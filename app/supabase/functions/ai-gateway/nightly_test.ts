import { assert, assertEquals } from "jsr:@std/assert@1";
import { cairoDatePlus, cairoNow, chunks, dueMembers, isNightlyWindow, MAX_PER_RUN, nightSentence, planKcal } from "./nightly.ts";

Deno.test("Cairo is UTC+3 in summer and UTC+2 in winter", () => {
  // 2026-07-01 19:00Z → 22:00 Cairo (EEST).
  assertEquals(cairoNow(new Date("2026-07-01T19:00:00Z")), { date: "2026-07-01", hour: 22 });
  // 2026-01-15 19:00Z → 21:00 Cairo (EET); 20:00Z → 22:00.
  assertEquals(cairoNow(new Date("2026-01-15T19:00:00Z")).hour, 21);
  assertEquals(cairoNow(new Date("2026-01-15T20:00:00Z")).hour, 22);
});

Deno.test("the window is 22:00 and 23:00 Cairo, whatever UTC says", () => {
  assert(isNightlyWindow(new Date("2026-07-01T19:30:00Z")));
  assert(isNightlyWindow(new Date("2026-07-01T20:30:00Z")));
  assert(!isNightlyWindow(new Date("2026-07-01T18:59:00Z")));
  assert(!isNightlyWindow(new Date("2026-07-01T21:00:00Z")), "00:00 Cairo is a new day");
  assert(isNightlyWindow(new Date("2026-01-15T20:00:00Z")));
  assert(!isNightlyWindow(new Date("2026-01-15T19:00:00Z")), "21:00 Cairo in winter is too early");
});

Deno.test("tomorrow is Cairo's tomorrow, across the UTC midnight", () => {
  // 22:30 Cairo on the 1st is 19:30Z on the 1st: tomorrow is the 2nd.
  assertEquals(cairoDatePlus(new Date("2026-07-01T19:30:00Z"), 1), "2026-07-02");
  // 23:30 Cairo on the 31st is 20:30Z on the 31st: tomorrow is 1 Aug.
  assertEquals(cairoDatePlus(new Date("2026-07-31T20:30:00Z"), 1), "2026-08-01");
  // 00:30 Cairo on 2 Jan is 22:30Z on 1 Jan: today is already the 2nd.
  assertEquals(cairoDatePlus(new Date("2026-01-01T22:30:00Z"), 0), "2026-01-02");
});

Deno.test("members who already have tomorrow's plan are never written a second one", () => {
  assertEquals(dueMembers(["a", "b", "c", "b"], ["b"]), ["a", "c"]);
  assertEquals(dueMembers([], []), []);
});

Deno.test("a run is capped", () => {
  const many = Array.from({ length: MAX_PER_RUN + 50 }, (_, i) => `u${i}`);
  assertEquals(dueMembers(many, []).length, MAX_PER_RUN);
});

Deno.test("plan calories are the portions, not the alternatives", () => {
  const meals = [
    { portions: [{ kcal: 300 }, { kcal: 120 }], alt: { portions: [{ kcal: 900 }] } },
    { portions: [{ kcal: 650.4 }] },
    {},
  ];
  assertEquals(planKcal(meals), 1070);
});

Deno.test("the night sentence compares tomorrow with today and names no dish", () => {
  const lighter = nightSentence({ planKcal: 1800, todayKcal: 2100, meals: 3 });
  assertEquals(lighter.en, "Tomorrow is 14% lighter than today — 1800 kcal over 3 meals.");
  assert(lighter.ar.includes("أخف") && lighter.ar.includes("14٪"));

  const more = nightSentence({ planKcal: 2000, todayKcal: 1500, meals: 3 });
  assert(more.en.startsWith("You were under your target today, so tomorrow is 33% more"));

  const same = nightSentence({ planKcal: 1900, todayKcal: 1850, meals: 3 });
  assert(same.en.startsWith("Tomorrow keeps today's rhythm"));

  const empty = nightSentence({ planKcal: 1900, todayKcal: 0, meals: 3 });
  assert(empty.en.includes("nothing was logged today"), "no division by an empty day");
  for (const s of [lighter, more, same, empty]) {
    assert(!/كشري|فول|رز|koshary|rice/i.test(s.ar + s.en));
  }
});

Deno.test("audiences are chunked for the URL", () => {
  assertEquals(chunks([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  assertEquals(chunks([], 2), []);
});
