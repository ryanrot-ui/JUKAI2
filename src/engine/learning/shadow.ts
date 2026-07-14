import { prisma } from "@/lib/prisma";
import { logger } from "../logging/logger";
import { evaluateExit } from "../trading/exitRules";
import type { BotSettings } from "@/lib/validation";

/**
 * Shadow strategy: every opportunity is evaluated twice — once by the live
 * strategy (which trades) and once by the CANDIDATE strategy (the
 * optimizer's recommended weights), which runs silently.
 *
 * Divergent entries (candidate buys, live doesn't) are recorded as
 * ShadowTrade rows and later resolved by replaying the token's recorded
 * snapshots through the production exit engine — hypothetical PnL on real
 * subsequent data. Entries the live strategy takes carry the candidate's
 * score in entrySignals, so both sides of the comparison are grounded in
 * actual outcomes. The comparison only recommends switching after enough
 * opportunities AND a statistically significant win-rate advantage.
 */

export const SHADOW_MIN_OPPORTUNITIES = 500;
const RESOLVE_AFTER_MS = 3 * 60_000; // give the token time to print data
const UNRESOLVABLE_AFTER_MS = 48 * 3_600_000;

export async function recordShadowTrade(input: {
  mint: string;
  tokenId: string;
  entryPriceUsd: number;
  candidateScore: number;
  liveScore: number;
}): Promise<void> {
  try {
    const existing = await prisma.shadowTrade.findFirst({ where: { mint: input.mint } });
    if (existing) return; // one hypothetical entry per token
    await prisma.shadowTrade.create({ data: { ...input, strategy: "candidate" } });
    logger.debug("scoring", `shadow entry ${input.mint.slice(0, 8)}… (candidate ${input.candidateScore} vs live ${input.liveScore})`);
  } catch (e) {
    logger.debug("scoring", `shadow record failed: ${(e as Error).message}`);
  }
}

/** Resolve pending shadow entries against the token's recorded snapshots. */
export async function resolveShadowTrades(settings: BotSettings): Promise<number> {
  const pending = await prisma.shadowTrade.findMany({
    where: { resolved: false, at: { lt: new Date(Date.now() - RESOLVE_AFTER_MS) } },
    take: 50,
  });
  let resolved = 0;
  for (const s of pending) {
    const snaps = s.tokenId
      ? await prisma.tokenSnapshot.findMany({
          where: { tokenId: s.tokenId, at: { gt: s.at } },
          orderBy: { at: "asc" },
          select: { at: true, priceUsd: true, liquiditySol: true, volume5mUsd: true, buySellRatio: true },
        })
      : [];
    const priced = snaps.filter((x) => x.priceUsd != null);

    if (priced.length < 2) {
      // No follow-up data (token archived / never indexed). Age out.
      if (Date.now() - s.at.getTime() > UNRESOLVABLE_AFTER_MS) {
        await prisma.shadowTrade.update({
          where: { id: s.id },
          data: { resolved: true, exitKind: "unresolvable", closedAt: new Date() },
        });
        resolved++;
      }
      continue;
    }

    const entryLiq = priced[0].liquiditySol;
    const entryVol = priced[0].volume5mUsd;
    let peak = s.entryPriceUsd;
    let exit: { pnlPct: number; kind: string; at: Date } | null = null;
    for (const p of priced) {
      peak = Math.max(peak, p.priceUsd!);
      const decision = evaluateExit(settings, {
        entryPriceUsd: s.entryPriceUsd,
        currentPriceUsd: p.priceUsd!,
        peakPriceUsd: peak,
        openedAt: s.at,
        now: p.at,
        liquidityDropPct:
          entryLiq && p.liquiditySol != null && entryLiq > 0
            ? ((p.liquiditySol - entryLiq) / entryLiq) * 100
            : null,
        buySellRatio5m: p.buySellRatio,
        volume5mUsd: p.volume5mUsd,
        entryVolume5mUsd: entryVol,
      });
      if (decision.exit) {
        exit = {
          pnlPct: ((p.priceUsd! - s.entryPriceUsd) / s.entryPriceUsd) * 100,
          kind: decision.kind ?? "other",
          at: p.at,
        };
        break;
      }
    }
    // Data ended while hypothetically open → close at the last known price,
    // but only once the series is clearly finished (token left the watchlist).
    if (!exit) {
      const last = priced[priced.length - 1];
      if (Date.now() - last.at.getTime() < 30 * 60_000) continue; // still printing — wait
      exit = {
        pnlPct: ((last.priceUsd! - s.entryPriceUsd) / s.entryPriceUsd) * 100,
        kind: "data_end",
        at: last.at,
      };
    }
    await prisma.shadowTrade.update({
      where: { id: s.id },
      data: { resolved: true, pnlPct: exit.pnlPct, exitKind: exit.kind, closedAt: exit.at },
    });
    resolved++;
  }
  if (resolved > 0) logger.debug("scoring", `resolved ${resolved} shadow trade(s)`);
  return resolved;
}

// ── Comparison ───────────────────────────────────────────────────────────────

export interface StrategyLine {
  trades: number;
  winRate: number | null;
  avgPnlPct: number | null;
  profitFactorPct: number | null; // on % returns
  maxDrawdownPct: number | null; // cumulative % curve
  totalPnlPct: number;
}

export interface ShadowComparison {
  activeSince: string | null;
  opportunities: number;
  minOpportunities: number;
  ready: boolean;
  live: StrategyLine;
  candidate: StrategyLine;
  candidateExtraTrades: number; // resolved shadow-only entries
  verdict: string;
}

function line(pnls: number[]): StrategyLine {
  const wins = pnls.filter((p) => p > 0);
  const losses = pnls.filter((p) => p <= 0);
  const gw = wins.reduce((a, b) => a + b, 0);
  const gl = Math.abs(losses.reduce((a, b) => a + b, 0));
  let equity = 0;
  let peak = 0;
  let dd = 0;
  for (const p of pnls) {
    equity += p;
    peak = Math.max(peak, equity);
    dd = Math.max(dd, peak - equity);
  }
  return {
    trades: pnls.length,
    winRate: pnls.length ? (wins.length / pnls.length) * 100 : null,
    avgPnlPct: pnls.length ? pnls.reduce((a, b) => a + b, 0) / pnls.length : null,
    profitFactorPct: gl > 0 ? gw / gl : null,
    maxDrawdownPct: pnls.length ? dd : null,
    totalPnlPct: pnls.reduce((a, b) => a + b, 0),
  };
}

export async function compareShadowStrategy(confidenceThreshold: number): Promise<ShadowComparison | null> {
  const first = await prisma.shadowTrade.findFirst({ orderBy: { at: "asc" }, select: { at: true } });
  if (!first) return null;

  const [opportunities, shadows, positions] = await Promise.all([
    prisma.scoreRecord.count({ where: { at: { gte: first.at } } }),
    prisma.shadowTrade.findMany({ where: { resolved: true, pnlPct: { not: null } } }),
    prisma.position.findMany({
      where: { status: "CLOSED", openedAt: { gte: first.at } },
      orderBy: { closedAt: "asc" },
      select: { pnlPct: true, entrySignals: true },
    }),
  ]);

  const livePnls = positions.map((p) => p.pnlPct).filter((v): v is number => v != null);
  // Candidate = live entries it also approved + its shadow-only entries
  const candidateFromLive = positions
    .filter((p) => {
      const sig = p.entrySignals as { candidateScore?: number } | null;
      return sig?.candidateScore == null || sig.candidateScore >= confidenceThreshold;
    })
    .map((p) => p.pnlPct)
    .filter((v): v is number => v != null);
  const shadowPnls = shadows.map((s) => s.pnlPct!) as number[];

  const live = line(livePnls);
  const candidate = line([...candidateFromLive, ...shadowPnls]);
  const ready = opportunities >= SHADOW_MIN_OPPORTUNITIES;

  let verdict: string;
  if (!ready) {
    verdict = `Collecting evidence: ${opportunities}/${SHADOW_MIN_OPPORTUNITIES} opportunities evaluated by both strategies. No recommendation yet.`;
  } else if (
    candidate.trades >= 30 &&
    live.trades >= 30 &&
    (candidate.winRate ?? 0) > (live.winRate ?? 0) &&
    candidate.totalPnlPct > live.totalPnlPct &&
    (candidate.maxDrawdownPct ?? Infinity) <= (live.maxDrawdownPct ?? 0) * 1.2
  ) {
    verdict = `Candidate outperforms live (win rate ${candidate.winRate?.toFixed(0)}% vs ${live.winRate?.toFixed(0)}%, total ${candidate.totalPnlPct.toFixed(0)}% vs ${live.totalPnlPct.toFixed(0)}%) over ${opportunities} opportunities — consider applying the recommended weights from the Analytics page.`;
  } else {
    verdict = `Candidate is not clearly superior yet (live ${live.winRate?.toFixed(0) ?? "–"}% WR / ${live.totalPnlPct.toFixed(0)}%, candidate ${candidate.winRate?.toFixed(0) ?? "–"}% WR / ${candidate.totalPnlPct.toFixed(0)}%). Keeping the live strategy.`;
  }

  return {
    activeSince: first.at.toISOString(),
    opportunities,
    minOpportunities: SHADOW_MIN_OPPORTUNITIES,
    ready,
    live,
    candidate,
    candidateExtraTrades: shadowPnls.length,
    verdict,
  };
}
