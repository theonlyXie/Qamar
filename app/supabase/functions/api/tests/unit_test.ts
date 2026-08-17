import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { calculateTarget } from "../_shared/targets.ts";
import { parsePath } from "../_shared/util.ts";

Deno.test("calculateTarget lose goal subtracts ~500 from TDEE", () => {
  const result = calculateTarget({
    birth_date: "1990-01-15",
    gender: "male",
    height_cm: 175,
    weight_kg: 80,
    activity_factor: 1.55,
    goal: "lose",
  });
  assertEquals(result.formula_version, "calc v2.0");
  assertEquals(result.kcal < result.tdee, true);
  assertEquals(result.protein_g, Math.round(80 * 1.6));
});

Deno.test("parsePath strips function prefix", () => {
  const a = parsePath(new URL("https://x.supabase.co/functions/v1/api/bootstrap"));
  assertEquals(a.route, "/bootstrap");
  assertEquals(a.parts, ["bootstrap"]);

  const b = parsePath(new URL("https://x.supabase.co/functions/v1/api/meal-drafts/abc/confirm"));
  assertEquals(b.route, "/meal-drafts/abc/confirm");
  assertEquals(b.parts[0], "meal-drafts");
  assertEquals(b.parts[2], "confirm");
});
