#!/usr/bin/env node
/**
 * Netlify build for the PumpTrader web app (dashboard + API + auth).
 *
 * What it does, in order:
 *   1. Validate ONLY the environment variables that are truly required, with
 *      clear, actionable messages. Optional variables are never required; if
 *      an optional secret is present but malformed, that IS flagged.
 *   2. Derive sensible defaults so fewer variables must be set by hand:
 *        - NEXTAUTH_URL   ← Netlify's $URL / $DEPLOY_PRIME_URL
 *        - DIRECT_URL     ← DATABASE_URL with any Neon "-pooler" removed
 *        - SOLANA_RPC_URL ← public mainnet endpoint
 *   3. Generate the Prisma client, apply the schema to the database
 *      (idempotent, non-destructive — creates tables on first deploy), and
 *      run `next build`.
 *
 * Truly required (set these in Netlify → Site settings → Environment):
 *   - DATABASE_URL      PostgreSQL connection string (Neon recommended)
 *   - NEXTAUTH_SECRET   session-signing secret (openssl rand -base64 32)
 *
 * Everything else is optional. WALLET_ENCRYPTION_KEY is only needed for LIVE
 * trading / importing a bot wallet; if you set it, it must be 64 hex chars.
 *
 * NOTE: Netlify hosts the web app only. The trading ENGINE is a long-running
 * worker and must run on an always-on host (Render worker, Railway, Fly.io,
 * a VPS). See docs/DEPLOY-NETLIFY.md.
 */
import { execSync } from "node:child_process";
import { join } from "node:path";
import { delimiter } from "node:path";

// Ensure locally-installed CLIs (prisma, next) resolve whether we're invoked
// via `npm run` or a bare `node scripts/netlify-build.mjs` build command.
const localBin = join(process.cwd(), "node_modules", ".bin");
process.env.PATH = `${localBin}${delimiter}${process.env.PATH ?? ""}`;

const RESET = "\x1b[0m";
const RED = "\x1b[31m";
const YELLOW = "\x1b[33m";
const GREEN = "\x1b[32m";
const BOLD = "\x1b[1m";

const errors = [];
const warnings = [];

// ── 1. Required variables ──────────────────────────────────────────────────

const DATABASE_URL = process.env.DATABASE_URL?.trim();
if (!DATABASE_URL) {
  errors.push(
    "DATABASE_URL is required but not set.\n" +
      "    → Set it in Netlify: Site settings → Environment variables → Add a variable.\n" +
      "    → Value: your PostgreSQL connection string, e.g. from Neon:\n" +
      "        postgresql://USER:PASSWORD@HOST/DB?sslmode=require"
  );
} else if (!/^postgres(ql)?:\/\//.test(DATABASE_URL)) {
  errors.push(
    `DATABASE_URL is set but does not look like a PostgreSQL URL (got "${DATABASE_URL.slice(0, 12)}…").\n` +
      "    → It must start with postg:// or postgresql://"
  );
}

const NEXTAUTH_SECRET = process.env.NEXTAUTH_SECRET?.trim();
if (!NEXTAUTH_SECRET) {
  errors.push(
    "NEXTAUTH_SECRET is required but not set.\n" +
      "    → Generate one:  openssl rand -base64 32\n" +
      "    → Set it in Netlify: Site settings → Environment variables → Add a variable."
  );
} else if (NEXTAUTH_SECRET.length < 16) {
  errors.push(
    `NEXTAUTH_SECRET is too short (${NEXTAUTH_SECRET.length} chars).\n` +
      "    → Use a strong random value (≥ 16 chars; 32 bytes recommended): openssl rand -base64 32"
  );
}

// ── 2. Optional variables — validate format only if present ────────────────

const WALLET_ENCRYPTION_KEY = process.env.WALLET_ENCRYPTION_KEY?.trim();
if (WALLET_ENCRYPTION_KEY && !/^[0-9a-fA-F]{64}$/.test(WALLET_ENCRYPTION_KEY)) {
  errors.push(
    `WALLET_ENCRYPTION_KEY is set but is not exactly 64 hexadecimal characters ` +
      `(got ${WALLET_ENCRYPTION_KEY.length} chars).\n` +
      "    → Generate a valid key:  openssl rand -hex 32\n" +
      "    → Leave it unset if you only use paper trading (it is required only for live trading)."
  );
}

if (process.env.REDIS_URL && !/^rediss?:\/\//.test(process.env.REDIS_URL.trim())) {
  warnings.push("REDIS_URL is set but does not start with redis:// — it will be ignored if unreachable (Redis is optional).");
}

// ── 3. Derived defaults (reduce the variables you must set) ────────────────

if (!process.env.NEXTAUTH_URL) {
  const derived = process.env.URL || process.env.DEPLOY_PRIME_URL || process.env.DEPLOY_URL;
  if (derived) {
    process.env.NEXTAUTH_URL = derived;
    console.log(`${GREEN}✓${RESET} NEXTAUTH_URL derived from Netlify's site URL: ${derived}`);
  } else {
    warnings.push(
      "NEXTAUTH_URL is not set and Netlify's $URL is unavailable. Logins need the public https origin.\n" +
        "    → Usually auto-detected on Netlify. If login fails after deploy, set NEXTAUTH_URL to your site URL."
    );
  }
}

if (DATABASE_URL && !process.env.DIRECT_URL) {
  // Neon's pooled endpoint (…-pooler…) cannot run the DDL that `prisma db push`
  // needs. Derive the direct endpoint automatically so the schema applies.
  process.env.DIRECT_URL = DATABASE_URL.includes("-pooler.")
    ? DATABASE_URL.replace("-pooler.", ".")
    : DATABASE_URL;
  if (DATABASE_URL.includes("-pooler."))
    console.log(`${GREEN}✓${RESET} DIRECT_URL derived from DATABASE_URL (removed -pooler) for schema apply`);
}

if (!process.env.SOLANA_RPC_URL) {
  process.env.SOLANA_RPC_URL = "https://api.mainnet-beta.solana.com";
  warnings.push("SOLANA_RPC_URL not set — defaulting to the public mainnet endpoint (rate-limited; set a dedicated RPC for real use).");
}

// ── Report validation results ──────────────────────────────────────────────

if (warnings.length) {
  console.log(`\n${YELLOW}${BOLD}Warnings (build continues):${RESET}`);
  for (const w of warnings) console.log(`${YELLOW}  •${RESET} ${w}`);
}

if (errors.length) {
  console.error(`\n${RED}${BOLD}✗ Build blocked — fix these environment variables in Netlify:${RESET}\n`);
  for (const e of errors) console.error(`${RED}  ✗${RESET} ${e}\n`);
  console.error(
    `${BOLD}Where:${RESET} Netlify dashboard → your site → Site configuration → ` +
      `Environment variables → Add / edit, then redeploy.\n`
  );
  process.exit(1);
}
console.log(`${GREEN}${BOLD}✓ Environment looks good.${RESET}\n`);

// ── Build steps ──────────────────────────────────────────────────────────

function run(cmd, label) {
  console.log(`${BOLD}▸ ${label}${RESET}  (${cmd})`);
  execSync(cmd, { stdio: "inherit", env: process.env });
}

run("prisma generate", "Generate Prisma client");

// Apply the schema (idempotent). Skippable via SKIP_DB_PUSH=1 for environments
// where the schema is managed separately.
if (process.env.SKIP_DB_PUSH === "1") {
  console.log(`${YELLOW}▸ Skipping schema apply (SKIP_DB_PUSH=1)${RESET}`);
} else {
  try {
    run("prisma db push --skip-generate", "Apply database schema (idempotent)");
  } catch {
    console.error(
      `\n${RED}${BOLD}✗ Could not apply the database schema.${RESET}\n` +
        `  • Check DATABASE_URL is reachable from Netlify's build.\n` +
        `  • On Neon, the schema apply uses the NON-pooled endpoint (auto-derived from\n` +
        `    DATABASE_URL by stripping "-pooler"). If your pooled/non-pooled hosts differ\n` +
        `    in more than "-pooler", set DIRECT_URL explicitly to the non-pooled URL.\n`
    );
    process.exit(1);
  }
}

run("next build", "Build the Next.js app");

console.log(`\n${GREEN}${BOLD}✓ Netlify build complete.${RESET}`);
