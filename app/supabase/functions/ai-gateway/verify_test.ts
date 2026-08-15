// Tests for the verifier. Run: deno test verify_test.ts
//
// This is the component that decides whether an answer is allowed to reach
// someone as a checked number, so the cases below are written as a
// specification of that boundary: what it must catch, what it must not catch,
// and what it must refuse to claim it checked.

import { assertEquals } from "jsr:@std/assert@1";
import {
  blocks,
  finalVerdict,
  isImprovement,
  isRevisable,
  revisableCount,
  revisionInstruction,
  verifyChat,
  verifyMeal,
  verifyPlan,
  type Meal,
  type MealItem,
} from "./verify.ts";
import type { Restriction } from "./safety.ts";

const item = (over: Partial<MealItem> = {}): MealItem => ({
  en: "foul",
  kcal: 200,
  proteinG: 13,
  carbsG: 27,
  fatG: 4,
  ...over,
});

const types = (fs: { failure_type: string }[]) => fs.map((f) => f.failure_type);

// ---- meal analysis ------------------------------------------------------

Deno.test("passes a meal whose macros reconcile with its kcal", () => {
  // 4(13) + 4(27) + 9(4) = 196, against a stated 200.
  const v = verifyMeal([item()]);
  assertEquals(v.verdict, "PASS");
  assertEquals(v.failures, []);
});

Deno.test("catches macros that do not add up to the stated kcal", () => {
  // 4(10) + 4(30) + 9(5) = 205, stated 600. One of those two is wrong, and the
  // kcal is the one that reaches the daily total.
  const v = verifyMeal([item({ kcal: 600, proteinG: 10, carbsG: 30, fatG: 5 })]);
  assertEquals(v.verdict, "REVISE");
  assertEquals(types(v.failures), ["atwater_mismatch"]);
  assertEquals((v.recomputed.items as { kcal_from_macros: number }[])[0].kcal_from_macros, 205);
});

Deno.test("tolerates the drift real food actually has", () => {
  // Fibre, rounding and cooking losses move this by more than a few kcal, and a
  // verifier that revises on 6% would spend every correction on nothing.
  assertEquals(verifyMeal([item({ kcal: 210 })]).verdict, "PASS");
  assertEquals(verifyMeal([item({ kcal: 185 })]).verdict, "PASS");
});

Deno.test("does not let a small item fail on a rounding difference", () => {
  // 4(1) + 4(2) + 9(0) = 12 against a stated 30. Proportionally enormous,
  // absolutely trivial — the floor exists for exactly this.
  assertEquals(verifyMeal([item({ kcal: 30, proteinG: 1, carbsG: 2, fatG: 0 })]).verdict, "PASS");
});

Deno.test("flags an item with no kcal and one with an impossible kcal", () => {
  assertEquals(types(verifyMeal([item({ kcal: undefined })]).failures), ["missing_kcal"]);
  const absurd = verifyMeal([item({ kcal: 9000, proteinG: 500, carbsG: 500, fatG: 500 })]);
  assertEquals(absurd.failures.some((f) => f.failure_type === "implausible_kcal"), true);
});

Deno.test("records missing macros without demanding a correction", () => {
  // Nothing can be recomputed, so there is nothing to revise towards. Saying so
  // is the honest outcome; asking the model to try again is not.
  const v = verifyMeal([item({ proteinG: undefined })]);
  assertEquals(types(v.failures), ["missing_macros"]);
  assertEquals(v.verdict, "PASS");
  assertEquals(isRevisable(v), false);
});

// ---- plan ---------------------------------------------------------------

const portion = (kcal: number) => ({ en: "portion", ar: "حصة", kcal });

const meal = (slot: string, kcal: number, over: Partial<Meal> = {}): Meal => ({
  slot,
  name_en: slot,
  name_ar: slot,
  portions: [portion(kcal)],
  ...over,
});

const day = (b: number, l: number, d: number): Meal[] => [
  meal("breakfast", b),
  meal("lunch", l),
  meal("dinner", d),
];

Deno.test("passes a day that totals within 5% of the target", () => {
  const v = verifyPlan(day(500, 800, 700), 2000, []);
  assertEquals(v.verdict, "PASS");
  assertEquals(v.recomputed.total_kcal, 2000);
});

Deno.test("catches a day that misses its target", () => {
  const v = verifyPlan(day(500, 500, 500), 2000, []);
  assertEquals(v.verdict, "REVISE");
  assertEquals(types(v.failures), ["target_mismatch"]);
  assertEquals(v.recomputed.delta_kcal, -500);
  assertEquals(v.recomputed.delta_pct, -25);
});

Deno.test("sums each meal separately, so the miss can be located", () => {
  const v = verifyPlan(day(500, 800, 700), 2000, []);
  assertEquals(v.recomputed.meal_totals, { breakfast: 500, lunch: 800, dinner: 700 });
});

Deno.test("flags a portion with no kcal rather than totalling around it", () => {
  const broken: Meal[] = [
    { slot: "breakfast", portions: [portion(300), { en: "bread" }] },
    meal("lunch", 800),
    meal("dinner", 700),
  ];
  assertEquals(types(verifyPlan(broken, 2000, []).failures).includes("missing_portion_kcal"), true);
});

Deno.test("an allergen in the generated plan is never revised, only refused", () => {
  // The filtering upstream removes restricted foods from the list the model is
  // shown. Nothing stops it naming one that was never on that list, which is
  // the whole reason this check exists downstream of the model.
  const restrictions: Restriction[] = [{ label: "sesame", kind: "allergy", severity: "severe" }];
  const plan = day(500, 800, 700);
  plan[1].name_en = "grilled chicken with sesame sauce";

  const v = verifyPlan(plan, 2000, restrictions);
  assertEquals(v.verdict, "ESCALATE");
  assertEquals(types(blocks(v)), ["restricted_food_present"]);
  // An escalation is not a revision. Re-asking the same model that just ignored
  // the constraint is not a control.
  assertEquals(isRevisable(v), false);
});

Deno.test("finds a restriction in the alternative and in the portions too", () => {
  const restrictions: Restriction[] = [{ label: "طحينة", kind: "allergy", severity: null }];
  const withAlt = day(500, 800, 700);
  withAlt[0].alt = { name_en: "baba ghanoug", name_ar: "بابا غنوج بالطحينة", portions: [portion(500)] };
  assertEquals(verifyPlan(withAlt, 2000, restrictions).verdict, "ESCALATE");

  const inPortion = day(500, 800, 700);
  inPortion[2].portions = [{ en: "tahina", ar: "طحينة", kcal: 700 }];
  assertEquals(verifyPlan(inPortion, 2000, restrictions).verdict, "ESCALATE");
});

Deno.test("an alternative far off its meal is noted, not corrected", () => {
  // Worth recording, not worth a model call: the user only sees it if they tap
  // the swap, and a revision round would spend the cap on the wrong problem.
  const plan = day(500, 800, 700);
  plan[0].alt = { name_en: "eggs", portions: [portion(900)] };
  const v = verifyPlan(plan, 2000, []);
  assertEquals(types(v.failures), ["alt_kcal_mismatch"]);
  assertEquals(v.verdict, "PASS");
});

Deno.test("checks nothing against a target that does not exist", () => {
  const v = verifyPlan(day(500, 800, 700), null, []);
  assertEquals(v.verdict, "PASS");
  assertEquals(v.recomputed.delta_kcal, undefined);
  assertEquals(v.recomputed.total_kcal, 2000);
});

// ---- chat ---------------------------------------------------------------

Deno.test("never claims to have checked a number it cannot check", () => {
  const v = verifyChat("A plate of foul is about 250 kcal.", []);
  assertEquals(v.verdict, "PASS");
  // A PASS on a chat row must not be mistaken for arithmetic that held.
  assertEquals(v.recomputed.numeric_claims_recomputed, false);
});

Deno.test("notes a restricted food in prose without suppressing the reply", () => {
  // "you are allergic to sesame, so skip the tahina" and "have some tahina"
  // both contain the word. Acting on this would suppress the wrong one.
  const restrictions: Restriction[] = [{ label: "sesame", kind: "allergy", severity: "severe" }];
  const v = verifyChat("You told me you are allergic to sesame, so skip the tahina.", restrictions);
  assertEquals(types(v.failures), ["restricted_food_mentioned"]);
  assertEquals(v.verdict, "PASS");
  assertEquals(blocks(v), []);
});

// ---- the revision cap ---------------------------------------------------

Deno.test("a failure that survives its one correction escalates", () => {
  const before = verifyPlan(day(500, 500, 500), 2000, []);
  assertEquals(before.verdict, "REVISE");
  const after = finalVerdict(before);
  assertEquals(after.verdict, "ESCALATE");
  // Escalating an arithmetic miss is not the same as blocking it: the day of
  // food is still returned, with the recomputed total attached.
  assertEquals(blocks(after), []);
  assertEquals(after.failures[0].detail.includes("still failing after one revision"), true);
});

Deno.test("a correction is accepted only if it is actually better", () => {
  const bad = verifyPlan(day(500, 500, 500), 2000, []);
  const good = verifyPlan(day(500, 800, 700), 2000, []);
  const worse = verifyPlan([
    { slot: "breakfast", portions: [portion(300), { en: "bread" }] },
    meal("lunch", 200),
    meal("dinner", 200),
  ], 2000, []);

  assertEquals(revisableCount(bad), 1);
  assertEquals(isImprovement(bad, good), true);
  assertEquals(isImprovement(bad, worse), false);
});

Deno.test("a correction that introduces an allergen is rejected outright", () => {
  const restrictions: Restriction[] = [{ label: "sesame", kind: "allergy", severity: "severe" }];
  const bad = verifyPlan(day(500, 500, 500), 2000, restrictions);
  const onTargetButUnsafe = day(500, 800, 700);
  onTargetButUnsafe[0].name_en = "sesame bread";
  const after = verifyPlan(onTargetButUnsafe, 2000, restrictions);

  // It fixed the arithmetic, so by count alone it looks better. It is not.
  assertEquals(revisableCount(after) < revisableCount(bad), true);
  assertEquals(isImprovement(bad, after), false);
});

Deno.test("the revision prompt carries the failures and the previous answer", () => {
  const v = verifyMeal([item({ kcal: 600, proteinG: 10, carbsG: 30, fatG: 5 })]);
  const text = revisionInstruction(v, { items: [{ en: "foul", kcal: 600 }] });
  assertEquals(text.includes("205 kcal"), true);
  assertEquals(text.includes("\"kcal\":600"), true);
  // The original question is deliberately absent — the system prompt still
  // holds the task, and restating it invites a rewrite instead of a fix.
  assertEquals(text.includes("Return the corrected JSON"), true);
});

Deno.test("an advisory finding never earns a correction round", () => {
  const plan = day(500, 800, 700);
  plan[0].alt = { name_en: "eggs", portions: [portion(900)] };
  assertEquals(isRevisable(verifyPlan(plan, 2000, [])), false);
});
