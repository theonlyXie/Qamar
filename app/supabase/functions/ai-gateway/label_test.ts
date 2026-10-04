// Every way a nutrition panel can produce a wrong number.
//
// Run: deno test label_test.ts

import { assertEquals } from "jsr:@std/assert@1";
import { labelProblemText, normaliseLabel, type LabelProblem } from "./label.ts";

const ok = (r: ReturnType<typeof normaliseLabel>) => {
  if (!r.ok) throw new Error(`expected a reading, got problem: ${r.problem}`);
  return r.value;
};
const problem = (r: ReturnType<typeof normaliseLabel>): LabelProblem => {
  if (r.ok) throw new Error("expected a problem, got a reading");
  return r.problem;
};

Deno.test("a per-100g panel passes through unchanged", () => {
  const v = ok(normaliseLabel({
    basis: "per_100g",
    kcal: 536,
    proteinG: 6.6,
    carbsG: 53,
    fatG: 34.6,
    saltG: 1.25,
  }));
  assertEquals(v.per100g.energy_kcal, 536);
  assertEquals(v.per100g.protein_g, 6.6);
  assertEquals(v.basis, "per_100g");
  // 1 g of salt is 400 mg of sodium.
  assertEquals(v.per100g.sodium_mg, 500);
});

Deno.test("a per-serving panel is converted, not taken at face value", () => {
  // An American panel: 30 g serving, 160 kcal. Read as per-100g that is a
  // three-fold understatement of the food.
  const v = ok(normaliseLabel({
    basis: "per_serving",
    servingGrams: 30,
    kcal: 160,
    proteinG: 2,
    carbsG: 15,
    fatG: 10,
  }));
  assertEquals(v.per100g.energy_kcal, 533.3);
  assertEquals(v.per100g.protein_g, 6.67);
  assertEquals(v.servingGrams, 30);
  assertEquals(v.basis, "per_serving");
});

Deno.test("per serving with no serving weight is refused, never assumed", () => {
  assertEquals(
    problem(normaliseLabel({ basis: "per_serving", kcal: 160, servingGrams: null })),
    "serving_basis_without_serving_size",
  );
});

Deno.test("kilojoules become kilocalories", () => {
  // A European panel leading with kJ. 2000 kJ is 478 kcal, not 2000.
  const v = ok(normaliseLabel({ basis: "per_100g", kj: 2000 }));
  assertEquals(v.per100g.energy_kcal, 478);
  assertEquals(v.energyFromKj, true);
});

Deno.test("kcal is preferred when both are printed", () => {
  const v = ok(normaliseLabel({ basis: "per_100g", kcal: 250, kj: 1046 }));
  assertEquals(v.per100g.energy_kcal, 250);
  assertEquals(v.energyFromKj, false);
});

Deno.test("nothing edible exceeds 900 kcal per 100 g", () => {
  // A misplaced decimal, or a kJ figure typed into the kcal box.
  assertEquals(problem(normaliseLabel({ basis: "per_100g", kcal: 5400 })), "implausible_energy");
  // Pure oil is right at the limit and must still pass.
  assertEquals(ok(normaliseLabel({ basis: "per_100g", kcal: 899 })).per100g.energy_kcal, 899);
});

Deno.test("the conversion is checked for plausibility too", () => {
  // 30 g serving read as 800 kcal scales to 2,666 per 100 g.
  assertEquals(
    problem(normaliseLabel({ basis: "per_serving", servingGrams: 30, kcal: 800 })),
    "implausible_energy",
  );
});

Deno.test("macros that do not account for the energy mean a misread column", () => {
  // 536 kcal claimed, but 4·2 + 4·5 + 9·1 = 37. One of the two was read from
  // the wrong column of the panel.
  assertEquals(
    problem(normaliseLabel({
      basis: "per_100g",
      kcal: 536,
      proteinG: 2,
      carbsG: 5,
      fatG: 1,
    })),
    "energy_disagrees_with_macros",
  );
});

Deno.test("printed rounding and fibre do not trip the cross-check", () => {
  // A real panel: Atwater on these gives 521 against a printed 536, which is
  // ordinary rounding plus fibre and must pass.
  const v = ok(normaliseLabel({
    basis: "per_100g",
    kcal: 536,
    proteinG: 6.6,
    carbsG: 53,
    fatG: 34.6,
  }));
  assertEquals(v.per100g.energy_kcal, 536);
});

Deno.test("an illegible photo is a problem, not a partial reading", () => {
  assertEquals(problem(normaliseLabel({ legible: false, kcal: 200 })), "illegible");
});

Deno.test("no energy at all", () => {
  assertEquals(problem(normaliseLabel({ basis: "per_100g", proteinG: 5 })), "no_energy");
});

Deno.test("a missing macro is absent rather than zero", () => {
  const v = ok(normaliseLabel({ basis: "per_100g", kcal: 100, proteinG: null }));
  assertEquals("protein_g" in v.per100g, false);
});

Deno.test("every problem has real copy in both languages", () => {
  const all: LabelProblem[] = [
    "illegible",
    "no_energy",
    "serving_basis_without_serving_size",
    "implausible_energy",
    "energy_disagrees_with_macros",
  ];
  for (const p of all) {
    for (const lang of ["ar", "en"]) {
      const text = labelProblemText(p, lang);
      // Not a stub, and it tells them what to do about it.
      assertEquals(text.length > 30, true, `${p}/${lang} is too short`);
    }
  }
});
