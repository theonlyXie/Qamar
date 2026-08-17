import { assertEquals } from "jsr:@std/assert@1";
import { cairoYmd, entitlementIsActive, isCairoToday, plusRequiredBody } from "./plus.ts";

Deno.test("Cairo ymd is ISO and stable for a fixed instant", () => {
  const d = new Date("2026-08-17T22:00:00Z");
  assertEquals(cairoYmd(d), "2026-08-18");
  assertEquals(isCairoToday("2026-08-18", d), true);
  assertEquals(isCairoToday("2026-08-17", d), false);
});

Deno.test("entitlement fails closed", () => {
  const now = new Date("2026-08-17T12:00:00Z");
  assertEquals(entitlementIsActive(null, now), false);
  assertEquals(entitlementIsActive({ status: "active" }, now), false);
  assertEquals(entitlementIsActive({ status: "expired", period_end: "2027-01-01T00:00:00Z" }, now), false);
  assertEquals(entitlementIsActive({ status: "active", period_end: "2026-08-16T00:00:00Z" }, now), false);
  assertEquals(entitlementIsActive({ status: "active", period_end: "2026-08-18T00:00:00Z" }, now), true);
});

Deno.test("plus refusal names the feature and does not sell Su", () => {
  const body = plusRequiredBody("en", "meal_photo");
  assertEquals(body.reason, "plus_required");
  assertEquals(body.feature, "meal_photo");
  assertEquals(body.error.toLowerCase().includes("qamar+"), true);
  assertEquals(body.error.toLowerCase().includes("su point"), false);
});
