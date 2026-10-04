// The earned month's rule, as the database states it (0058: billing_config,
// read by qamar_earned_month_status). The function never writes its own
// number: the threshold is tunable without a release, so a hard-coded "28"
// or "20" here would be the one sentence that can go wrong.

export type EarnedStatus = { needed?: unknown; window_days?: unknown; logged_days?: unknown };

function count(v: unknown, fallback: number): number {
  return typeof v === "number" && Number.isFinite(v) && v >= 0 ? Math.round(v) : fallback;
}

/** The refusal the app shows when a claim comes too early. */
export function notYetEarnedMessage(status: EarnedStatus | null | undefined): string {
  const needed = count(status?.needed, 20);
  const window = count(status?.window_days, 30);
  const logged = status?.logged_days === undefined ? null : count(status.logged_days, 0);
  const so = logged === null ? "" : ` So far: ${logged}.`;
  return `Not earned yet: ${needed} logged days in the first ${window} are needed.${so}`;
}
