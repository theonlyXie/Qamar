import { assertEquals } from "jsr:@std/assert@1";
import {
  barcodeProductFromOff,
  itemsFromBarcode,
  scalePer100g,
  servingGramsFromOff,
} from "./retrieval.ts";

Deno.test("serving grams prefer serving_quantity, then a grams token, else 100", () => {
  assertEquals(servingGramsFromOff({ serving_quantity: 30 }), 30);
  assertEquals(servingGramsFromOff({ serving_size: "45 g (1 bar)" }), 45);
  assertEquals(servingGramsFromOff({}), 100);
  assertEquals(servingGramsFromOff({ serving_quantity: 9000 }), 100);
});

Deno.test("per-100 g scales by the serving", () => {
  assertEquals(
    scalePer100g({ kcal: 400, protein: 10, carbs: 40, fat: 20 }, 50),
    { kcal: 200, protein: 5, carbs: 20, fat: 10 },
  );
});

Deno.test("a missing or empty OFF product is not a meal", () => {
  assertEquals(barcodeProductFromOff({ status: 0 }), null);
  assertEquals(barcodeProductFromOff({ product: { nutriments: {} } }), null);
});

Deno.test("a real OFF payload becomes one confirmable item, no model", () => {
  const product = barcodeProductFromOff({
    status: 1,
    product: {
      code: "6223001870021",
      product_name: "Juhayna milk",
      product_name_ar: "لبن جهينة",
      nutriments: {
        "energy-kcal_100g": 62,
        proteins_100g: 3.2,
        carbohydrates_100g: 4.8,
        fat_100g: 3.5,
      },
      serving_quantity: 200,
    },
  });
  if (!product) throw new Error("expected a product");
  assertEquals(product.servingGrams, 200);
  const items = itemsFromBarcode(product, "ar");
  assertEquals(items.length, 1);
  assertEquals(items[0].kcal, 124);
  assertEquals(items[0].ar, "لبن جهينة");
  assertEquals(items[0].confidence, "high");
  assertEquals(items[0].grams, 200);
});
