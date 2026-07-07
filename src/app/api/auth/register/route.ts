import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { hashPassword } from "@/lib/auth";
import { registerSchema } from "@/lib/validation";
import { rateLimit, clientIp } from "@/lib/rateLimit";

/**
 * Single-administrator bootstrap. Registration works exactly once — to
 * create the admin account on first run — and is permanently disabled the
 * moment any account exists. There is no public registration.
 * (Locked out? See scripts/reset-admin.ts.)
 */
export async function POST(req: Request) {
  if (!(await rateLimit(`register:${clientIp(req)}`, 5, 3600))) {
    return NextResponse.json({ error: "Too many attempts" }, { status: 429 });
  }

  const body = await req.json().catch(() => null);
  const parsed = registerSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? "Invalid input" },
      { status: 400 }
    );
  }

  try {
    const existingUsers = await prisma.user.count();
    if (existingUsers > 0) {
      return NextResponse.json(
        { error: "Registration is disabled — administrator account already exists" },
        { status: 403 }
      );
    }

    const email = parsed.data.email.toLowerCase().trim();
    const passwordHash = await hashPassword(parsed.data.password);
    // One transaction: the admin account is never created without its
    // default settings row (paper trading ON, bot OFF).
    await prisma.$transaction(async (tx) => {
      const user = await tx.user.create({ data: { email, passwordHash } });
      await tx.settings.create({ data: { userId: user.id } });
      await tx.logEntry.create({
        data: { level: "info", source: "api", message: `administrator account created: ${email}` },
      });
    });
    return NextResponse.json({ ok: true });
  } catch (e) {
    // Surface infrastructure problems honestly instead of a generic failure —
    // an unreachable or uninitialized database is a deployment issue, not a
    // bad password. Details go to the server log only.
    console.error("[register] failed:", (e as Error).message);
    return NextResponse.json(
      {
        error:
          "The server cannot reach its database. Check DATABASE_URL and the deployment logs (schema is applied automatically at boot).",
      },
      { status: 503 }
    );
  }
}
