import type { BotSettings } from "@/lib/validation";

export interface RiskState {
  openPositions: number;
  exposureSol: number; // SOL currently deployed in open positions
  dailyRealizedSol: number; // realized PnL today (negative = loss)
  lastLossAt: Date | null;
  emergencyStopped: boolean;
  now?: Date; // injectable for tests
}

export interface RiskDecision {
  allowed: boolean;
  /** actual SOL amount to use (buyAmount clamped by per-trade/exposure caps) */
  sizeSol: number;
  reasons: string[];
}

// ── Per-pair discipline ──────────────────────────────────────────────────────

/** A pair with 2 consecutive losses is locked for this long. */
export const PAIR_LOCK_HOURS = 24;

export interface PairTradeHistory {
  /** most recent closed positions on this mint, newest first (2 is enough) */
  recentClosed: Array<{ pnlSol: number | null; closedAt: Date | null }>;
  now?: Date;
}

/**
 * Pair-level cooldown and locking, evaluated before any re-buy of a mint:
 *  - last trade on the pair was a loss and is still inside lossCooldownMin
 *    → cooling down (no revenge trading the same coin)
 *  - last TWO trades on the pair were losses within PAIR_LOCK_HOURS
 *    → pair locked for the day (the pair is telling us something)
 * Returns the human-readable block reason, or null when trading is allowed.
 */
export function checkPairHistory(s: BotSettings, h: PairTradeHistory): string | null {
  const now = h.now ?? new Date();
  const closed = h.recentClosed.filter((p) => p.closedAt != null);
  if (closed.length === 0) return null;

  const [last, prev] = closed;
  const lastLoss = (last.pnlSol ?? 0) <= 0;

  if (lastLoss && prev && (prev.pnlSol ?? 0) <= 0) {
    const hoursSince = (now.getTime() - last.closedAt!.getTime()) / 3_600_000;
    if (hoursSince < PAIR_LOCK_HOURS) {
      return `pair locked: 2 consecutive losses on this mint (last ${hoursSince.toFixed(1)}h ago; unlocks after ${PAIR_LOCK_HOURS}h)`;
    }
  }

  if (lastLoss && s.lossCooldownMin > 0) {
    const minSince = (now.getTime() - last.closedAt!.getTime()) / 60_000;
    if (minSince < s.lossCooldownMin) {
      return `pair cooling down: previous trade on this mint was a loss ${minSince.toFixed(1)} min ago (cooldown ${s.lossCooldownMin} min)`;
    }
  }

  return null;
}

// ── Condition-aware sizing ───────────────────────────────────────────────────

export interface TradeConditions {
  volatility5m: number | null;
  estSlippagePctFor1Sol: number | null;
  rpcLatencyMs: number | null;
}

export interface SizedDecision {
  sizeSol: number;
  /** why the size was reduced (empty = full size) */
  notes: string[];
}

/**
 * Reduce position size when execution conditions are adverse: high
 * volatility (wider effective stop), elevated slippage (worse fills), or
 * degraded RPC latency (late entries AND late exits). Each adverse
 * condition halves the size; the floor is 25% of the base size.
 */
export function adjustSizeForConditions(baseSizeSol: number, c: TradeConditions): SizedDecision {
  const notes: string[] = [];
  let mult = 1;
  if (c.volatility5m !== null && c.volatility5m > 15) {
    mult *= 0.5;
    notes.push(`volatility ${c.volatility5m.toFixed(1)}% > 15% — half size`);
  }
  if (c.estSlippagePctFor1Sol !== null && c.estSlippagePctFor1Sol > 2) {
    mult *= 0.5;
    notes.push(`slippage ~${c.estSlippagePctFor1Sol.toFixed(1)}% > 2% — half size`);
  }
  if (c.rpcLatencyMs !== null && c.rpcLatencyMs > 1_000) {
    mult *= 0.5;
    notes.push(`RPC latency ${c.rpcLatencyMs}ms > 1000ms — half size`);
  }
  mult = Math.max(mult, 0.25);
  return { sizeSol: baseSizeSol * mult, notes };
}

/**
 * Portfolio-level gate applied before any buy. Pure function — all state is
 * passed in, so it is deterministic and fully unit-testable.
 */
export function checkRisk(s: BotSettings, r: RiskState): RiskDecision {
  const reasons: string[] = [];
  const now = r.now ?? new Date();

  if (r.emergencyStopped) reasons.push("emergency stop is active");

  if (r.openPositions >= s.maxOpenPositions)
    reasons.push(`open positions ${r.openPositions} at limit ${s.maxOpenPositions}`);

  if (r.dailyRealizedSol <= -s.maxDailyLossSol)
    reasons.push(`daily loss ${(-r.dailyRealizedSol).toFixed(3)} SOL hit limit ${s.maxDailyLossSol}`);

  if (s.dailyProfitTarget !== null && r.dailyRealizedSol >= s.dailyProfitTarget)
    reasons.push(`daily profit target ${s.dailyProfitTarget} SOL reached — done for the day`);

  if (r.lastLossAt && s.lossCooldownMin > 0) {
    const elapsedMin = (now.getTime() - r.lastLossAt.getTime()) / 60_000;
    if (elapsedMin < s.lossCooldownMin)
      reasons.push(`in loss cooldown (${(s.lossCooldownMin - elapsedMin).toFixed(1)} min remaining)`);
  }

  const sizeSol = Math.min(s.buyAmountSol, s.maxSolPerTrade, s.maxExposureSol - r.exposureSol);
  if (sizeSol <= 0)
    reasons.push(`exposure ${r.exposureSol.toFixed(3)} SOL at cap ${s.maxExposureSol}`);

  return { allowed: reasons.length === 0, sizeSol: Math.max(0, sizeSol), reasons };
}
