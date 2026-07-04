/**
 * Concurrency primitives for the trading engine. Deliberately tiny and
 * dependency-free so they are trivial to audit.
 */

/**
 * FIFO async mutex. Used to serialize the buy critical section
 * (risk check → position reservation) so concurrent token evaluations can
 * never over-commit exposure or exceed the max-open-positions cap.
 */
export class AsyncLock {
  private tail: Promise<void> = Promise.resolve();

  async run<T>(fn: () => Promise<T>): Promise<T> {
    const prev = this.tail;
    let release!: () => void;
    this.tail = new Promise<void>((r) => (release = r));
    await prev;
    try {
      return await fn();
    } finally {
      release();
    }
  }
}

export interface RetryOutcome<T> {
  result: T;
  attempts: number; // 1 = succeeded first try
}

/**
 * Retry with exponential backoff. `isRetryable` lets callers refuse to retry
 * anything ambiguous (e.g. a swap that may have landed on-chain).
 */
export async function withRetries<T>(
  fn: (attempt: number) => Promise<T>,
  opts: {
    retries: number;
    baseDelayMs?: number;
    isRetryable?: (err: unknown) => boolean;
    onRetry?: (err: unknown, attempt: number) => void;
  }
): Promise<RetryOutcome<T>> {
  const base = opts.baseDelayMs ?? 500;
  let lastErr: unknown;
  for (let attempt = 1; attempt <= opts.retries + 1; attempt++) {
    try {
      return { result: await fn(attempt), attempts: attempt };
    } catch (err) {
      lastErr = err;
      const retryable = opts.isRetryable ? opts.isRetryable(err) : true;
      if (!retryable || attempt > opts.retries) throw err;
      opts.onRetry?.(err, attempt);
      await new Promise((r) => setTimeout(r, base * 2 ** (attempt - 1)));
    }
  }
  throw lastErr;
}
