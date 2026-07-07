# Deploy to Railway (web dashboard + trading engine)

This app is **two long-running programs** that share one Postgres and one Redis:

- **web** — the Next.js dashboard (build: `Dockerfile`, config: `railway.json`)
- **engine** — the always-on trading worker (build: `Dockerfile.engine`,
  config: `railway.engine.json`)

You create both as separate services **in the same Railway project**, pointing
at **the same GitHub repo** (`main` branch).

---

## 1. Add the databases

In your Railway project: **+ New → Database → PostgreSQL**, then again for
**Redis**. Leave them as-is; Railway exposes their connection strings as
variable references you'll use below.

## 2. Web service

You already have this service (the one that was failing). Configure it:

**Settings → Config-as-code path:** `railway.json` (usually auto-detected).

**Variables:**

```
DATABASE_URL          = ${{Postgres.DATABASE_URL}}
REDIS_URL             = ${{Redis.REDIS_URL}}
NEXTAUTH_URL          = https://<your-web-service>.up.railway.app
NEXTAUTH_SECRET       = <openssl rand -base64 32>
WALLET_ENCRYPTION_KEY = <openssl rand -hex 32>
SOLANA_RPC_URL        = https://mainnet.helius-rpc.com/?api-key=<your-key>
```

Generate `NEXTAUTH_URL` last: Railway assigns the domain after the first deploy
(**Settings → Networking → Generate Domain**), then paste it back here and
redeploy. `NEXTAUTH_URL` starting with `https://` is what switches on Secure
cookies.

## 3. Engine service

**+ New → GitHub Repo →** pick the **same repo**. Then in that service:

**Settings → Config-as-code path:** `railway.engine.json`
(this is what makes it build `Dockerfile.engine` instead of the web image).

**Variables** — the engine needs the same secrets so it can decrypt the bot
wallet and reach the databases. The simplest path is a **shared variable
group**, or just set the same values:

```
DATABASE_URL          = ${{Postgres.DATABASE_URL}}
REDIS_URL             = ${{Redis.REDIS_URL}}
WALLET_ENCRYPTION_KEY = <same value as the web service>
SOLANA_RPC_URL        = https://mainnet.helius-rpc.com/?api-key=<your-key>
# optional but strongly recommended:
SOLANA_RPC_URLS       = <comma-separated fallback RPC endpoints>
HELIUS_API_KEY        = <your-helius-key>   # enables holder metrics
```

`WALLET_ENCRYPTION_KEY` **must be identical** on both services — the web app
encrypts the imported bot-wallet key, the engine decrypts it.

The engine has no public port; it just runs. It reads its live settings from
Postgres/Redis, so it starts idle (bot disabled, paper mode) until you turn it
on from the dashboard.

## 4. First run

1. Open the web URL → `/register` → create your **administrator account**
   (works once). Enable 2FA under Settings.
2. Settings → **Wallets**: connect Phantom (watch-only) and/or import a
   dedicated bot wallet.
3. Keep **paper trading ON**. Press **Start auto** in the sidebar.
4. Watch the dashboard health strip — once the engine service is up you'll see
   RPC latency, scans/min, and the live feed populate.

## Notes

- **Trial limits:** two services + two databases will use more of the trial
  than a single service. If you hit limits, deploy the **web** service first,
  confirm it works, then add the engine.
- **A dedicated RPC is required.** Railway's outbound IP hitting the public
  Solana RPC will be rate-limited immediately; the scanner needs Helius/Triton/
  QuickNode. Helius has a free tier.
- **Schema:** both services run `prisma db push` on boot, so the tables are
  created automatically the first time either one starts. It's idempotent.
- **Backups:** Railway's Postgres has its own backup tooling; the compose
  `backup` service is only for self-hosted `docker compose` deploys.
