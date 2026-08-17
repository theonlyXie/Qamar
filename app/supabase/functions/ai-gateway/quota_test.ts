// Run: deno test quota_test.ts

import { assertEquals } from "jsr:@std/assert@1";
import { asQuota, quotaExceededMessage, quotaPayload } from "./quota.ts";

Deno.test("reads a consume result and ignores junk", () => {
  const q = asQuota({ allowed: true, used: 3, limit: 5, extra: 0, remaining: 2, day: "2026-08-17" });
  assertEquals(q?.remaining, 2);
  assertEquals(asQuota({ used: "nope" }), null);
  assertEquals(asQuota(null), null);
});

Deno.test("the exhausted copy tells them to earn Su, not to pay cash", () => {
  const en = quotaExceededMessage("en");
  const ar = quotaExceededMessage("ar");
  assertEquals(en.includes("Su Points"), true);
  assertEquals(en.toLowerCase().includes("subscribe") || en.toLowerCase().includes("unlimited"), false);
  assertEquals(ar.includes("Su"), true);
});

Deno.test("the payload the app parses is just the counters", () => {
  assertEquals(quotaPayload({ allowed: true, used: 1, limit: 5, extra: 2, remaining: 6 }), {
    used: 1,
    limit: 5,
    extra: 2,
    remaining: 6,
  });
});
