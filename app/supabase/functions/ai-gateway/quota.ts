// Copy and shape for the daily walls.
//
// Three buckets, counted in Postgres (qamar_ai_try_consume): photo — a meal
// photograph or a body scan, three a day on Lite plus whatever Su bought;
// chat — a question to Qamar, three a day on Lite and the fourth is the
// paywall; plan — writing today's menu, a small cap for everyone that exists
// only to stop a loop. Typing or speaking a meal is never counted.

export type Bucket = "photo" | "chat" | "plan";

export interface Quota {
  bucket: Bucket;
  allowed: boolean;
  used: number;
  limit: number;
  extra: number;
  remaining: number;
  plus?: boolean;
  day?: string;
}

export function asQuota(raw: unknown, fallback: Bucket = "chat"): Quota | null {
  if (!raw || typeof raw !== "object") return null;
  const o = raw as Record<string, unknown>;
  const num = (v: unknown): number | null =>
    typeof v === "number" && Number.isFinite(v) ? v : null;
  const used = num(o.used);
  const limit = num(o.limit);
  const extra = num(o.extra) ?? 0;
  const remaining = num(o.remaining);
  if (used === null || limit === null || remaining === null) return null;
  const bucket = o.bucket === "photo" || o.bucket === "chat" || o.bucket === "plan" ? o.bucket : fallback;
  return {
    bucket,
    allowed: o.allowed === true,
    used,
    limit,
    extra,
    remaining,
    plus: typeof o.plus === "boolean" ? o.plus : undefined,
    day: typeof o.day === "string" ? o.day : undefined,
  };
}

/**
 * What the person is told at the wall. Each bucket has a different way out,
 * and the copy names it: another photo is earned with Su, another question is
 * Qamar+, and the plan simply waits for tomorrow.
 */
export function quotaExceededMessage(lang: "ar" | "en", bucket: Bucket): string {
  const ar: Record<Bucket, string> = {
    photo:
      "خلصت التلات صور بتوع النهارده. اكتب أو قول الوجبة مجاناً، أو اصرف نقاط Su على صورة زيادة من المحفظة. الصور بتتجدد الصبح.",
    chat:
      "دي كانت تالت سؤال النهارده. Qamar+ بيفتح الأسئلة والخطة بتاعة بكرة — أو استنى الصبح وارجع اسأل.",
    plan:
      "الخطة اتكتبت كفاية النهارده. عدّل الوجبات من الخطة نفسها، أو قوللي إيه اللي اتغيّر وأنا أظبط الباقي.",
  };
  const en: Record<Bucket, string> = {
    photo:
      "That’s today’s three photos. Type or say the meal for free, or spend Su Points on another photo from the wallet. Photos refresh in the morning.",
    chat:
      "That was today’s third question. Qamar+ opens the questions and tomorrow’s plan — or come back in the morning.",
    plan:
      "Today’s plan has been rewritten enough. Swap meals on the plan itself, or tell me what changed and I will adjust the rest.",
  };
  return (lang === "ar" ? ar : en)[bucket];
}

/** The bucket's counters, which is what the app parses off every response. */
export function quotaPayload(q: Quota): Record<string, unknown> {
  return {
    bucket: q.bucket,
    used: q.used,
    limit: q.limit,
    extra: q.extra,
    remaining: q.remaining,
    ...(typeof q.plus === "boolean" ? { plus: q.plus } : {}),
  };
}
