// How Qamar edits the day's menu from a conversation.
//
// The Plan and Today screens show whatever is in meal_plans. Chat used to
// return prose only, so talking to the nutritionist never moved a dish. The
// model now returns a structured plan_update; these helpers turn that into
// the meal list that gets verified and saved. Kept pure so a bad merge is
// caught in tests rather than on someone's dinner.

import type { Meal } from "./verify.ts";

export type PlanUpdateKind = "none" | "rebuild" | "replace_slot" | "replace_day";

export interface PlanUpdate {
  kind?: string;
  type?: string;
  slot?: string;
  meal?: Meal;
  meals?: Meal[];
  plan?: { meals?: Meal[] };
  instruction?: string;
  reason?: string;
  notes?: string;
}

export function planUpdateKind(update: PlanUpdate | null | undefined): PlanUpdateKind {
  if (!update || typeof update !== "object") return "none";
  const raw = `${update.kind ?? update.type ?? ""}`.toLowerCase().trim();
  if (raw === "rebuild" || raw === "regenerate" || raw === "rebalance") return "rebuild";
  if (raw === "replace_slot" || raw === "swap_slot" || raw === "edit_slot") return "replace_slot";
  if (raw === "replace_day" || raw === "replace_plan" || raw === "set_day") return "replace_day";
  if (update.meal && update.slot) return "replace_slot";
  if (Array.isArray(update.meals) && update.meals.length > 0) return "replace_day";
  return "none";
}

/** Breakfast / lunch / dinner (and snack), including the Arabic labels the app uses. */
export function normalizeSlot(slot: string | undefined | null): string | null {
  const s = (slot ?? "").toLowerCase().trim();
  if (s === "breakfast" || s === "فطار" || s === "فطور") return "breakfast";
  if (s === "lunch" || s === "غدا" || s === "غداء") return "lunch";
  if (s === "dinner" || s === "عشا" || s === "عشاء") return "dinner";
  if (s === "snack" || s === "سناك") return "snack";
  return s || null;
}

export interface MergedPlan {
  kind: PlanUpdateKind;
  meals: Meal[];
  instruction?: string;
}

/**
 * Applies a chat plan_update onto the meals currently on the person's screens.
 *
 * A rebuild does not invent meals here — it carries an instruction so the
 * existing plan generator can rewrite the day as a nutritionist would.
 * replace_slot with no current menu also becomes a rebuild: there is nothing
 * to patch, and a one-meal "plan" would look like a day of eating.
 */
export function mergePlanUpdate(
  current: Meal[] | null | undefined,
  update: PlanUpdate,
): MergedPlan | null {
  const kind = planUpdateKind(update);
  if (kind === "none") return null;

  const instruction = (update.instruction ?? update.reason ?? "").trim() || undefined;

  if (kind === "rebuild") {
    return { kind, meals: current ?? [], instruction };
  }

  if (kind === "replace_day") {
    const meals = update.meals ?? update.plan?.meals;
    if (!Array.isArray(meals) || meals.length === 0) return null;
    return { kind, meals, instruction };
  }

  const slot = normalizeSlot(update.slot);
  const meal = update.meal;
  if (!slot || !meal || typeof meal !== "object") return null;

  const have = Array.isArray(current) ? current : [];
  if (have.length === 0) {
    return { kind: "rebuild", meals: [], instruction: instruction ?? slot };
  }

  const patched: Meal = { ...meal, slot };
  const next = have.map((m) => (normalizeSlot(m.slot) === slot ? patched : m));
  if (!next.some((m) => normalizeSlot(m.slot) === slot)) next.push(patched);
  return { kind: "replace_slot", meals: next, instruction };
}

/** Names to look up so a menu edit is priced from food data, not invented. */
export function foodTermsFromMeals(meals: Meal[] | null | undefined): string[] {
  const out: string[] = [];
  for (const m of meals ?? []) {
    for (const s of [
      m.name_ar,
      m.name_en,
      ...(m.portions ?? []).flatMap((p) => [p.ar, p.en]),
      m.alt?.name_ar,
      m.alt?.name_en,
    ]) {
      if (typeof s === "string" && s.trim().length > 1) out.push(s.trim());
    }
  }
  return out;
}
