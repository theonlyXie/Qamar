import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { notYetEarnedMessage } from "./earned.ts";

Deno.test("the refusal states the database's numbers, not a constant", () => {
  assertEquals(
    notYetEarnedMessage({ needed: 20, window_days: 30, logged_days: 12 }),
    "Not earned yet: 20 logged days in the first 30 are needed. So far: 12.",
  );
  // Tuned by the operator: the sentence follows without a release.
  assertStringIncludes(notYetEarnedMessage({ needed: 24, window_days: 30 }), "24 logged days in the first 30");
});

Deno.test("an unreadable status still gives a true sentence at the launch rule", () => {
  assertEquals(notYetEarnedMessage(null), "Not earned yet: 20 logged days in the first 30 are needed.");
  assertEquals(notYetEarnedMessage({ needed: "x", window_days: -3 }), "Not earned yet: 20 logged days in the first 30 are needed.");
});
