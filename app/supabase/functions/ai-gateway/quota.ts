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
 * Qamar+, and the plan simply waits for tomorrow. Once a day the app also
 * offers the question itself for Su under the chat wall (O13, 0066), as a
 * button shown only when the balance covers it; the words stay Qamar+'s.
 *
 * The words state no number: the day's limits are configuration
 * (ai_quota_config), so "the third question" would go false the day they are
 * tuned. And a member ([plus]) who reaches their own limit is not sold the
 * Qamar+ they already have. Arabic writes the brand as قمر+, which an RTL line
 * draws the right way round.
 */
export function quotaExceededMessage(lang: "ar" | "en", bucket: Bucket, plus = false): string {
  const ar: Record<Bucket, string> = {
    photo:
      "دي كانت آخر صورة النهارده. اكتب أو قول الوجبة مجاناً، أو اصرف نقاط Su على صورة زيادة من المحفظة. الصور بتتجدد الصبح.",
    chat: plus
      ? "دي كانت آخر سؤال النهارده. اسأل تاني الصبح."
      : "دي كانت آخر سؤال ببلاش النهارده. قمر+ بيكمّل معاك الكلام وبيقولك تاكل إيه بكرة — أو اسأل تاني الصبح.",
    plan:
      "الخطة اتكتبت كفاية النهارده. عدّل الوجبات من الخطة نفسها، أو قوللي إيه اللي اتغيّر وأنا أظبط الباقي.",
  };
  const en: Record<Bucket, string> = {
    photo:
      "That was today’s last photo. Type or say the meal for free, or spend Su Points on another photo from the wallet. Photos refresh in the morning.",
    chat: plus
      ? "That was today’s last question. Ask again in the morning."
      : "That was today’s last free question. Qamar+ keeps the conversation going and tells you what to eat tomorrow — or ask again in the morning.",
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
