import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { requireUser, unauthorized } from "@/lib/session";

export async function GET() {
  const user = await requireUser();
  if (!user) return unauthorized();

  const weekAgo = new Date(Date.now() - 7 * 86_400_000);
  const [closed, open, daily] = await Promise.all([
    prisma.position.findMany({ where: { status: "CLOSED" } }),
    prisma.position.findMany({ where: { status: "OPEN" } }),
    prisma.dailyStats.findMany({ orderBy: { date: "asc" }, take: 90 }),
  ]);

  const realizedSol = closed.reduce((a, p) => a + (p.pnlSol ?? 0), 0);
  const wins = closed.filter((p) => (p.pnlSol ?? 0) > 0).length;
  const invested = closed.reduce((a, p) => a + p.entrySol, 0);

  const holdsMin = closed
    .filter((p) => p.closedAt)
    .map((p) => (p.closedAt!.getTime() - p.openedAt.getTime()) / 60_000);
  const pnls = closed.map((p) => p.pnlSol ?? 0);
  const weekly = daily.filter((d) => d.date >= weekAgo);

  // cumulative PnL series for the profit graph
  let cum = 0;
  const pnlSeries = daily.map((d) => {
    cum += d.realizedSol;
    return { date: d.date, realizedSol: d.realizedSol, cumulativeSol: cum };
  });

  return NextResponse.json({
    realizedSol,
    weeklyRealizedSol: weekly.reduce((a, d) => a + d.realizedSol, 0),
    openPositions: open.length,
    exposureSol: open.reduce((a, p) => a + p.entrySol, 0),
    closedPositions: closed.length,
    winRate: closed.length ? (wins / closed.length) * 100 : null,
    roiPct: invested > 0 ? (realizedSol / invested) * 100 : null,
    avgHoldMinutes: holdsMin.length ? holdsMin.reduce((a, b) => a + b, 0) / holdsMin.length : null,
    avgPnlSol: pnls.length ? realizedSol / pnls.length : null,
    largestWinSol: pnls.length ? Math.max(...pnls, 0) : null,
    largestLossSol: pnls.length ? Math.min(...pnls, 0) : null,
    pnlSeries,
    today:
      daily.find((d) => d.date.toISOString().slice(0, 10) === new Date().toISOString().slice(0, 10)) ??
      null,
  });
}
