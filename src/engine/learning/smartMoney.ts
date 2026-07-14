import { prisma } from "@/lib/prisma";
import { logger } from "../logging/logger";
import { WINNER_GAIN_PCT } from "./missed";

/**
 * Smart-money database (Phase 4).
 *
 * Collection: for every detected token, the early buyers are sampled once
 * (Helius parsed-transaction API; requires HELIUS_API_KEY — without it the
 * whole feature is inert and scores stay neutral).
 *
 * Grading: hourly, each wallet×token event older than 24h is graded from
 * the missed-opportunity tracker's outcome for that mint (winner / rug /
 * flat). Wallet scores are Laplace-smoothed winner rates — a wallet with 2
 * lucky buys cannot outrank one with 20 graded buys.
 *
 * Signal: when ≥2 PROVEN wallets (score ≥65 over ≥5 graded tokens) bought
 * the current token, the trade score gets a small bounded bonus (max +8).
 * Never negative, never a gate, never the deciding factor — measured
 * confidence only.
 */

export const PROVEN_SCORE = 65;
export const PROVEN_MIN_TOKENS = 5;
const MAX_BUYERS_PER_TOKEN = 25;
const READING_TTL_MS = 10 * 60_000;

// ── pure scoring helpers (unit-tested) ──────────────────────────────────────

export function classifyTokenOutcome(
  maxGainPct: number | null,
  rugged: boolean | null
): "winner" | "rug" | "flat" {
  if (rugged === true) return "rug";
  if ((maxGainPct ?? 0) >= WINNER_GAIN_PCT) return "winner";
  return "flat";
}

/** Laplace-smoothed winner rate (0–100), rug-penalized. */
export function walletScore(wins: number, rugs: number, tokens: number): number {
  if (tokens <= 0) return 50;
  const smoothed = (wins + 1) / (tokens + 2);
  const rugPenalty = (rugs / tokens) * 15; // habitual rug-buyers score down
  return Math.max(0, Math.min(100, Math.round(smoothed * 100 - rugPenalty)));
}

export interface SmartMoneyReading {
  buyersSampled: number;
  knownWallets: number; // with any graded history
  provenBuyers: number; // score ≥ PROVEN_SCORE over ≥ PROVEN_MIN_TOKENS
  avgProvenScore: number | null;
}

/** Bounded confidence bonus: +0 (no signal) … +8 (broad proven interest). */
export function smartMoneyDelta(r: SmartMoneyReading | null): { delta: number; detail: string } {
  if (!r || r.buyersSampled === 0) return { delta: 0, detail: "no buyer data (neutral)" };
  if (r.provenBuyers >= 4) return { delta: 8, detail: `${r.provenBuyers} historically profitable wallets bought (avg score ${r.avgProvenScore})` };
  if (r.provenBuyers >= 2) return { delta: 5, detail: `${r.provenBuyers} historically profitable wallets bought (avg score ${r.avgProvenScore})` };
  if (r.provenBuyers === 1) return { delta: 2, detail: `1 historically profitable wallet bought — never decisive on its own` };
  return { delta: 0, detail: `${r.buyersSampled} buyers sampled, none with a proven record (neutral)` };
}

// ── collection (Helius-gated) ────────────────────────────────────────────────

async function fetchEarlyBuyers(mint: string): Promise<string[]> {
  const key = process.env.HELIUS_API_KEY;
  if (!key) return [];
  try {
    const res = await fetch(
      `https://api.helius.xyz/v0/addresses/${mint}/transactions?api-key=${key}&type=SWAP&limit=50`,
      { signal: AbortSignal.timeout(8000) }
    );
    if (!res.ok) return [];
    const txs = (await res.json()) as Array<{
      feePayer?: string;
      tokenTransfers?: Array<{ mint?: string; toUserAccount?: string; tokenAmount?: number }>;
    }>;
    const buyers = new Set<string>();
    for (const tx of txs) {
      const received = tx.tokenTransfers?.some(
        (t) => t.mint === mint && (t.tokenAmount ?? 0) > 0 && t.toUserAccount === tx.feePayer
      );
      if (received && tx.feePayer) buyers.add(tx.feePayer);
      if (buyers.size >= MAX_BUYERS_PER_TOKEN) break;
    }
    return [...buyers];
  } catch {
    return [];
  }
}

const readingCache = new Map<string, { at: number; reading: SmartMoneyReading }>();

/** Sample buyers for a token (once per TTL), record them, score the group. */
export async function getSmartMoneyReading(mint: string): Promise<SmartMoneyReading | null> {
  if (!process.env.HELIUS_API_KEY) return null;
  const cached = readingCache.get(mint);
  if (cached && Date.now() - cached.at < READING_TTL_MS) return cached.reading;

  const buyers = await fetchEarlyBuyers(mint);
  // Record wallet×token events so grading builds every wallet's history.
  for (const address of buyers) {
    await prisma.walletTokenEvent
      .upsert({ where: { address_mint: { address, mint } }, create: { address, mint }, update: {} })
      .catch(() => {});
  }
  const known = buyers.length
    ? await prisma.smartWallet.findMany({ where: { address: { in: buyers }, tokensBought: { gt: 0 } } })
    : [];
  const proven = known.filter((w) => w.score >= PROVEN_SCORE && w.tokensBought >= PROVEN_MIN_TOKENS);
  const reading: SmartMoneyReading = {
    buyersSampled: buyers.length,
    knownWallets: known.length,
    provenBuyers: proven.length,
    avgProvenScore: proven.length
      ? Math.round(proven.reduce((a, w) => a + w.score, 0) / proven.length)
      : null,
  };
  readingCache.set(mint, { at: Date.now(), reading });
  if (readingCache.size > 2000) readingCache.clear();
  return reading;
}

// ── grading (hourly) ─────────────────────────────────────────────────────────

export async function gradeWalletEvents(): Promise<void> {
  const pending = await prisma.walletTokenEvent.findMany({
    where: { graded: false, at: { lt: new Date(Date.now() - 24 * 3_600_000) } },
    take: 300,
  });
  if (pending.length === 0) return;

  const mints = [...new Set(pending.map((p) => p.mint))];
  const outcomes = await prisma.missedOpportunity.findMany({
    where: { mint: { in: mints }, doneAt: { not: null } },
    select: { mint: true, maxGainPct: true, rugged: true },
  });
  const byMint = new Map(outcomes.map((o) => [o.mint, o]));

  const touched = new Set<string>();
  for (const e of pending) {
    const o = byMint.get(e.mint);
    // No graded outcome for this mint (we bought it, or tracking was full):
    // after 72h mark unknown so the queue can't grow forever.
    if (!o) {
      if (Date.now() - e.at.getTime() > 72 * 3_600_000) {
        await prisma.walletTokenEvent
          .update({ where: { id: e.id }, data: { graded: true, outcome: "unknown" } })
          .catch(() => {});
      }
      continue;
    }
    const outcome = classifyTokenOutcome(o.maxGainPct, o.rugged);
    await prisma.walletTokenEvent
      .update({ where: { id: e.id }, data: { graded: true, outcome, maxGainPct: o.maxGainPct } })
      .catch(() => {});
    touched.add(e.address);
  }

  // Recompute aggregates for the wallets whose history changed.
  for (const address of touched) {
    const events = await prisma.walletTokenEvent.findMany({
      where: { address, graded: true, outcome: { in: ["winner", "rug", "flat"] } },
      select: { outcome: true, maxGainPct: true },
    });
    const wins = events.filter((e) => e.outcome === "winner").length;
    const rugs = events.filter((e) => e.outcome === "rug").length;
    const gains = events.map((e) => e.maxGainPct).filter((v): v is number => v != null);
    await prisma.smartWallet
      .upsert({
        where: { address },
        create: {
          address,
          tokensBought: events.length,
          wins,
          rugs,
          avgTokenGainPct: gains.length ? gains.reduce((a, b) => a + b, 0) / gains.length : null,
          score: walletScore(wins, rugs, events.length),
        },
        update: {
          lastSeenAt: new Date(),
          tokensBought: events.length,
          wins,
          rugs,
          avgTokenGainPct: gains.length ? gains.reduce((a, b) => a + b, 0) / gains.length : null,
          score: walletScore(wins, rugs, events.length),
        },
      })
      .catch(() => {});
  }
  if (touched.size > 0) {
    logger.debug("scoring", `smart-money grading: ${pending.length} events processed, ${touched.size} wallet(s) rescored`);
  }
}
