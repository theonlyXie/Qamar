// Run: deno test quota_test.ts

import { assertEquals } from "jsr:@std/assert@1";
import { asQuota, quotaExceededMessage, quotaPayload } from "./quota.ts";

Deno.test("reads a consume result, keeps its bucket, and ignores junk", () => {
  const q = asQuota({ bucket: "photo", allowed: true, used: 2, limit: 3, extra: 1, remaining: 2, day: "2026-09-20", plus: false });
  assertEquals(q?.bucket, "photo");
  assertEquals(q?.remaining, 2);
  assertEquals(q?.plus, false);
  assertEquals(asQuota({ used: 1, limit: 3, remaining: 2 })?.bucket, "chat");
  assertEquals(asQuota({ used: 1, limit: 3, remaining: 2 }, "plan")?.bucket, "plan");
  assertEquals(asQuota({ used: "nope" }), null);
  assertEquals(asQuota(null), null);
});

Deno.test("each wall names its own way out", () => {
  const photo = quotaExceededMessage("en", "photo");
  assertEquals(photo.includes("Su Points"), true);
  assertEquals(photo.toLowerCase().includes("qamar+"), false);

  const chat = quotaExceededMessage("en", "chat");
  assertEquals(chat.includes("Qamar+"), true);
  assertEquals(chat.includes("last free question"), true);
  assertEquals(chat.includes("what to eat tomorrow"), true, "the wall leads with what Qamar+ is for");
  // The words name Qamar+ only. The question bought with Su (O13, 0066) is a
  // button under the wall, offered only when the balance covers it, so the
  // message itself never promises it to someone who cannot afford it.
  assertEquals(chat.includes("Su Points"), false, "the wall's words never promise the Su question");

  for (const b of ["photo", "chat", "plan"] as const) {
    assertEquals(quotaExceededMessage("ar", b).length > 20, true);
  }
});

Deno.test("the payload the app parses is the bucket and its counters", () => {
  assertEquals(quotaPayload({ bucket: "chat", allowed: true, used: 1, limit: 3, extra: 0, remaining: 2 }), {
    bucket: "chat",
    used: 1,
    limit: 3,
    extra: 0,
    remaining: 2,
  });
  assertEquals(
    quotaPayload({ bucket: "photo", allowed: false, used: 3, limit: 3, extra: 0, remaining: 0, plus: true }).plus,
    true,
  );
});

Deno.test("the wall states no limit of its own, and never sells Qamar+ to a member", () => {
  // The limits are configuration (ai_quota_config): a number in the words
  // would go false the day they are tuned.
  for (const lang of ["ar", "en"] as const) {
    for (const b of ["photo", "chat", "plan"] as const) {
      for (const plus of [false, true]) {
        const m = quotaExceededMessage(lang, b, plus);
        assertEquals(/\b(three|third|3|50|30)\b|تلات|تالت|[٠-٩]/.test(m), false, `${lang} ${b} ${plus}: ${m}`);
      }
    }
  }
  const member = quotaExceededMessage("en", "chat", true);
  assertEquals(member.includes("Qamar+"), false, "a member already has it");
  assertEquals(quotaExceededMessage("ar", "chat", true).includes("قمر+"), false);
  // Arabic writes the brand in Arabic: a Latin "Qamar+" opening an RTL line
  // is drawn "+Qamar".
  assertEquals(quotaExceededMessage("ar", "chat").includes("Qamar+"), false);
  assertEquals(quotaExceededMessage("ar", "chat").includes("قمر+"), true);
});

