// The night job: Qamar+ members wake to tomorrow's plan.
//
// Pure helpers only — the route in index.ts does the database and model work.
// Everything here is about *when* and *for whom*, which is what needs testing
// without a database: Cairo's clock (UTC+2 in winter, UTC+3 in summer, so a
// fixed UTC cron cannot hit 22:00 Cairo all year), and the rule that a member
// who already has tomorrow's plan is never written a second one.

/** The Cairo hour the job is meant for. Runs are accepted through the hour after, so a
 * second cron slot can pick up members a long first pass did not reach. */
export const NIGHTLY_HOUR = 22;
export const NIGHTLY_HOURS = [NIGHTLY_HOUR, NIGHTLY_HOUR + 1];

/** Members per run. A plan is one model call; a run is bounded by the function's wall clock. */
export const MAX_PER_RUN = 200;

/** Milliseconds a run spends writing plans before it stops and reports the rest. */
export const RUN_BUDGET_MS = 110_000;

const cairo = new Intl.DateTimeFormat("en-GB", {
  timeZone: "Africa/Cairo",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  hour12: false,
});

/** The Cairo calendar date (YYYY-MM-DD) and hour (0–23) at [now]. */
export function cairoNow(now: Date): { date: string; hour: number } {
  const parts = Object.fromEntries(cairo.formatToParts(now).map((p) => [p.type, p.value]));
  // "24" appears for midnight in some ICU builds; the date is already right.
  const hour = Number(parts.hour) % 24;
  return { date: `${parts.year}-${parts.month}-${parts.day}`, hour };
}

/** The Cairo date [days] after the Cairo date at [now]. */
export function cairoDatePlus(now: Date, days: number): string {
  const { date } = cairoNow(now);
  const [y, m, d] = date.split("-").map(Number);
  const shifted = new Date(Date.UTC(y, m - 1, d + days));
  return shifted.toISOString().slice(0, 10);
}

/** True when a run fired at [now] should write plans. */
export function isNightlyWindow(now: Date): boolean {
  return NIGHTLY_HOURS.includes(cairoNow(now).hour);
}

/**
 * Members who still need tomorrow's plan, in the order given, capped at
 * [MAX_PER_RUN]. Duplicates and anyone in [alreadyPlanned] drop out.
 */
export function dueMembers(plusMembers: Iterable<string>, alreadyPlanned: Iterable<string>): string[] {
  const done = new Set(alreadyPlanned);
  const out: string[] = [];
  for (const id of plusMembers) {
    if (done.has(id)) continue;
    done.add(id);
    out.push(id);
    if (out.length >= MAX_PER_RUN) break;
  }
  return out;
}

export interface NightlyReport {
  date: string;
  ran: boolean;
  reason?: string;
  written: number;
  skipped: number;
  failed: number;
  remaining: number;
  failures: Array<{ user: string; status: number; error?: string }>;
}
