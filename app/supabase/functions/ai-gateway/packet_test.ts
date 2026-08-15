// Tests for the parts of the evidence packet that are pure functions.
// Run: deno test packet_test.ts
//
// The writes themselves need a database and are verified against the live
// project. What is worth testing here is the extraction: a claim the packet
// fails to record cannot be verified later, and a claim it records wrongly is
// worse than none, because something downstream will check the wrong number.

import { assertEquals } from "jsr:@std/assert@1";
import {
  externalCallsIn,
  numericClaims,
  resolutionUncertainty,
  targetsFrom,
} from "./packet.ts";
import type { Resolution } from "./graph.ts";
import type { UserContext } from "./model.ts";

interface Claim {
  claim: string;
  value: number;
  unit: string;
}

const claims = (t: string) => numericClaims(t) as Claim[];
const units = (t: string) => claims(t).map((c) => `${c.value}${c.unit}`);

Deno.test("records the quantities an English answer asserted", () => {
  assertEquals(
    units("A plate of koshary is about 520 kcal, with 15 g protein and 90 g carbs."),
    ["520kcal", "15g", "90g"],
  );
});

Deno.test("records them in Arabic too, including Arabic-Indic digits", () => {
  // The app's primary language. If this ever regresses, the packet quietly
  // stops recording claims for most of the traffic.
  assertEquals(units("طبق الكشري فيه حوالي ٥٢٠ سعرة و ١٥ جرام بروتين."), ["520سعرة", "15جرام"]);
  assertEquals(units("الرغيف فيه 250 سعرة"), ["250سعرة"]);
});

Deno.test("does not read a unit out of an ordinary word", () => {
  // "500 great" is not 500 grams, and a claim invented here would be checked
  // against nothing and fail for no reason.
  assertEquals(claims("I walked 500 great steps"), []);
  assertEquals(claims("that was 10 kilometres away"), []);
});

Deno.test("prefers the longer unit when one contains another", () => {
  assertEquals(units("about 30 grams of protein"), ["30grams"]);
  assertEquals(units("roughly 1.5 kilograms this month"), ["1.5kilograms"]);
});

Deno.test("keeps decimals and percentages", () => {
  assertEquals(units("that is 12.5 g of fat, around 20% of the day"), ["12.5g", "20%"]);
});

Deno.test("says the same claim once", () => {
  assertEquals(units("200 kcal at breakfast and 200 kcal at lunch"), ["200kcal"]);
});

Deno.test("finds nothing to verify in an answer that asserts nothing", () => {
  assertEquals(claims("Yes, that is a reasonable breakfast."), []);
  assertEquals(claims(""), []);
});

// ---- resolutions --------------------------------------------------------

function resolution(over: Partial<Resolution>): Resolution {
  return {
    phrase: "فول",
    food: null,
    alternatives: [],
    portion: null,
    facts: null,
    origin: "graph",
    needsConfirmation: false,
    uncertainty: [],
    ...over,
  };
}

Deno.test("counts an external lookup whether or not it answered", () => {
  // Both cost a call. Counting only the successes would report the food
  // resolver as comfortably inside a budget it is actually exceeding.
  assertEquals(
    externalCallsIn([
      resolution({ origin: "graph" }),
      resolution({ origin: "graph_derived" }),
      resolution({ origin: "external" }),
      resolution({ origin: "unresolved" }),
    ]),
    2,
  );
});

Deno.test("carries every reason the resolver was unsure, keyed by phrase", () => {
  assertEquals(
    resolutionUncertainty([
      resolution({ phrase: "عيش", uncertainty: ["portion assumed: loaf"] }),
      resolution({ phrase: "فول", uncertainty: [] }),
      resolution({ phrase: "حاجة غريبة", origin: "unresolved", uncertainty: [] }),
    ]),
    {
      "عيش": ["portion assumed: loaf"],
      "حاجة غريبة": ["no food matched"],
    },
  );
});

// ---- targets ------------------------------------------------------------

const user = (over: Partial<UserContext> = {}): UserContext => ({ lang: "ar", ...over });

Deno.test("records the target, and never invents an equation for it", () => {
  const [t] = targetsFrom(user({ targetKcal: 2100 })) as {
    metric: string;
    value: number;
    equation_version: null;
  }[];
  assertEquals(t.metric, "energy_kcal");
  assertEquals(t.value, 2100);
  // The requirement engine does not exist yet. Naming an equation the target
  // did not come from would be a fabricated citation in an audit record.
  assertEquals(t.equation_version, null);
});

Deno.test("records no target when there is none", () => {
  assertEquals(targetsFrom(user()), []);
});
