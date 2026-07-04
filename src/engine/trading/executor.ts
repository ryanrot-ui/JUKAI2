import {
  Connection,
  Keypair,
  LAMPORTS_PER_SOL,
  PublicKey,
  VersionedTransaction,
} from "@solana/web3.js";

/**
 * Swap execution.
 *
 * Live mode routes through the Jupiter aggregator API, which includes every
 * Raydium pool (newly migrated Pump.fun pools are indexed within seconds).
 * Jupiter handles route construction and slippage protection and returns a
 * ready-to-sign versioned transaction — the private key never leaves this
 * process and is only held in memory while signing.
 *
 * Confirmation is blockhash-aware: the transaction is confirmed against its
 * own lastValidBlockHeight, and if confirmation times out we check whether
 * the signature actually landed before deciding success or failure — so a
 * confirmed-but-slow swap is never double-executed and a dropped swap is
 * reported as a clean, retryable failure.
 *
 * Paper mode fills at the current observed price with a simulated slippage
 * haircut so paper results stay conservative.
 */

const JUPITER = "https://quote-api.jup.ag/v6";
const WSOL = "So11111111111111111111111111111111111111112";

export interface SwapOptions {
  maxSlippageBps: number;
  /** exact micro-lamport priority fee; undefined/null = Jupiter "auto" */
  priorityFeeLamports?: number | null;
}

export interface SwapResult {
  signature: string | null; // null for paper fills
  inAmount: number; // lamports or token base units spent
  outAmount: number; // received, base units
  priceImpactPct: number | null;
  paper: boolean;
}

/** Thrown when a swap failed cleanly (definitely NOT on-chain) → retryable. */
export class SwapDroppedError extends Error {
  readonly retryable = true;
}

/** Thrown when we cannot prove whether the swap landed → NOT retryable. */
export class SwapUncertainError extends Error {
  readonly retryable = false;
  constructor(
    message: string,
    public readonly signature: string
  ) {
    super(message);
  }
}

export interface Executor {
  buy(mint: string, amountSol: number, opts: SwapOptions): Promise<SwapResult>;
  sell(mint: string, tokenBaseUnits: number, opts: SwapOptions): Promise<SwapResult>;
}

// ── Balance helpers (pre-trade validation & desync recovery) ────────────────

export async function getWalletSolBalance(conn: Connection, owner: PublicKey): Promise<number> {
  return (await conn.getBalance(owner, "confirmed")) / LAMPORTS_PER_SOL;
}

/** Total base-unit balance of `mint` across the owner's token accounts. */
export async function getWalletTokenBalance(
  conn: Connection,
  owner: PublicKey,
  mint: string
): Promise<number> {
  const res = await conn.getParsedTokenAccountsByOwner(
    owner,
    { mint: new PublicKey(mint) },
    "confirmed"
  );
  return res.value.reduce(
    (sum, acc) => sum + Number(acc.account.data.parsed.info.tokenAmount.amount),
    0
  );
}

// ── Live executor (Jupiter) ─────────────────────────────────────────────────

interface JupiterQuote {
  inAmount: string;
  outAmount: string;
  priceImpactPct: string;
  [k: string]: unknown;
}

export class LiveExecutor implements Executor {
  constructor(
    private conn: Connection,
    private getSigner: () => Keypair // resolved lazily; key stays encrypted at rest
  ) {}

  publicKey(): PublicKey {
    return this.getSigner().publicKey;
  }

  async buy(mint: string, amountSol: number, opts: SwapOptions): Promise<SwapResult> {
    return this.swap(WSOL, mint, Math.round(amountSol * LAMPORTS_PER_SOL), opts);
  }

  async sell(mint: string, tokenBaseUnits: number, opts: SwapOptions): Promise<SwapResult> {
    return this.swap(mint, WSOL, Math.round(tokenBaseUnits), opts);
  }

  private async swap(
    inputMint: string,
    outputMint: string,
    amount: number,
    opts: SwapOptions
  ): Promise<SwapResult> {
    // 1. Quote (Jupiter enforces slippage via slippageBps in the route)
    const quoteRes = await fetch(
      `${JUPITER}/quote?inputMint=${inputMint}&outputMint=${outputMint}` +
        `&amount=${amount}&slippageBps=${opts.maxSlippageBps}&onlyDirectRoutes=false`,
      { signal: AbortSignal.timeout(8000) }
    );
    if (!quoteRes.ok) throw new SwapDroppedError(`jupiter quote HTTP ${quoteRes.status}`);
    const quote = (await quoteRes.json()) as JupiterQuote;

    // 2. Build swap tx (compute budget + priority fee handled by Jupiter:
    //    dynamicComputeUnitLimit right-sizes CU, priority fee is exact or auto)
    const signer = this.getSigner();
    const swapRes = await fetch(`${JUPITER}/swap`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      signal: AbortSignal.timeout(8000),
      body: JSON.stringify({
        quoteResponse: quote,
        userPublicKey: signer.publicKey.toBase58(),
        wrapAndUnwrapSol: true,
        dynamicComputeUnitLimit: true,
        prioritizationFeeLamports:
          opts.priorityFeeLamports != null ? opts.priorityFeeLamports : "auto",
      }),
    });
    if (!swapRes.ok) throw new SwapDroppedError(`jupiter swap HTTP ${swapRes.status}`);
    const { swapTransaction } = (await swapRes.json()) as { swapTransaction: string };

    // 3. Sign & send with a fresh blockhash window for expiry-aware confirm
    const tx = VersionedTransaction.deserialize(Buffer.from(swapTransaction, "base64"));
    tx.sign([signer]);
    const latest = await this.conn.getLatestBlockhash("confirmed");

    let signature: string;
    try {
      signature = await this.conn.sendRawTransaction(tx.serialize(), {
        skipPreflight: false, // preflight simulation catches doomed swaps for free
        maxRetries: 3,
      });
    } catch (e) {
      // send failed before broadcast — definitely not on-chain
      throw new SwapDroppedError(`send failed: ${(e as Error).message}`);
    }

    // 4. Confirm against the blockhash validity window
    try {
      const conf = await this.conn.confirmTransaction(
        {
          signature,
          blockhash: latest.blockhash,
          lastValidBlockHeight: latest.lastValidBlockHeight,
        },
        "confirmed"
      );
      if (conf.value.err) {
        // executed and failed on-chain (e.g. slippage exceeded) — safe to retry
        throw new SwapDroppedError(`swap failed on-chain: ${JSON.stringify(conf.value.err)}`);
      }
    } catch (e) {
      if (e instanceof SwapDroppedError) throw e;
      // Confirmation timed out or blockhash expired: check whether it landed.
      const landed = await this.didLand(signature);
      if (landed === true) {
        /* fall through to success */
      } else if (landed === false) {
        throw new SwapDroppedError(`blockhash expired before inclusion (${signature})`);
      } else {
        throw new SwapUncertainError(
          `cannot verify swap outcome — manual check required: ${signature}`,
          signature
        );
      }
    }

    return {
      signature,
      inAmount: Number(quote.inAmount),
      outAmount: Number(quote.outAmount),
      priceImpactPct: parseFloat(quote.priceImpactPct) || null,
      paper: false,
    };
  }

  /** true = landed OK, false = definitely not on-chain, null = unknown. */
  private async didLand(signature: string): Promise<boolean | null> {
    try {
      const st = await this.conn.getSignatureStatus(signature, {
        searchTransactionHistory: true,
      });
      if (!st.value) return false;
      return st.value.err ? false : true;
    } catch {
      return null; // RPC failed — we genuinely don't know
    }
  }
}

// ── Paper executor ──────────────────────────────────────────────────────────

export class PaperExecutor implements Executor {
  constructor(
    private getPriceUsd: (mint: string) => Promise<number | null>,
    private getSolPriceUsd: () => Promise<number>,
    /** simulated slippage haircut applied to every paper fill */
    private simulatedSlippagePct = 1.5
  ) {}

  async buy(mint: string, amountSol: number, _opts: SwapOptions): Promise<SwapResult> {
    const price = await this.getPriceUsd(mint);
    const sol = await this.getSolPriceUsd();
    if (!price || price <= 0) throw new SwapDroppedError("paper buy: no price available");
    const usd = amountSol * sol;
    const tokens = (usd / price) * (1 - this.simulatedSlippagePct / 100);
    return {
      signature: null,
      inAmount: Math.round(amountSol * LAMPORTS_PER_SOL),
      outAmount: tokens,
      priceImpactPct: this.simulatedSlippagePct,
      paper: true,
    };
  }

  async sell(mint: string, tokenQty: number, _opts: SwapOptions): Promise<SwapResult> {
    const price = await this.getPriceUsd(mint);
    const sol = await this.getSolPriceUsd();
    if (!price || price <= 0) throw new SwapDroppedError("paper sell: no price available");
    const usd = tokenQty * price * (1 - this.simulatedSlippagePct / 100);
    return {
      signature: null,
      inAmount: tokenQty,
      outAmount: Math.round((usd / sol) * LAMPORTS_PER_SOL),
      priceImpactPct: this.simulatedSlippagePct,
      paper: true,
    };
  }
}
