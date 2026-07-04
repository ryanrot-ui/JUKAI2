import { NextResponse } from "next/server";
import { Connection, VersionedTransaction } from "@solana/web3.js";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { requireUser, unauthorized } from "@/lib/session";
import { rateLimit } from "@/lib/rateLimit";

/**
 * Manual Mode, step 2: submit the Phantom-signed transaction. The server
 * only relays already-signed bytes — it cannot alter or re-sign them —
 * then confirms and records the trade for the history views.
 */

const conn = new Connection(
  process.env.SOLANA_RPC_URL ?? "https://api.mainnet-beta.solana.com",
  "confirmed"
);

const submitSchema = z.object({
  signedTransaction: z.string().min(100).max(20_000), // base64
  mint: z.string().min(32).max(44),
  side: z.enum(["buy", "sell"]),
  amountSol: z.number().min(0),
});

export async function POST(req: Request) {
  const user = await requireUser();
  if (!user) return unauthorized();
  if (!(await rateLimit(`manual-submit:${user.id}`, 20, 60))) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const parsed = submitSchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: "Invalid input" }, { status: 400 });

  let tx: VersionedTransaction;
  try {
    tx = VersionedTransaction.deserialize(Buffer.from(parsed.data.signedTransaction, "base64"));
  } catch {
    return NextResponse.json({ error: "Malformed transaction" }, { status: 400 });
  }

  try {
    const latest = await conn.getLatestBlockhash("confirmed");
    const signature = await conn.sendRawTransaction(tx.serialize(), {
      skipPreflight: false,
      maxRetries: 3,
    });
    const conf = await conn.confirmTransaction(
      { signature, blockhash: latest.blockhash, lastValidBlockHeight: latest.lastValidBlockHeight },
      "confirmed"
    );
    if (conf.value.err) {
      return NextResponse.json(
        { error: `Transaction failed on-chain: ${JSON.stringify(conf.value.err)}` },
        { status: 400 }
      );
    }

    await prisma.trade.create({
      data: {
        side: parsed.data.side.toUpperCase(),
        paper: false,
        mint: parsed.data.mint,
        amountSol: parsed.data.amountSol,
        tokenQty: 0, // exact fill amount visible on-chain via the signature
        signature,
        reason: `manual trade via Phantom (approved by ${user.email})`,
      },
    });
    await prisma.logEntry
      .create({
        data: {
          level: "info",
          source: "executor",
          message: `manual ${parsed.data.side} executed via Phantom: ${parsed.data.mint} (${signature})`,
        },
      })
      .catch(() => {});

    return NextResponse.json({ ok: true, signature });
  } catch (e) {
    // Secure error handling: log the full detail server-side, return a
    // clean message with no stack trace.
    await prisma.logEntry
      .create({
        data: {
          level: "error",
          source: "executor",
          message: `manual trade submit failed: ${(e as Error).message}`,
        },
      })
      .catch(() => {});
    return NextResponse.json({ error: "Transaction submission failed" }, { status: 502 });
  }
}
