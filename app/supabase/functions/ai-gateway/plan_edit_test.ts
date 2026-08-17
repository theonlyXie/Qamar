// Tests for turning a chat plan_update into the meals the screens show.
// Run: deno test plan_edit_test.ts

import { assertEquals } from "jsr:@std/assert@1";
import { foodTermsFromMeals, mergePlanUpdate, normalizeSlot, planUpdateKind } from "./plan_edit.ts";
import { chatSystemPrompt } from "./model.ts";
import type { Meal } from "./verify.ts";
import type { UserContext } from "./model.ts";

const foul: Meal = {
  slot: "breakfast",
  name_ar: "فول",
  name_en: "Foul",
  portions: [{ ar: "فول", en: "Foul", amount_ar: "١٥٠ جم", amount_en: "150 g", kcal: 180 }],
};
const koshary: Meal = {
  slot: "lunch",
  name_ar: "كشري",
  name_en: "Koshary",
  portions: [{ ar: "كشري", en: "Koshary", amount_ar: "طبق", amount_en: "1 bowl", kcal: 520 }],
};
const tuna: Meal = {
  slot: "dinner",
  name_ar: "تونة",
  name_en: "Tuna",
  portions: [{ ar: "تونة", en: "Tuna", amount_ar: "علبة", amount_en: "1 tin", kcal: 130 }],
};

const day = [foul, koshary, tuna];

Deno.test("Arabic dinner is the same slot the app uses", () => {
  assertEquals(normalizeSlot("عشا"), "dinner");
  assertEquals(normalizeSlot("Dinner"), "dinner");
  assertEquals(normalizeSlot("فطار"), "breakfast");
});

Deno.test("a meal plus slot is a replace even without kind", () => {
  assertEquals(planUpdateKind({ slot: "dinner", meal: tuna }), "replace_slot");
  assertEquals(planUpdateKind({ kind: "rebuild", instruction: "no cook" }), "rebuild");
  assertEquals(planUpdateKind({ meals: [foul, koshary, tuna] }), "replace_day");
  assertEquals(planUpdateKind({ kind: "chat" }), "none");
});

Deno.test("replacing dinner leaves breakfast and lunch where they were", () => {
  const eggs: Meal = {
    name_ar: "بيض وجبنة",
    name_en: "Eggs and cheese",
    portions: [{ ar: "بيض", en: "Eggs", amount_ar: "٢", amount_en: "2", kcal: 160 }],
    alt: {
      name_ar: "زبادي",
      name_en: "Yogurt",
      portions: [{ ar: "زبادي", en: "Yogurt", amount_ar: "علبة", amount_en: "1 pot", kcal: 150 }],
    },
  };
  const merged = mergePlanUpdate(day, { kind: "replace_slot", slot: "عشا", meal: eggs });
  assertEquals(merged?.kind, "replace_slot");
  assertEquals(merged?.meals.map((m) => m.name_en), ["Foul", "Koshary", "Eggs and cheese"]);
  assertEquals(merged?.meals[2].slot, "dinner");
  assertEquals(merged?.meals[2].alt?.name_en, "Yogurt");
});

Deno.test("a full-day replace is what the screens will show, not a merge", () => {
  const next = [{ ...foul, name_en: "Eggs" }, koshary, tuna];
  const merged = mergePlanUpdate(day, { kind: "replace_day", meals: next });
  assertEquals(merged?.meals[0].name_en, "Eggs");
  assertEquals(merged?.meals.length, 3);
});

Deno.test("rebuilding carries the nutritionist instruction and does not invent meals", () => {
  const merged = mergePlanUpdate(day, {
    kind: "rebalance",
    instruction: "tired, no cooking tonight",
  });
  assertEquals(merged?.kind, "rebuild");
  assertEquals(merged?.instruction, "tired, no cooking tonight");
  assertEquals(merged?.meals, day);
});

Deno.test("editing a slot with no menu yet becomes a rebuild, not a one-meal day", () => {
  const merged = mergePlanUpdate(null, { kind: "replace_slot", slot: "dinner", meal: tuna });
  assertEquals(merged?.kind, "rebuild");
});

Deno.test("food names on the current menu are look-up terms", () => {
  assertEquals(foodTermsFromMeals(day).includes("Koshary"), true);
  assertEquals(foodTermsFromMeals(day).includes("فول"), true);
});

Deno.test("the chat prompt tells Qamar to write the on-screen menu", () => {
  const u: UserContext = { lang: "ar", targetKcal: 1800, exclusions: ["sesame"] };
  const prompt = chatSystemPrompt(u, [], "(none)", JSON.stringify({ meals: day }));
  assertEquals(prompt.includes("plan_update"), true);
  assertEquals(prompt.includes("TODAY'S MENU"), true);
  assertEquals(prompt.includes("Koshary"), true);
});
