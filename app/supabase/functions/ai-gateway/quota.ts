// Copy and shape for the shared daily AI allowance.
// The counter itself lives in Postgres (qamar_ai_try_consume); this is what
// the gateway returns when the five uses are gone, and how a 200 response
// carries the remaining count so the app can show it.

export interface Quota {
  allowed: boolean;
  used: number;
  limit: number;
  extra: number;
  remaining: number;
  day?: string;
}

export function asQuota(raw: unknown): Quota | null {
  if (!raw || typeof raw !== "object") return null;
  const o = raw as Record<string, unknown>;
  const num = (v: unknown): number | null =>
    typeof v === "number" && Number.isFinite(v) ? v : null;
  const used = num(o.used);
  const limit = num(o.limit);
  const extra = num(o.extra) ?? 0;
  const remaining = num(o.remaining);
  if (used === null || limit === null || remaining === null) return null;
  return {
    allowed: o.allowed === true,
    used,
    limit,
    extra,
    remaining,
    day: typeof o.day === "string" ? o.day : undefined,
  };
}

export function quotaExceededMessage(lang: "ar" | "en"): string {
  return lang === "ar"
    ? "خلصت الخمس استخدامات لـ قمر النهارده. سجّل أكلك أو خلّص مهمة اليوم عشان تكسب نقاط Su، وصرفهم على استخدام زيادة من المحفظة. بكرة الصبح بيتجددوا."
    : "That’s today’s five Qamar uses. Log a meal or finish the daily quest to earn Su Points, then spend them on another use from the wallet. They refresh at Cairo midnight.";
}

export function quotaPayload(q: Quota): Record<string, number> {
  return {
    used: q.used,
    limit: q.limit,
    extra: q.extra,
    remaining: q.remaining,
  };
}
