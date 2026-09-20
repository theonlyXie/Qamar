// The night job: members wake to tomorrow's plan; everyone who logged today
// wakes to one sentence about it.
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
  /** Qamar+ members in tonight's audience. */
  plus: number;
  /** Free-tier accounts that logged today, and so get the sentence too. */
  lite: number;
  written: number;
  /** Night sentences written (for plans written tonight or already there). */
  noted: number;
  skipped: number;
  failed: number;
  remaining: number;
  failures: Array<{ user: string; status: number; error?: string }>;
}

// ---- the night sentence ---------------------------------------------------

/** Portion calories summed across the plan's meals. Alternatives are not counted. */
export function planKcal(meals: Array<{ portions?: Array<{ kcal?: number }> }>): number {
  let sum = 0;
  for (const m of meals) for (const p of m.portions ?? []) sum += Number(p.kcal) || 0;
  return Math.round(sum);
}

export interface NightSentence {
  ar: string;
  en: string;
}

/** Below this, tomorrow and today are "the same rhythm". */
export const SAME_RHYTHM_PCT = 10;

/**
 * The one sentence written at night and read in the morning: tomorrow against
 * today, in Qamar's voice, and no dish named. The free tier sees this line
 * with the plan locked behind it (the blueprint's fourth paywall), so it has
 * to be worth reading without giving the plan away. Western digits — the
 * phone redraws them in the digits the person chose.
 */
export function nightSentence(input: { planKcal: number; todayKcal: number; meals: number }): NightSentence {
  const { planKcal: plan, todayKcal: today, meals } = input;
  if (today <= 0) {
    return {
      ar: `بكرة جاهز: ${plan} سعرة على ${meals} وجبات، مبني على هدفك — النهارده مفيش تسجيل.`,
      en: `Tomorrow is ready: ${plan} kcal over ${meals} meals, built on your target — nothing was logged today.`,
    };
  }
  const pct = Math.round(((plan - today) / today) * 100);
  if (pct <= -SAME_RHYTHM_PCT) {
    return {
      ar: `بكرة أخف من النهارده بـ ${-pct}٪ — ${plan} سعرة على ${meals} وجبات.`,
      en: `Tomorrow is ${-pct}% lighter than today — ${plan} kcal over ${meals} meals.`,
    };
  }
  if (pct >= SAME_RHYTHM_PCT) {
    return {
      ar: `النهارده كنت تحت هدفك، فبكرة أكتر بـ ${pct}٪ — ${plan} سعرة على ${meals} وجبات.`,
      en: `You were under your target today, so tomorrow is ${pct}% more — ${plan} kcal over ${meals} meals.`,
    };
  }
  return {
    ar: `بكرة نفس إيقاع النهارده تقريباً — ${plan} سعرة على ${meals} وجبات.`,
    en: `Tomorrow keeps today's rhythm — ${plan} kcal over ${meals} meals.`,
  };
}

/** Splits [ids] into URL-sized groups for PostgREST `in.(...)` filters. */
export function chunks<T>(ids: T[], size = 100): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < ids.length; i += size) out.push(ids.slice(i, i + size));
  return out;
}
