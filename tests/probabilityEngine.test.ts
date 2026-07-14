import { describe, expect, it } from "vitest";
import {
  buildCalibration,
  probabilityOfSuccess,
  validateFeatures,
} from "@/engine/learning/featureValidation";
import { classifyRegime } from "@/engine/learning/regime";
import type { ClosedTrade } from "@/engine/learning/tradeStats";

const T0 = new Date("2026-07-01T10:00:00Z").getTime();

function trade(i: number, win: boolean, overrides: Partial<ClosedTrade> = {}): ClosedTrade {
  const openedAt = new Date(T0 + i * 600_000);
  return {
    pnlSol: win ? 0.02 : -0.015,
    pnlPct: win ? 15 : -8,
    entrySol: 0.1,
    openedAt,
    closedAt: new Date(openedAt.getTime() + 5 * 60_000),
    exitReason: null,
    exitKind: win ? "take_profit" : "stop_loss",
    entryReason: null,
    score: 75,
    entryMarketCapUsd: 150_000,
    entryLiquiditySol: 60,
    tokenAgeMinAtEntry: 5,
    detectionToBuyMs: 4_000,
    maxUnrealizedPnlPct: null,
    maxDrawdownPct: null,
    entryMetrics: null,
    entryContext: null,
    paper: true,
    ...overrides,
  };
}

describe("feature validation", () => {
  it("ranks features by measured predictive power with strong/weak splits", () => {
    const trades: ClosedTrade[] = [];
    for (let i = 0; i < 80; i++) {
      const win = i % 2 === 0;
      trades.push(
        trade(i, win, {
          // buy pressure strongly separates winners from losers…
          entryContext: { buySellRatio: win ? 2.5 : 0.9, momentumAcceleration: 0.1 },
          // …liquidity is pure noise
          entryLiquiditySol: 40 + (i % 7) * 10,
        })
      );
    }
    const stats = validateFeatures(trades);
    const bp = stats.find((s) => s.feature === "buy pressure")!;
    const liq = stats.find((s) => s.feature === "liquidity")!;
    expect(bp.importancePct).toBeGreaterThan(liq.importancePct);
    expect(bp.strongWinRate!).toBeGreaterThan(bp.weakWinRate!);
    expect(bp.correlation!).toBeGreaterThan(0.5);
    expect(Math.abs(liq.correlation ?? 0)).toBeLessThan(0.25);
    // importance shares are a distribution
    const total = stats.reduce((a, s) => a + s.importancePct, 0);
    expect(total).toBeGreaterThan(99);
    expect(total).toBeLessThan(101);
  });

  it("reports drift when a feature's predictive power changes over time", () => {
    const trades: ClosedTrade[] = [];
    // first half: buy pressure predicts perfectly; second half: pure noise
    for (let i = 0; i < 60; i++) {
      const win = i % 2 === 0;
      trades.push(trade(i, win, { entryContext: { buySellRatio: win ? 2.5 : 0.9 } }));
    }
    for (let i = 60; i < 120; i++) {
      const win = i % 2 === 0;
      trades.push(trade(i, win, { entryContext: { buySellRatio: i % 3 === 0 ? 2.5 : 0.9 } }));
    }
    const bp = validateFeatures(trades).find((s) => s.feature === "buy pressure")!;
    expect(bp.drift).toBe("less_useful");
  });
});

describe("probability calibration", () => {
  it("estimates P(success) from measured win rates per score bucket", () => {
    const trades: ClosedTrade[] = [];
    for (let i = 0; i < 40; i++) trades.push(trade(i, i % 10 < 8, { score: 90 })); // 80% WR at 85-92
    for (let i = 40; i < 80; i++) trades.push(trade(i, i % 10 < 3, { score: 72 })); // 30% WR at 70-78
    const cal = buildCalibration(trades);
    const high = probabilityOfSuccess(cal, 90)!;
    const low = probabilityOfSuccess(cal, 72)!;
    expect(high.pct).toBeGreaterThan(70);
    expect(low.pct).toBeLessThan(40);
    expect(high.basis).toMatch(/40 historical trades/);
  });

  it("smooths tiny buckets toward 50% and refuses to rate without history", () => {
    const cal = buildCalibration([trade(0, true, { score: 95 })]);
    expect(probabilityOfSuccess(cal, 95)).toBeNull(); // < 20 total trades
    const trades = Array.from({ length: 25 }, (_, i) => trade(i, true, { score: 72 }));
    const sparse = buildCalibration(trades);
    // the 85-92 bucket has 0 trades → smoothed to 50%, not 0% or 100%
    const p = probabilityOfSuccess(sparse, 90)!;
    expect(p.pct).toBe(50);
  });
});

describe("market regime classification", () => {
  it("classifies pump mania, bull, bear/risk-off, and quiet markets", () => {
    expect(
      classifyRegime({
        tokenChangesPct: [30, 45, 12, 60, 8, 25],
        avgBuySellRatio: 1.8,
        detectionsPerHour: 20,
        avgVolume5mUsd: 30_000,
      }).regime
    ).toBe("pump_mania");

    expect(
      classifyRegime({
        tokenChangesPct: [5, 8, 12, -2, 6, 9],
        avgBuySellRatio: 1.3,
        detectionsPerHour: 4,
        avgVolume5mUsd: 15_000,
      }).regime
    ).toBe("bull_trend");

    expect(
      classifyRegime({
        tokenChangesPct: [-15, -22, -8, 3, -12, -18],
        avgBuySellRatio: 0.7,
        detectionsPerHour: 3,
        avgVolume5mUsd: 12_000,
      }).regime
    ).toBe("bear_trend");

    expect(
      classifyRegime({
        tokenChangesPct: [-15, -22, -8, -3, -12],
        avgBuySellRatio: 0.8,
        detectionsPerHour: 1,
        avgVolume5mUsd: 2_000,
      }).regime
    ).toBe("risk_off");

    expect(
      classifyRegime({
        tokenChangesPct: [80, -60, 45, -30, 70, -55],
        avgBuySellRatio: 1.0,
        detectionsPerHour: 5,
        avgVolume5mUsd: 20_000,
      }).regime
    ).toBe("high_volatility");

    expect(classifyRegime({ tokenChangesPct: [1], avgBuySellRatio: null, detectionsPerHour: 0, avgVolume5mUsd: null }).regime).toBe(
      "low_volatility"
    );
  });

  it("always reports its inputs for transparency", () => {
    const r = classifyRegime({
      tokenChangesPct: [5, -3, 8, 2],
      avgBuySellRatio: 1.05,
      detectionsPerHour: 3,
      avgVolume5mUsd: 9_000,
    });
    expect(r.inputs.tokensSampled).toBe(4);
    expect(r.detail.length).toBeGreaterThan(5);
  });
});
