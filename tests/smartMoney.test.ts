import { describe, expect, it } from "vitest";
import {
  classifyTokenOutcome,
  smartMoneyDelta,
  walletScore,
  PROVEN_SCORE,
} from "@/engine/learning/smartMoney";

describe("smart money — token outcome grading", () => {
  it("classifies winners, rugs, and flats; a rugged pump is a rug", () => {
    expect(classifyTokenOutcome(120, false)).toBe("winner");
    expect(classifyTokenOutcome(120, true)).toBe("rug"); // pumped then rugged
    expect(classifyTokenOutcome(10, false)).toBe("flat");
    expect(classifyTokenOutcome(null, null)).toBe("flat");
  });
});

describe("smart money — wallet scoring (smoothed, rug-penalized)", () => {
  it("smooths small samples toward 50 so lucky wallets can't outrank proven ones", () => {
    expect(walletScore(2, 0, 2)).toBe(75); // 2/2 lucky → 75, not 100
    expect(walletScore(18, 0, 20)).toBe(86); // proven record scores higher
    expect(walletScore(0, 0, 0)).toBe(50); // no history = neutral
  });

  it("penalizes habitual rug-buyers", () => {
    const clean = walletScore(10, 0, 20);
    const ruggy = walletScore(10, 10, 20);
    expect(ruggy).toBeLessThan(clean);
    expect(walletScore(0, 20, 20)).toBeLessThanOrEqual(5);
  });

  it("stays within 0–100", () => {
    expect(walletScore(100, 0, 100)).toBeLessThanOrEqual(100);
    expect(walletScore(0, 100, 100)).toBeGreaterThanOrEqual(0);
  });
});

describe("smart money — bounded confidence component", () => {
  const reading = (provenBuyers: number, buyersSampled = 20) => ({
    buyersSampled,
    knownWallets: provenBuyers,
    provenBuyers,
    avgProvenScore: provenBuyers ? 72 : null,
  });

  it("is neutral without data and never negative", () => {
    expect(smartMoneyDelta(null).delta).toBe(0);
    expect(smartMoneyDelta(reading(0)).delta).toBe(0);
    expect(smartMoneyDelta(reading(0, 0)).delta).toBe(0);
  });

  it("one wallet is never decisive; broad proven interest caps at +8", () => {
    expect(smartMoneyDelta(reading(1)).delta).toBe(2);
    expect(smartMoneyDelta(reading(1)).detail).toMatch(/never decisive/);
    expect(smartMoneyDelta(reading(2)).delta).toBe(5);
    expect(smartMoneyDelta(reading(6)).delta).toBe(8); // hard cap
  });

  it("proven threshold is meaningfully above neutral", () => {
    expect(PROVEN_SCORE).toBeGreaterThanOrEqual(60);
  });
});
