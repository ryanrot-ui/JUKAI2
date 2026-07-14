import { describe, expect, it } from "vitest";
import { evaluateBuyRules } from "@/engine/trading/rules";
import { scoreToken } from "@/engine/analysis/scoring";
import { emptyMetrics } from "@/engine/analysis/collectors";
import { evaluateExit } from "@/engine/trading/exitRules";
import {
  adjustSizeForConditions,
  checkPairHistory,
  PAIR_LOCK_HOURS,
} from "@/engine/trading/riskManager";
import { DEFAULT_SETTINGS } from "@/engine/config";
import type { TokenMetrics } from "@/engine/analysis/types";

/** A setup that confirms all 6 independent signals. */
function confirmedCandidate(): TokenMetrics {
  const m = emptyMetrics("TESTMINT1111111111111111111111111111111111", new Date(Date.now() - 5 * 60_000));
  Object.assign(m, {
    priceUsd: 0.0001,
    liquiditySol: 250,
    liquidityUsd: 37_500,
    marketCapUsd: 400_000,
    volume5mUsd: 40_000,
    volumeGrowthPct: 60,
    buySellRatio: 2.2,
    buys5m: 200,
    sells5m: 90,
    txPerMinute: 58,
    holderCount: 600,
    holderGrowth5m: 40,
    topHolderPct: 2.5,
    top10HolderPct: 14,
    devWalletPct: 1,
    freshWalletPct: 12,
    sniperWalletCount: 2,
    bundledWalletCount: 0,
    liquidityChangePct: 5,
    estSlippagePctFor1Sol: 0.8,
    volatility5m: 3,
    momentum: 1.2,
    momentumAcceleration: 0.3,
    mintAuthorityRevoked: true,
    freezeAuthorityRevoked: true,
    lpBurnedOrLockedPct: 100,
    isHoneypotSuspected: false,
    devSoldPct: 0,
    washTradingSuspected: false,
    artificialVolumeSuspected: false,
    priceChange5mPct: 8,
    priceChange1hPct: 30,
  });
  return m;
}

describe("confirmation gate (N-of-6 signal agreement)", () => {
  it("buys when enough independent signals confirm", () => {
    const m = confirmedCandidate();
    const d = evaluateBuyRules(m, scoreToken(m), DEFAULT_SETTINGS);
    expect(d.buy).toBe(true);
    const summary = d.trace.find((r) => r.rule === "signal agreement");
    expect(summary?.passed).toBe(true);
    expect(summary?.detail).toMatch(/6\/6/);
    expect(d.reasons[0]).toMatch(/6\/6 independent signals/);
  });

  it("WATCHes (not ignores) when too few signals confirm", () => {
    const m = confirmedCandidate();
    m.volumeGrowthPct = -20; // volume fading
    m.priceChange1hPct = -5; // against the larger trend
    m.volatility5m = 20; // choppy
    const s = { ...DEFAULT_SETTINGS, minConfirmations: 5 };
    const d = evaluateBuyRules(m, scoreToken(m), s);
    expect(d.buy).toBe(false);
    expect(d.action).toBe("watch"); // conviction can still build next cycle
    expect(d.reasons[0]).toMatch(/only 3\/6 independent signals/);
  });

  it("unknown data does not confirm (fail closed)", () => {
    const m = confirmedCandidate();
    m.volumeGrowthPct = null;
    m.priceChange1hPct = null;
    m.volatility5m = null;
    const s = { ...DEFAULT_SETTINGS, minConfirmations: 5 };
    const d = evaluateBuyRules(m, scoreToken(m), s);
    expect(d.buy).toBe(false);
    const summary = d.trace.find((r) => r.rule === "signal agreement");
    expect(summary?.passed).toBe(false);
  });

  it("wash trading kills the momentum confirmation even with holder growth", () => {
    const m = confirmedCandidate();
    m.washTradingSuspected = true;
    const c = evaluateBuyRules(m, scoreToken(m), DEFAULT_SETTINGS).trace.find(
      (r) => r.rule === "real momentum (social/on-chain)"
    );
    expect(c?.passed).toBe(false);
    expect(c?.detail).toMatch(/manufactured/);
  });

  it("minConfirmations 0 disables the gate", () => {
    const m = confirmedCandidate();
    m.volumeGrowthPct = null;
    m.priceChange1hPct = null;
    m.volatility5m = null;
    m.holderGrowth5m = null;
    const s = { ...DEFAULT_SETTINGS, minConfirmations: 0, confidenceThreshold: 40 };
    const d = evaluateBuyRules(m, scoreToken(m), s);
    expect(d.trace.find((r) => r.rule === "signal agreement")).toBeUndefined();
    expect(d.buy).toBe(true);
  });
});

describe("cost-vs-target gate", () => {
  it("hard-rejects when round-trip cost eats too much of the first target", () => {
    const m = confirmedCandidate();
    // 2×2.5 + 0.6 = 5.6% round trip vs 12/3 = 4% budget → reject
    m.estSlippagePctFor1Sol = 2.5;
    const d = evaluateBuyRules(m, scoreToken(m), DEFAULT_SETTINGS);
    expect(d.buy).toBe(false);
    expect(d.action).toBe("ignore");
    expect(d.reasons.join(" ")).toMatch(/round-trip cost/);
  });

  it("passes when the target comfortably covers costs", () => {
    const m = confirmedCandidate();
    m.estSlippagePctFor1Sol = 0.5; // 1.6% cost vs 4% budget
    expect(evaluateBuyRules(m, scoreToken(m), DEFAULT_SETTINGS).buy).toBe(true);
  });
});

describe("breakeven stop", () => {
  const base = {
    entryPriceUsd: 0.001,
    openedAt: new Date("2026-07-04T12:00:00Z"),
    now: new Date("2026-07-04T12:03:00Z"),
    buySellRatio5m: 1.2, // healthy flow: momentum/weak exits stay quiet
  };

  it("exits at entry after the trade proved itself and faded", () => {
    const d = evaluateExit(DEFAULT_SETTINGS, {
      ...base,
      peakPriceUsd: 0.00108, // peaked +8% ≥ proof at +6%
      currentPriceUsd: 0.001, // back to entry
    });
    expect(d.exit).toBe(true);
    expect(d.kind).toBe("breakeven_stop");
  });

  it("catches a gap straight through entry (trailing stop can't)", () => {
    const d = evaluateExit(DEFAULT_SETTINGS, {
      ...base,
      peakPriceUsd: 0.00108,
      currentPriceUsd: 0.00098, // -2%: above the -6% stop loss
    });
    expect(d.exit).toBe(true);
    expect(d.kind).toBe("breakeven_stop");
  });

  it("does not fire before the trade proved itself", () => {
    const d = evaluateExit(DEFAULT_SETTINGS, {
      ...base,
      peakPriceUsd: 0.00104, // peaked only +4% < +6% proof
      currentPriceUsd: 0.001,
    });
    expect(d.kind).not.toBe("breakeven_stop");
  });

  it("respects breakevenAfterPct=null (disabled)", () => {
    const d = evaluateExit(
      { ...DEFAULT_SETTINGS, breakevenAfterPct: null, cutWeakAfterMinutes: null },
      { ...base, peakPriceUsd: 0.00108, currentPriceUsd: 0.001 }
    );
    expect(d.kind).not.toBe("breakeven_stop");
  });
});

describe("pair discipline (cooldown + lock)", () => {
  const now = new Date("2026-07-10T12:00:00Z");
  const minAgo = (min: number) => new Date(now.getTime() - min * 60_000);

  it("allows a mint with no history or a winning last trade", () => {
    expect(checkPairHistory(DEFAULT_SETTINGS, { recentClosed: [], now })).toBeNull();
    expect(
      checkPairHistory(DEFAULT_SETTINGS, {
        recentClosed: [{ pnlSol: 0.02, closedAt: minAgo(2) }],
        now,
      })
    ).toBeNull();
  });

  it("cools down a pair whose last trade was a recent loss", () => {
    const reason = checkPairHistory(DEFAULT_SETTINGS, {
      recentClosed: [{ pnlSol: -0.01, closedAt: minAgo(5) }], // cooldown 15 min
      now,
    });
    expect(reason).toMatch(/cooling down/);
    expect(
      checkPairHistory(DEFAULT_SETTINGS, {
        recentClosed: [{ pnlSol: -0.01, closedAt: minAgo(30) }],
        now,
      })
    ).toBeNull();
  });

  it("locks a pair after 2 consecutive losses for PAIR_LOCK_HOURS", () => {
    const reason = checkPairHistory(DEFAULT_SETTINGS, {
      recentClosed: [
        { pnlSol: -0.01, closedAt: minAgo(60) }, // outside the 15-min cooldown
        { pnlSol: -0.02, closedAt: minAgo(90) },
      ],
      now,
    });
    expect(reason).toMatch(/locked: 2 consecutive losses/);
    // …but not after the lock expires
    expect(
      checkPairHistory(DEFAULT_SETTINGS, {
        recentClosed: [
          { pnlSol: -0.01, closedAt: minAgo((PAIR_LOCK_HOURS + 1) * 60) },
          { pnlSol: -0.02, closedAt: minAgo((PAIR_LOCK_HOURS + 2) * 60) },
        ],
        now,
      })
    ).toBeNull();
    // a win between losses clears the streak
    expect(
      checkPairHistory(DEFAULT_SETTINGS, {
        recentClosed: [
          { pnlSol: 0.02, closedAt: minAgo(60) },
          { pnlSol: -0.02, closedAt: minAgo(90) },
        ],
        now,
      })
    ).toBeNull();
  });
});

describe("condition-aware sizing", () => {
  it("keeps full size in good conditions", () => {
    const d = adjustSizeForConditions(0.1, {
      volatility5m: 5,
      estSlippagePctFor1Sol: 0.8,
      rpcLatencyMs: 60,
    });
    expect(d.sizeSol).toBe(0.1);
    expect(d.notes).toHaveLength(0);
  });

  it("halves per adverse condition with a 25% floor", () => {
    expect(
      adjustSizeForConditions(0.1, { volatility5m: 20, estSlippagePctFor1Sol: 0.8, rpcLatencyMs: 60 }).sizeSol
    ).toBeCloseTo(0.05);
    const worst = adjustSizeForConditions(0.1, {
      volatility5m: 20,
      estSlippagePctFor1Sol: 3,
      rpcLatencyMs: 2_000,
    });
    expect(worst.sizeSol).toBeCloseTo(0.025); // floor: 25% of base, not 12.5%
    expect(worst.notes).toHaveLength(3);
  });

  it("treats missing readings as neutral", () => {
    const d = adjustSizeForConditions(0.1, {
      volatility5m: null,
      estSlippagePctFor1Sol: null,
      rpcLatencyMs: null,
    });
    expect(d.sizeSol).toBe(0.1);
  });
});
