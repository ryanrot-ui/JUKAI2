import type { ClosedTrade } from "./tradeStats";

/**
 * Feature validation: measures — never assumes — the predictive value of
 * every signal the scoring engine uses, from realized trade outcomes.
 *
 * For each feature: win rate / avg return / profit factor / expected value
 * in the feature's strong half vs weak half, plus the point-biserial
 * correlation with winning. Importance ranks features by |correlation|
 * share. Drift compares the correlation on the older half of history vs the
 * recent half, answering "which indicators are becoming more/less useful"
 * — only when both halves have enough samples.
 */

export interface FeatureStat {
  feature: string;
  samples: number;
  correlation: number | null; // with winning, -1..1
  importancePct: number; // share of total |correlation|
  // strong half (value above median) vs weak half
  strongWinRate: number | null;
  weakWinRate: number | null;
  strongAvgReturnPct: number | null;
  weakAvgReturnPct: number | null;
  strongProfitFactor: number | null;
  strongExpectedValueSol: number | null;
  drift: "more_useful" | "less_useful" | "stable" | "unrated";
  driftDetail: string | null;
}

const MIN_SAMPLES = 30;
const MIN_HALF = 25;

interface FeatureDef {
  name: string;
  value: (t: ClosedTrade) => number | null;
}

const FEATURES: FeatureDef[] = [
  { name: "liquidity", value: (t) => t.entryLiquiditySol },
  { name: "market cap", value: (t) => t.entryMarketCapUsd },
  { name: "volume (5m)", value: (t) => t.entryContext?.volume5mUsd ?? null },
  { name: "buy pressure", value: (t) => t.entryContext?.buySellRatio ?? null },
  { name: "momentum", value: (t) => t.entryContext?.momentum ?? null },
  { name: "momentum acceleration", value: (t) => t.entryContext?.momentumAcceleration ?? null },
  { name: "volatility", value: (t) => t.entryContext?.volatility5m ?? null },
  { name: "slippage estimate", value: (t) => t.entryContext?.estSlippagePctFor1Sol ?? null },
  { name: "holders", value: (t) => t.entryContext?.holderCount ?? null },
  { name: "token age", value: (t) => t.tokenAgeMinAtEntry },
  { name: "scanner score", value: (t) => t.score },
  // 0..1 metric-quality values from the scoring breakdown
  { name: "holder distribution (metric)", value: (t) => t.entryMetrics?.distribution ?? null },
  { name: "wallet quality (metric)", value: (t) => t.entryMetrics?.walletQuality ?? null },
  { name: "safety (metric)", value: (t) => t.entryMetrics?.safety ?? null },
  { name: "tx velocity (metric)", value: (t) => t.entryMetrics?.activity ?? null },
  { name: "volume growth (metric)", value: (t) => t.entryMetrics?.volumeGrowth ?? null },
];

function pointBiserial(values: number[], wins: boolean[]): number | null {
  const n = values.length;
  if (n < MIN_SAMPLES) return null;
  const winVals = values.filter((_, i) => wins[i]);
  const loseVals = values.filter((_, i) => !wins[i]);
  if (winVals.length < 5 || loseVals.length < 5) return null;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  const sd = Math.sqrt(values.reduce((a, v) => a + (v - mean) ** 2, 0) / n);
  if (sd === 0) return 0;
  const mWin = winVals.reduce((a, b) => a + b, 0) / winVals.length;
  const mLose = loseVals.reduce((a, b) => a + b, 0) / loseVals.length;
  const p = winVals.length / n;
  return ((mWin - mLose) / sd) * Math.sqrt(p * (1 - p));
}

function half(rows: Array<{ v: number; t: ClosedTrade }>, strong: boolean) {
  const sorted = [...rows].sort((a, b) => a.v - b.v);
  const mid = Math.floor(sorted.length / 2);
  return (strong ? sorted.slice(mid) : sorted.slice(0, mid)).map((r) => r.t);
}

const wr = (ts: ClosedTrade[]) => (ts.length ? (ts.filter((t) => t.pnlSol > 0).length / ts.length) * 100 : null);
const avgRet = (ts: ClosedTrade[]) => {
  const p = ts.map((t) => t.pnlPct).filter((v): v is number => v != null);
  return p.length ? p.reduce((a, b) => a + b, 0) / p.length : null;
};
const pf = (ts: ClosedTrade[]) => {
  const gw = ts.filter((t) => t.pnlSol > 0).reduce((a, t) => a + t.pnlSol, 0);
  const gl = Math.abs(ts.filter((t) => t.pnlSol <= 0).reduce((a, t) => a + t.pnlSol, 0));
  return gl > 0 ? gw / gl : null;
};
const ev = (ts: ClosedTrade[]) => (ts.length ? ts.reduce((a, t) => a + t.pnlSol, 0) / ts.length : null);

export function validateFeatures(trades: ClosedTrade[]): FeatureStat[] {
  const chron = [...trades].sort((a, b) => a.closedAt.getTime() - b.closedAt.getTime());
  const stats: Array<Omit<FeatureStat, "importancePct">> = [];

  for (const f of FEATURES) {
    const rows = chron
      .map((t) => ({ v: f.value(t), t }))
      .filter((r): r is { v: number; t: ClosedTrade } => r.v != null && Number.isFinite(r.v));
    if (rows.length < MIN_SAMPLES) continue;

    const corr = pointBiserial(rows.map((r) => r.v), rows.map((r) => r.t.pnlSol > 0));
    const strong = half(rows, true);
    const weak = half(rows, false);

    // Drift: correlation on the older half vs the recent half of history.
    let drift: FeatureStat["drift"] = "unrated";
    let driftDetail: string | null = null;
    const mid = Math.floor(rows.length / 2);
    if (mid >= MIN_HALF) {
      const older = rows.slice(0, mid);
      const recent = rows.slice(mid);
      const cOld = pointBiserial(older.map((r) => r.v), older.map((r) => r.t.pnlSol > 0));
      const cNew = pointBiserial(recent.map((r) => r.v), recent.map((r) => r.t.pnlSol > 0));
      if (cOld != null && cNew != null) {
        const delta = Math.abs(cNew) - Math.abs(cOld);
        drift = delta > 0.08 ? "more_useful" : delta < -0.08 ? "less_useful" : "stable";
        driftDetail = `|corr| ${Math.abs(cOld).toFixed(2)} (older) → ${Math.abs(cNew).toFixed(2)} (recent)`;
      }
    }

    stats.push({
      feature: f.name,
      samples: rows.length,
      correlation: corr,
      strongWinRate: wr(strong),
      weakWinRate: wr(weak),
      strongAvgReturnPct: avgRet(strong),
      weakAvgReturnPct: avgRet(weak),
      strongProfitFactor: pf(strong),
      strongExpectedValueSol: ev(strong),
      drift,
      driftDetail,
    });
  }

  const totalAbs = stats.reduce((a, s) => a + Math.abs(s.correlation ?? 0), 0);
  return stats
    .map((s) => ({
      ...s,
      importancePct: totalAbs > 0 ? (Math.abs(s.correlation ?? 0) / totalAbs) * 100 : 0,
    }))
    .sort((a, b) => b.importancePct - a.importancePct);
}

// ── Success-probability calibration ─────────────────────────────────────────

export interface CalibrationBucket {
  label: string;
  lo: number;
  hi: number;
  trades: number;
  winRatePct: number; // Laplace-smoothed
}

export interface Calibration {
  buckets: CalibrationBucket[];
  totalTrades: number;
}

const SCORE_BUCKETS: Array<[number, number]> = [
  [0, 60],
  [60, 70],
  [70, 78],
  [78, 85],
  [85, 92],
  [92, 101],
];

/**
 * Calibrates "probability of success" from the measured win rate per score
 * bucket (Laplace-smoothed toward 50% so tiny buckets can't claim
 * certainty). This turns the 0–100 score into an evidence-based estimate:
 * "historically, trades scored like this one won X% of the time."
 */
export function buildCalibration(trades: ClosedTrade[]): Calibration {
  const scored = trades.filter((t) => t.score != null);
  const buckets = SCORE_BUCKETS.map(([lo, hi]) => {
    const ts = scored.filter((t) => t.score! >= lo && t.score! < hi);
    const wins = ts.filter((t) => t.pnlSol > 0).length;
    // Laplace smoothing: +2 pseudo-trades at 50%
    const winRatePct = ((wins + 1) / (ts.length + 2)) * 100;
    return { label: hi > 100 ? `${lo}+` : `${lo}-${hi - 1}`, lo, hi, trades: ts.length, winRatePct };
  });
  return { buckets, totalTrades: scored.length };
}

export function probabilityOfSuccess(cal: Calibration, score: number): { pct: number; basis: string } | null {
  const b = cal.buckets.find((x) => score >= x.lo && score < x.hi);
  if (!b || cal.totalTrades < 20) return null;
  return {
    pct: Math.round(b.winRatePct),
    basis: `calibrated on ${b.trades} historical trades scored ${b.label} (${cal.totalTrades} total)`,
  };
}
