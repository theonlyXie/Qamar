// Pure arithmetic over graph resolutions. No database.
// Run: deno test graph_test.ts

import { assertEquals } from "jsr:@std/assert@1";
import {
  itemsFromResolutions,
  type GraphCandidate,
  type Resolution,
  type ResolvedPortion,
} from "./graph.ts";

const food = (over: Partial<GraphCandidate> = {}): GraphCandidate => ({
  qamarFoodId: "f1",
  slug: "koshary",
  nameEn: "Koshary",
  nameAr: "كشري",
  nameEg: "كشري",
  isRecipe: true,
  matchScore: 1,
  matchedAlias: "كشري",
  matchKind: "exact",
  hasNutrients: true,
  phraseCoverage: 1,
  ...over,
});

const portion = (over: Partial<ResolvedPortion> = {}): ResolvedPortion => ({
  labelEn: "1 medium bowl",
  labelAr: "طبق وسط",
  grams: 400,
  basis: "household",
  confidence: 0.9,
  matchedInPhrase: true,
  ...over,
});

const resolution = (over: Partial<Resolution>): Resolution => ({
  phrase: "كشري",
  food: food(),
  alternatives: [],
  portion: portion(),
  facts: {
    name: "Koshary",
    per100g: { kcal: 130, protein: 4, carbs: 24, fat: 2 },
    source: "Qamar graph",
    url: null,
  },
  origin: "graph",
  needsConfirmation: false,
  uncertainty: [],
  ...over,
});

Deno.test("scales per-100 g facts by the resolved portion", () => {
  const items = itemsFromResolutions([resolution({ portion: portion({ grams: 400 }) })]);
  assertEquals(items.length, 1);
  assertEquals(items[0].kcal, 520);
  assertEquals(items[0].proteinG, 16);
  assertEquals(items[0].carbsG, 96);
  assertEquals(items[0].fatG, 8);
  assertEquals(items[0].en, "Koshary");
  assertEquals(items[0].ar, "كشري");
  assertEquals(items[0].portionEn, "1 medium bowl");
  assertEquals(items[0].confidence, "high");
});

Deno.test("drops unresolved phrases instead of inventing a plate", () => {
  assertEquals(
    itemsFromResolutions([
      resolution({
        phrase: "حاجة غريبة",
        food: null,
        portion: null,
        facts: null,
        origin: "unresolved",
        needsConfirmation: true,
      }),
    ]),
    [],
  );
});

Deno.test("assumes 100 g when no portion was named, and marks it uncertain", () => {
  const items = itemsFromResolutions([
    resolution({
      phrase: "فول",
      food: food({ slug: "foul", nameEn: "Foul", nameAr: "فول", nameEg: "فول" }),
      portion: null,
      facts: {
        name: "Foul",
        per100g: { kcal: 110, protein: 7, carbs: 18, fat: 1 },
        source: "Qamar graph",
        url: null,
      },
      origin: "graph",
      needsConfirmation: true,
      uncertainty: ["portion assumed: 100 g"],
    }),
  ]);
  assertEquals(items.length, 1);
  assertEquals(items[0].kcal, 110);
  assertEquals(items[0].proteinG, 7);
  assertEquals(items[0].portionEn, "100 g");
  assertEquals(items[0].confidence, "low");
});
