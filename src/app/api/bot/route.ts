import { NextResponse } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { redis, KEYS } from "@/lib/redis";
import { requireUser, unauthorized } from "@/lib/session";
import { rateLimit } from "@/lib/rateLimit";

export async function GET() {
  const user = await requireUser();
  if (!user) return unauthorized();

  const [status, heartbeat, readOnly, settings] = await Promise.all([
    redis.get(KEYS.botStatus).catch(() => null),
    redis.get(KEYS.botHeartbeat).catch(() => null),
    redis.get("bot:readOnly").catch(() => null),
    prisma.settings.findUnique({ where: { userId: user.id } }),
  ]);
  const beatAge = heartbeat ? Date.now() - parseInt(heartbeat, 10) : null;
  return NextResponse.json({
    status: status ?? "stopped",
    engineAlive: beatAge !== null && beatAge < 20_000,
    lastHeartbeatMsAgo: beatAge,
    readOnly: readOnly === "1",
    // Trading mode indicator: AUTO = the engine trades with the imported bot
    // wallet; MANUAL = bot disabled, trades only via Phantom approval.
    mode: settings?.botEnabled ? "auto" : "manual",
    paperTrading: settings?.paperTrading ?? true,
  });
}

const actionSchema = z.object({
  action: z.enum(["start", "stop", "emergency_stop", "resume", "read_only_on", "read_only_off"]),
});

export async function POST(req: Request) {
  const user = await requireUser();
  if (!user) return unauthorized();
  if (!(await rateLimit(`bot:${user.id}`, 30, 60))) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const parsed = actionSchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: "Invalid action" }, { status: 400 });
  const { action } = parsed.data;

  if (action === "start" || action === "stop") {
    await prisma.settings.upsert({
      where: { userId: user.id },
      update: { botEnabled: action === "start" },
      create: { userId: user.id, botEnabled: action === "start" },
    });
    await redis.publish(KEYS.settingsChannel, "updated").catch(() => {});
  } else if (action === "read_only_on" || action === "read_only_off") {
    // Read-only mode: engine observes and scores but executes nothing.
    await redis.set("bot:readOnly", action === "read_only_on" ? "1" : "0").catch(() => {});
  } else {
    // emergency_stop / resume go straight to the engine control channel
    await redis.publish(KEYS.controlChannel, action).catch(() => {});
  }

  await prisma.logEntry
    .create({
      data: {
        level: action === "emergency_stop" ? "warn" : "info",
        source: "api",
        message: `bot control: ${action} (by ${user.email})`,
      },
    })
    .catch(() => {});
  return NextResponse.json({ ok: true });
}
