// The conversation Qamar is allowed to remember.
//
// The bug these pin: the gateway judged every message on its own, so "and I
// got" — somebody continuing a sentence about the meal they had just typed —
// was scored as a fragment about nothing and refused as off-topic. That
// refusal is in the live database, alongside "ازيك" and "أنا تعبان النهاردة".

import { assertEquals } from "jsr:@std/assert@1";
import { conversationMessages, type Turn } from "./model.ts";

Deno.test("no history is the old behaviour: one user message", () => {
  const m = conversationMessages(undefined, "how much protein?");
  assertEquals(m.length, 1);
  assertEquals(m[0].role, "user");
});

Deno.test("history comes before the new message, oldest first", () => {
  const history: Turn[] = [
    { user: "kasam", assistant: "[read the meal and offered the items to confirm]" },
    { user: "and I got", assistant: "Got what? Tell me and I will add it." },
  ];
  const m = conversationMessages(history, "chips too");

  assertEquals(m.map((x) => x.role), [
    "user",
    "assistant",
    "user",
    "assistant",
    "user",
  ]);
  assertEquals(m[0].content, "kasam");
  assertEquals(m[4].content, "chips too");
});

Deno.test("roles alternate, which is what the API requires", () => {
  const history: Turn[] = [
    { user: "a", assistant: "b" },
    { user: "c", assistant: "d" },
    { user: "e", assistant: "f" },
  ];
  const m = conversationMessages(history, "g", "{");
  for (let i = 1; i < m.length; i++) {
    if (m[i].role === m[i - 1].role) {
      throw new Error(`two ${m[i].role} messages in a row at ${i}`);
    }
  }
});

Deno.test("a turn where one side said nothing is dropped, not padded", () => {
  // An empty content block is rejected outright by the API, and inventing
  // filler to keep the alternation would put words in somebody's mouth.
  const history: Turn[] = [
    { user: "ازيك", assistant: "" },
    { user: "   ", assistant: "still here" },
    { user: "how much protein?", assistant: "Depends on your weight." },
  ];
  const m = conversationMessages(history, "and for fat?");
  assertEquals(m.length, 3);
  assertEquals(m[0].content, "how much protein?");
  assertEquals(m[2].content, "and for fat?");
});

Deno.test("the prefill stays last, after the new message", () => {
  const m = conversationMessages(
    [{ user: "a", assistant: "b" }],
    "c",
    "{",
  );
  assertEquals(m[m.length - 1].role, "assistant");
  assertEquals(m[m.length - 1].content, "{");
  assertEquals(m[m.length - 2].content, "c");
});

Deno.test("an image message survives being wrapped in history", () => {
  // The current message is a content array for vision calls, and history must
  // not flatten or reorder it.
  const content = [
    { type: "image", source: { type: "base64", media_type: "image/jpeg", data: "x" } },
    { type: "text", text: "Read this panel." },
  ];
  const m = conversationMessages([{ user: "a", assistant: "b" }], content);
  assertEquals(m[2].content, content);
});
