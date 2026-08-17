/** Cairo calendar day as YYYY-MM-DD — same timezone the quota counter uses. */
export function cairoYmd(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Cairo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

export function isCairoToday(date: string, now = new Date()): boolean {
  const day = date.trim().slice(0, 10);
  return day === cairoYmd(now);
}

export function plusRequiredMessage(lang: "ar" | "en", feature: "meal_photo" | "week_plan"): string {
  if (feature === "meal_photo") {
    return lang === "ar"
      ? "تصوير الوجبة من Qamar+. الكتابة والصوت مجاناً."
      : "Photographing a meal is Qamar+. Typing and speaking stay free.";
  }
  return lang === "ar"
    ? "خطة النهاردة مجاناً. الأيام التانية من Qamar+."
    : "Today’s plan is free. Other days are Qamar+.";
}

export function plusRequiredBody(lang: "ar" | "en", feature: "meal_photo" | "week_plan") {
  return {
    error: plusRequiredMessage(lang, feature),
    refused: true,
    reason: "plus_required",
    feature,
  };
}

/** Fail closed: missing, expired, or unreadable entitlement is not Plus. */
export function entitlementIsActive(
  row: { status?: string; period_end?: string | null } | null | undefined,
  now = new Date(),
): boolean {
  if (!row || row.status !== "active" || !row.period_end) return false;
  const end = Date.parse(row.period_end);
  return Number.isFinite(end) && end > now.getTime();
}
