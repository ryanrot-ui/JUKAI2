"use client";

import { useMemo } from "react";
import { ConnectionProvider, WalletProvider } from "@solana/wallet-adapter-react";
import { PhantomWalletAdapter } from "@solana/wallet-adapter-phantom";

/**
 * Official Solana Wallet Adapter context (Phantom, mainnet).
 *
 * The browser never talks to an RPC endpoint directly — balances and
 * transaction history are fetched by the server — so the endpoint below only
 * satisfies the provider contract and stays within the strict same-origin
 * Content Security Policy. autoConnect restores the session's wallet on
 * reload. Phantom's own security model is never bypassed: the extension
 * prompts for every signature and no key material ever reaches this app.
 */
export function WalletProviders({ children }: { children: React.ReactNode }) {
  const wallets = useMemo(() => [new PhantomWalletAdapter()], []);
  const endpoint =
    process.env.NEXT_PUBLIC_SOLANA_RPC_URL ?? "https://api.mainnet-beta.solana.com";
  return (
    <ConnectionProvider endpoint={endpoint}>
      <WalletProvider wallets={wallets} autoConnect>
        {children}
      </WalletProvider>
    </ConnectionProvider>
  );
}
