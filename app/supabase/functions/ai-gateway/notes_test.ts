// The meal reading's notes (notes.ts) say only what is true: no photo is ever
// said to need Qamar+ (the free tier photographs three plates a day), and a
// photo is offered only while today's photos last. The not-found lines are the
// app's own (AppState.notFoundReply), copied here verbatim so the two agree.
// Run: deno test notes_test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import { graphMealNote, modelMealNote } from "./notes.ts";
import type { MealItem } from "./verify.ts";

const found: MealItem[] = [{ en: "Koshary", ar: "كشري", kcal: 507 } as MealItem];

Deno.test("nothing matched, photos left: a clearer name, or photograph the plate", () => {
  assertEquals(graphMealNote("en", [], true), "I could not match that food. Try a clearer name, or photograph the plate.");
  assertEquals(graphMealNote("ar", [], true), "مقدرتش ألاقي الأكل ده. جرّب اسم أوضح، أو صوّر الطبق.");
});

Deno.test("nothing matched, no photos left or none known: what is in it and how much, and no photo", () => {
  for (const photosLeft of [false, undefined]) {
    assertEquals(graphMealNote("en", [], photosLeft), "I could not match that food. Try a clearer name, or tell me what’s in it and how much.");
    assertEquals(graphMealNote("ar", [], photosLeft), "مقدرتش ألاقي الأكل ده. جرّب اسم أوضح، أو قوللي فيه إيه وقد إيه.");
  }
});

Deno.test("no note says a photo, or anything, is Qamar+", () => {
  const plus = /qamar\s*\+|قمر\s*\+|\bplus\b|membership|اشتراك/i;
  for (const lang of ["ar", "en"] as const) {
    for (const items of [[], found]) {
      for (const photosLeft of [true, false]) {
        const note = graphMealNote(lang, items, photosLeft);
        assert(!plus.test(note), note);
      }
    }
  }
});

Deno.test("a matched meal's note is unchanged: the numbers are the food database's", () => {
  assertEquals(graphMealNote("en", found, true), "These numbers come from the food database, not the model. Adjust the amounts before you confirm.");
  assertEquals(graphMealNote("ar", found, false), "الأرقام من قاعدة الأكل، مش من الموديل. ظبّط الكميات قبل ما تأكد.");
});

Deno.test("a model note is shown trimmed, and dropped if it talks points", () => {
  assertEquals(modelMealNote("  I assumed a medium plate.  "), "I assumed a medium plate.");
  assertEquals(modelMealNote("You earned 100 Su!"), null);
  assertEquals(modelMealNote(""), null);
});
