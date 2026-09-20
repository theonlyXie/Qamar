import { assert, assertEquals } from "jsr:@std/assert@1";
import { dayShape, isFasting, planSystemPrompt, slotEnum, type UserContext } from "./model.ts";

const base: UserContext = { age: 30, gender: "male", targetKcal: 2000, lang: "ar" };

Deno.test("a fasting month changes the day's shape, not its energy", () => {
  const fasting: UserContext = { ...base, fasting: "ramadan" };
  assert(!isFasting(base));
  assert(isFasting(fasting));
  assertEquals(slotEnum(base), "breakfast|lunch|dinner");
  assertEquals(slotEnum(fasting), "iftar|snack|suhoor");
  assert(dayShape(fasting).includes("within 5% of the daily target"), "the fast does not change the target");
  assert(dayShape(base).includes("breakfast, lunch and dinner"));
});

Deno.test("the plan prompt asks for iftar and suhoor while fasting, three meals otherwise", () => {
  const p = planSystemPrompt({ ...base, fasting: "ramadan" }, [], "(no food data)");
  assert(p.includes('"slot": "iftar|snack|suhoor"'));
  assert(p.includes("fasting Ramadan"));
  assert(p.includes("suhoor"));
  const q = planSystemPrompt(base, [], "(no food data)");
  assert(q.includes('"slot": "breakfast|lunch|dinner"'));
  assert(!q.includes("fasting Ramadan"));
});
