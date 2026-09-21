import { assert, assertEquals } from "jsr:@std/assert@1";
import { chatSystemPrompt, dayShape, isFasting, planSystemPrompt, slotEnum, type UserContext } from "./model.ts";

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

Deno.test("a photo in the conversation is read as a menu; a plain question is not", () => {
  const withPhoto = chatSystemPrompt(base, [], "(no food data)", "", { photo: true });
  assert(withPhoto.includes("THE PHOTO"));
  assert(withPhoto.includes("plan_update stays null unless they say they ate it"));
  assert(withPhoto.includes("(no guidance retrieved)"), "an empty retrieval does not stop a menu reading");
  const plain = chatSystemPrompt(base, [], "(no food data)", "");
  assert(!plain.includes("THE PHOTO"));
});
