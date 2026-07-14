/**
 * Market regime detection from the scanner's own recorded data — no external
 * feed needed. Classifies the memecoin market the bot is actually trading
 * in, from the last hour of token snapshots:
 *
 *   pump_mania      — detections pouring in AND broad buy pressure
 *   bull_trend      — most watched tokens rising, buyers in control
 *   bear_trend      — most falling, sellers in control
 *   risk_off        — falling prices AND drying volume
 *   high_volatility — big dispersion of per-token price swings
 *   low_volatility  — hardly anything moving
 *   sideways        — everything else
 *
 * The active regime is stamped into every entry's signals (and therefore
 * into the lessons database as a `regime_*` tag), so "which conditions do
 * we actually make money in" becomes measurable per regime.
 */

export type MarketRegime =
  | "pump_mania"
  | "bull_trend"
  | "bear_trend"
  | "risk_off"
  | "high_volatility"
  | "low_volatility"
  | "sideways";

export interface RegimeInput {
  /** per-token % price change across the window (first→last snapshot) */
  tokenChangesPct: number[];
  /** average 5m buy/sell ratio across recent snapshots */
  avgBuySellRatio: number | null;
  /** new tokens detected in the window */
  detectionsPerHour: number;
  /** average 5m volume across recent snapshots, USD */
  avgVolume5mUsd: number | null;
}

export interface RegimeResult {
  regime: MarketRegime;
  detail: string;
  inputs: {
    tokensSampled: number;
    risingSharePct: number | null;
    medianChangePct: number | null;
    dispersionPct: number | null;
    avgBuySellRatio: number | null;
    detectionsPerHour: number;
  };
}

const median = (xs: number[]) => {
  if (xs.length === 0) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

export function classifyRegime(input: RegimeInput): RegimeResult {
  const changes = input.tokenChangesPct.filter((v) => Number.isFinite(v));
  const n = changes.length;
  const rising = n ? changes.filter((c) => c > 0).length / n : null;
  const med = median(changes);
  const mean = n ? changes.reduce((a, b) => a + b, 0) / n : 0;
  const dispersion = n >= 3 ? Math.sqrt(changes.reduce((a, c) => a + (c - mean) ** 2, 0) / n) : null;
  const ratio = input.avgBuySellRatio;

  const inputs = {
    tokensSampled: n,
    risingSharePct: rising != null ? rising * 100 : null,
    medianChangePct: med,
    dispersionPct: dispersion,
    avgBuySellRatio: ratio,
    detectionsPerHour: input.detectionsPerHour,
  };
  const make = (regime: MarketRegime, detail: string): RegimeResult => ({ regime, detail, inputs });

  if (n < 3) {
    return make("low_volatility", `only ${n} active tokens in the window — quiet market`);
  }

  if (input.detectionsPerHour >= 12 && (ratio ?? 0) >= 1.3 && (rising ?? 0) >= 0.5) {
    return make(
      "pump_mania",
      `${input.detectionsPerHour.toFixed(0)} migrations/h with broad buy pressure (${ratio?.toFixed(2)}) — froth`
    );
  }
  if ((rising ?? 0) <= 0.35 && (input.avgVolume5mUsd ?? Infinity) < 5_000) {
    return make("risk_off", `${((rising ?? 0) * 100).toFixed(0)}% of tokens rising and volume drying up`);
  }
  if (dispersion != null && dispersion >= 25) {
    return make("high_volatility", `per-token swings dispersed ±${dispersion.toFixed(0)}% — whipsaw conditions`);
  }
  if ((rising ?? 0) >= 0.6 && (ratio ?? 1) >= 1.1) {
    return make("bull_trend", `${((rising ?? 0) * 100).toFixed(0)}% of watched tokens rising, buy/sell ${ratio?.toFixed(2)}`);
  }
  if ((rising ?? 1) <= 0.4 || (ratio ?? 1) < 0.9) {
    return make("bear_trend", `${((rising ?? 0) * 100).toFixed(0)}% rising, buy/sell ${ratio?.toFixed(2) ?? "?"} — sellers in control`);
  }
  if (dispersion != null && dispersion < 5) {
    return make("low_volatility", `per-token swings only ±${dispersion.toFixed(1)}% — nothing moving`);
  }
  return make("sideways", `no dominant direction (${((rising ?? 0) * 100).toFixed(0)}% rising, dispersion ±${dispersion?.toFixed(0) ?? "?"}%)`);
}
