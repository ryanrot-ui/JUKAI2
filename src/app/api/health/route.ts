import { NextResponse } from "next/server";
import { redis, KEYS } from "@/lib/redis";
import { requireUser, unauthorized } from "@/lib/session";

/** Engine health & telemetry for the dashboard health strip. */
export async function GET() {
  const user = await requireUser();
  if (!user) return unauthorized();

  const [health, heartbeat, status, readOnly, lastError] = await Promise.all([
    redis.hgetall("bot:health").catch(() => ({}) as Record<string, string>),
    redis.get(KEYS.botHeartbeat).catch(() => null),
    redis.get(KEYS.botStatus).catch(() => null),
    redis.get("bot:readOnly").catch(() => null),
    redis.get("bot:lastError").catch(() => null),
  ]);

  const beatAge = heartbeat ? Date.now() - parseInt(heartbeat, 10) : null;
  const num = (v: string | undefined) => (v ? parseInt(v, 10) : null);

  return NextResponse.json({
    engineAlive: beatAge !== null && beatAge < 20_000,
    status: status ?? "stopped",
    readOnly: readOnly === "1",
    rpcUrl: health.rpcUrl ?? null,
    rpcLatencyMs: num(health.rpcLatencyMs),
    rpcFailures: num(health.rpcFailures),
    scannerLastEventAt: num(health.scannerLastEventAt),
    scansPerMin: num(health.scansPerMin),
    watchlistSize: num(health.watchlistSize),
    lastTradeAt: num(health.lastTradeAt),
    memoryRssMb: num(health.rssMb),
    memoryHeapMb: num(health.heapMb),
    lastError: lastError ? JSON.parse(lastError) : null,
  });
}
