import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { hashPassword } from "@/lib/auth";
import { registerSchema } from "@/lib/validation";
import { rateLimit, clientIp } from "@/lib/rateLimit";

/**
 * Single-administrator bootstrap. Registration works exactly once — to
 * create the admin account on first run — and is permanently disabled the
 * moment any account exists. There is no public registration.
 */
export async function POST(req: Request) {
  if (!(await rateLimit(`register:${clientIp(req)}`, 5, 3600))) {
    return NextResponse.json({ error: "Too many attempts" }, { status: 429 });
  }

  const existingUsers = await prisma.user.count();
  if (existingUsers > 0) {
    return NextResponse.json(
      { error: "Registration is disabled — administrator account already exists" },
      { status: 403 }
    );
  }

  const body = await req.json().catch(() => null);
  const parsed = registerSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? "Invalid input" },
      { status: 400 }
    );
  }

  const email = parsed.data.email.toLowerCase().trim();
  const passwordHash = await hashPassword(parsed.data.password);
  const user = await prisma.user.create({ data: { email, passwordHash } });
  // Provision default settings (paper trading ON, bot OFF)
  await prisma.settings.create({ data: { userId: user.id } });
  await prisma.logEntry.create({
    data: { level: "info", source: "api", message: `administrator account created: ${email}` },
  }).catch(() => {});

  return NextResponse.json({ ok: true });
}
