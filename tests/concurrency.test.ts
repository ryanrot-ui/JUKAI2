import { describe, expect, it } from "vitest";
import { AsyncLock, withRetries } from "@/engine/utils/concurrency";

describe("AsyncLock", () => {
  it("serializes concurrent critical sections in FIFO order", async () => {
    const lock = new AsyncLock();
    const order: number[] = [];
    let inside = 0;
    let maxInside = 0;

    await Promise.all(
      [1, 2, 3, 4, 5].map((n) =>
        lock.run(async () => {
          inside++;
          maxInside = Math.max(maxInside, inside);
          await new Promise((r) => setTimeout(r, 5));
          order.push(n);
          inside--;
        })
      )
    );

    expect(maxInside).toBe(1); // never two holders at once
    expect(order).toEqual([1, 2, 3, 4, 5]);
  });

  it("releases the lock after an exception", async () => {
    const lock = new AsyncLock();
    await expect(lock.run(async () => Promise.reject(new Error("boom")))).rejects.toThrow("boom");
    const result = await lock.run(async () => "still works");
    expect(result).toBe("still works");
  });
});

describe("withRetries", () => {
  it("returns first-try success with attempts=1", async () => {
    const { result, attempts } = await withRetries(async () => 42, { retries: 3, baseDelayMs: 1 });
    expect(result).toBe(42);
    expect(attempts).toBe(1);
  });

  it("retries transient failures and reports the attempt count", async () => {
    let calls = 0;
    const { result, attempts } = await withRetries(
      async () => {
        calls++;
        if (calls < 3) throw new Error("transient");
        return "ok";
      },
      { retries: 3, baseDelayMs: 1 }
    );
    expect(result).toBe("ok");
    expect(attempts).toBe(3);
  });

  it("gives up after the retry budget", async () => {
    let calls = 0;
    await expect(
      withRetries(
        async () => {
          calls++;
          throw new Error("always fails");
        },
        { retries: 2, baseDelayMs: 1 }
      )
    ).rejects.toThrow("always fails");
    expect(calls).toBe(3); // initial + 2 retries
  });

  it("never retries when isRetryable says no (uncertain swap outcomes)", async () => {
    let calls = 0;
    await expect(
      withRetries(
        async () => {
          calls++;
          throw new Error("may have landed on-chain");
        },
        { retries: 5, baseDelayMs: 1, isRetryable: () => false }
      )
    ).rejects.toThrow("may have landed");
    expect(calls).toBe(1); // duplicate-execution guard
  });
});
