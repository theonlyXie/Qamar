// The parts of a barcode scan that can be wrong without anyone noticing.
//
// Run: deno test barcode_test.ts

import { assertEquals } from "jsr:@std/assert@1";
import {
  eatenPortion,
  parseGrams,
  per100FromOff,
  scaleTo,
  type ScannedProduct,
} from "./barcode.ts";

Deno.test("pack sizes as they are actually printed", () => {
  assertEquals(parseGrams("330 ml"), 330);
  assertEquals(parseGrams("25g"), 25);
  // "1 portion" carries no unit, so the parser walks past it to the figure
  // that does. That is the right answer, not a lucky one.
  assertEquals(parseGrams("1 portion (330 ml)"), 330);
  assertEquals(parseGrams("1,5 L"), 1500);
  assertEquals(parseGrams("0.5 kg"), 500);
  assertEquals(parseGrams("40 cl"), 400);
});

Deno.test("Arabic-Indic digits on Egyptian packaging", () => {
  // All three of these returned null until the word boundary was fixed: \b is
  // defined on [A-Za-z0-9_] and never matches after an Arabic letter, so the
  // way an Egyptian packet is actually printed parsed as nothing.
  assertEquals(parseGrams("٢٥ جم"), 25);
  assertEquals(parseGrams("٥٠٠ مل"), 500);
  assertEquals(parseGrams("١٫٥ لتر"), 1500); // Arabic decimal separator
  assertEquals(parseGrams("١ كجم"), 1000);
});

Deno.test("nothing parseable is null, never a guess", () => {
  assertEquals(parseGrams(null), null);
  assertEquals(parseGrams(""), null);
  assertEquals(parseGrams("family size"), null);
  // Not a unit we know. Better nothing than reading it as grams.
  assertEquals(parseGrams("12 gallons"), null);
  assertEquals(parseGrams("500 grams"), 500);
  assertEquals(parseGrams("0 g"), null);
});

Deno.test("Open Food Facts minerals are grams and we store milligrams", () => {
  // 0.5 g of sodium is 500 mg. Reading it as 0.5 mg would report a packet of
  // crisps as containing almost no salt.
  const per100 = per100FromOff({
    "energy-kcal_100g": 536,
    "proteins_100g": 6.6,
    "sodium_100g": 0.5,
    "iron_100g": 0.0014,
    "vitamin-c_100g": 0.0311,
  });
  assertEquals(per100.energy_kcal, 536);
  assertEquals(per100.protein_g, 6.6);
  assertEquals(per100.sodium_mg, 500);
  assertEquals(per100.iron_mg, 1.4);
  assertEquals(per100.vitamin_c_mg, 31.1);
});

Deno.test("a missing or non-numeric nutriment is absent, not zero", () => {
  const per100 = per100FromOff({
    "energy-kcal_100g": 100,
    "proteins_100g": "unknown",
    "fat_100g": null,
  });
  assertEquals(per100.energy_kcal, 100);
  assertEquals("protein_g" in per100, false);
  assertEquals("fat_g" in per100, false);
});

Deno.test("scaling a table to the real weight eaten", () => {
  // A 25 g bag of crisps off a per-100 g table.
  const bag = scaleTo({ energy_kcal: 536, fat_g: 34.6, sodium_mg: 500 }, 25);
  assertEquals(bag.energy_kcal, 134);
  assertEquals(bag.fat_g, 8.65);
  assertEquals(bag.sodium_mg, 125);
});

const product = (over: Partial<ScannedProduct> = {}): ScannedProduct => ({
  barcode: "1",
  name: "Crisps",
  brand: null,
  per100g: { energy_kcal: 536 },
  packGrams: null,
  servingGrams: null,
  packLabel: null,
  source: "open_food_facts",
  sourceUrl: null,
  ...over,
});

Deno.test("eating the packet means the packet, not 100 g", () => {
  const p = eatenPortion(product({ packGrams: 25, packLabel: "25 g" }));
  assertEquals(p.grams, 25);
  assertEquals(p.assumed, false);
});

Deno.test("a serving is the fallback when the pack size is not printed", () => {
  const p = eatenPortion(product({ servingGrams: 30 }));
  assertEquals(p.grams, 30);
  assertEquals(p.assumed, false);
});

Deno.test("an implausible pack weight is not trusted", () => {
  // 5 kg is a catering box, not something one person ate in a sitting. Falling
  // back to the labelled serving is far better than logging 27,000 kcal.
  const p = eatenPortion(product({ packGrams: 5000, servingGrams: 30 }));
  assertEquals(p.grams, 30);
});

Deno.test("with nothing printed, 100 g is used and flagged as an assumption", () => {
  const p = eatenPortion(product());
  assertEquals(p.grams, 100);
  assertEquals(p.assumed, true);
});
