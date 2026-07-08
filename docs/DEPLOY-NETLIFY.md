# Deploy the PumpTrader web app to Netlify

This guide gets a **fresh GitHub → Netlify deployment** working. The only manual
step is pasting two secrets into Netlify; everything else is automated by
[`netlify.toml`](../netlify.toml) and [`scripts/netlify-build.mjs`](../scripts/netlify-build.mjs).

> **What Netlify runs, and what it does NOT.**
> Netlify hosts the **web app** — the dashboard, the API routes, and login/registration.
> Netlify **cannot** run the trading **engine**. The engine is a long-running
> worker (persistent process, websockets, background scanning) and Netlify's
> serverless platform kills anything that isn't a short request. Run the engine
> on an always-on host (Render worker, Railway, Fly.io, or a VPS) pointed at the
> **same** database. See [DEPLOY-RENDER.md](./DEPLOY-RENDER.md) for a one-click
> Render setup that runs both the web app and the engine.

---

## 1. Create a database (once)

Use any PostgreSQL provider. [Neon](https://neon.tech) has a free tier and works
well. Create a project and copy its connection string. It looks like:

```
postgresql://USER:PASSWORD@ep-xxxx-pooler.REGION.aws.neon.tech/DB?sslmode=require
```

You do **not** need to run any migrations by hand. The build applies the schema
automatically on the first deploy (and it's idempotent on every deploy after).

> **Neon note:** the default string Neon gives you is the **pooled** endpoint
> (the host contains `-pooler`). The build automatically derives the direct
> endpoint (by removing `-pooler`) to apply the schema, because Neon's pooler
> can't run the `CREATE TABLE` statements. You only need to set `DATABASE_URL`.

---

## 2. Connect the repo to Netlify

1. Netlify dashboard → **Add new site** → **Import an existing project**.
2. Choose **GitHub** and pick this repository.
3. **Branch to deploy:** select the branch that contains this code.
   - If you have merged everything into `main`, choose `main`.
   - If the fixes live on `claude/trade-bot-audit-hardening-yga8ha` (or any other
     branch) and are **not yet on `main`**, select **that branch** here —
     otherwise Netlify will build the old `main` and the deploy will fail.
4. **Build command** and **publish directory**: leave them blank. `netlify.toml`
   sets the build command (`node scripts/netlify-build.mjs`) and the Next.js
   plugin manages the publish directory. Do not override them.
5. Do **not** click "Deploy" yet — add the environment variables first (next step),
   or the first build will stop with a clear "variable is required" message.

---

## 3. Paste the two required secrets

Netlify → **Site configuration** → **Environment variables** → **Add a variable**.
Add these two. **These are the only variables you must set.**

| Key | Value to paste | How to get it |
|-----|----------------|---------------|
| `DATABASE_URL` | your full PostgreSQL connection string from step 1 | Neon dashboard → Connection string |
| `NEXTAUTH_SECRET` | a fresh random secret | run `openssl rand -base64 32` in a terminal and paste the output |

That's it. Trigger a deploy (**Deploys** → **Trigger deploy** → **Deploy site**).

---

## 4. Optional variables (set only if you need the feature)

Everything below is **optional**. The build never fails because one is missing;
it only fails if you set one to an invalid value.

| Key | When you need it | Value |
|-----|------------------|-------|
| `NEXTAUTH_URL` | Only if login redirects break. Netlify's `$URL` is auto-detected, so you normally leave this unset. | your public site URL, e.g. `https://your-site.netlify.app` |
| `SOLANA_RPC_URL` | Recommended for real use. Defaults to the public mainnet endpoint, which is rate-limited. | a dedicated RPC URL (Helius, QuickNode, Triton, …) |
| `WALLET_ENCRYPTION_KEY` | **Only for live trading / importing a bot wallet.** Not needed for paper trading. | **exactly 64 hexadecimal characters** — generate with `openssl rand -hex 32` |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Only to enable "Sign in with Google". | from Google Cloud Console → OAuth credentials |
| `REDIS_URL` | Optional. The engine coordinates via the database if this is absent. | `redis://…` or `rediss://…` |
| `DIRECT_URL` | Only if your DB's pooled and direct hosts differ by more than `-pooler`. Auto-derived otherwise. | the non-pooled PostgreSQL URL |

### `WALLET_ENCRYPTION_KEY` must be exactly 64 hex characters

If you set it, it must match `^[0-9a-fA-F]{64}$` — 64 characters, each `0-9`/`a-f`.
`openssl rand -hex 32` produces exactly this. If it's the wrong length or contains
non-hex characters the build stops with:

```
✗ WALLET_ENCRYPTION_KEY is set but is not exactly 64 hexadecimal characters (got N chars).
```

Leave it unset entirely if you only use paper trading.

---

## 5. What the build does (so you can read the log)

`scripts/netlify-build.mjs` runs, in order:

1. **Validate** the required variables (`DATABASE_URL`, `NEXTAUTH_SECRET`) and the
   format of any optional secret you set. On failure it prints exactly which
   variable is wrong and where to fix it, then exits non-zero.
2. **Derive** `NEXTAUTH_URL` (from Netlify's `$URL`), `DIRECT_URL` (from
   `DATABASE_URL`), and a default `SOLANA_RPC_URL` — so you don't have to set them.
3. `prisma generate` — build the database client.
4. `prisma db push` — apply the schema (creates all tables on first deploy;
   idempotent afterward). Skippable with `SKIP_DB_PUSH=1` if you manage the
   schema elsewhere.
5. `next build` — build the app.

A successful log ends with `✓ Netlify build complete.`

---

## 6. First run

Open the deployed URL and go to **/register** to create the first account, then
log in. If registration ever reports that the schema isn't initialized, it means
step 4 above didn't run against your database — check the build log and confirm
`DATABASE_URL` is reachable from Netlify.

---

## 7. Run the engine (separately)

The dashboard shows data and lets you place manual trades, but automated trading
only happens while the **engine** runs. Deploy the engine on an always-on host
pointed at the **same** `DATABASE_URL`:

- **Easiest:** use [DEPLOY-RENDER.md](./DEPLOY-RENDER.md) — the Render Blueprint
  runs both the web service and the engine worker.
- **Manual:** on any always-on host, set the same env vars and run
  `npm run engine` (it self-applies the schema and starts the worker).

The engine needs `WALLET_ENCRYPTION_KEY` (64 hex) **only** when live trading is
enabled; paper trading needs none.
