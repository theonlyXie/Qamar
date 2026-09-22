// The sentences a meal reading carries back to the person (its `note`).
//
// A note is the reading's caveat, shown with the proposal before anything is
// confirmed: where the numbers came from, or which portion was assumed. It is
// never about points. "Fixed points keep the economy honest; variable words
// keep the reward alive" (blueprint, line 614): the wallet counts, Qamar
// talks, and no word Qamar says is about Su, points or earning (O3). The eval
// suite holds this for both kinds of note (kind "meal_note", eval.ts).

import type { MealItem } from "./verify.ts";

/** Words about the score, in either language. A note must never carry them. */
export const SCORE_WORDS = /\bsu\b|\bpoints?\b|\bearn|\breward|\bcoins?\b|نقط|نقاط|كسب|مكافأ/i;

export function mentionsScore(text: string): boolean {
  return SCORE_WORDS.test(text);
}

/** The typed or spoken meal's note, priced from the food graph alone. */
export function graphMealNote(lang: "ar" | "en", items: MealItem[]): string {
  if (items.length === 0) {
    return lang === "ar"
      ? "مقدرتش ألاقي الأكل ده في قاعدة البيانات. جرّب اسم أوضح. تصوير الطبق لـ Qamar+."
      : "I could not match that to a food we know. Try a clearer name. Photographing a plate is Qamar+.";
  }
  return lang === "ar"
    ? "الأرقام من قاعدة الأكل، مش من الموديل. ظبّط الكميات قبل ما تأكد."
    : "These numbers come from the food database, not the model. Adjust the amounts before you confirm.";
}

/**
 * The model's note on a photographed or described plate, as the person will
 * read it: trimmed, and dropped whole if it talks about the score. A dropped
 * note costs nothing; the items and their numbers stand on their own.
 */
export function modelMealNote(note: string | null | undefined): string | null {
  const t = typeof note === "string" ? note.trim() : "";
  if (!t || mentionsScore(t)) return null;
  return t;
}
