// The pure parts of the bulk import. Run: deno test ingest_fdc_bulk_test.ts
//
// The risk in a bulk importer is not the network, it is silently mangling
// fifteen thousand names on the way in. USDA descriptions are written with
// commas in them, so the CSV parser is the whole ballgame.

import { assertEquals } from "jsr:@std/assert@1";
import { aliasesFor, parseCsvLine, slugFor } from "./ingest_fdc_bulk.ts";

Deno.test("a quoted field keeps its commas", () => {
  // The actual shape of a USDA row. split(",") would return "Beef" as the
  // description and shift every later column by four.
  assertEquals(
    parseCsvLine('"1234","Beef, ground, 80% lean meat / 20% fat, raw","13"'),
    ["1234", "Beef, ground, 80% lean meat / 20% fat, raw", "13"],
  );
});

Deno.test("an escaped quote inside a field survives", () => {
  assertEquals(
    parseCsvLine('"9","Cheese, ""cheddar"", sharp","1"'),
    ["9", 'Cheese, "cheddar", sharp', "1"],
  );
});

Deno.test("unquoted fields and empty cells", () => {
  assertEquals(parseCsvLine("1,2,,4"), ["1", "2", "", "4"]);
  assertEquals(parseCsvLine(""), [""]);
});

Deno.test("a slug is unique, readable and stable", () => {
  const a = slugFor("173944", "Beef, ground, 80% lean meat / 20% fat, raw");
  assertEquals(a, "fdc_beef_ground_80_lean_meat_20_fat_raw_173944");
  // Same input, same slug — a re-run must update rather than duplicate.
  assertEquals(a, slugFor("173944", "Beef, ground, 80% lean meat / 20% fat, raw"));
  // Two foods whose names truncate to the same prefix stay distinct, because
  // the fdc id is on the end rather than the front.
  const long = "A".repeat(80);
  assertEquals(slugFor("1", long) === slugFor("2", long), false);
});

Deno.test("the head of a USDA description becomes a searchable alias", () => {
  // Nobody types the full string. "beef" is what they type.
  assertEquals(
    aliasesFor("Beef, ground, 80% lean meat / 20% fat, raw"),
    ["beef, ground, 80% lean meat / 20% fat, raw", "beef"],
  );
});

Deno.test("a description with no comma yields one alias, not two identical ones", () => {
  assertEquals(aliasesFor("Cheeseburger"), ["cheeseburger"]);
});

Deno.test("a very short head is not worth an alias of its own", () => {
  // "Eg" would match almost anything on trigrams.
  assertEquals(aliasesFor("Eg, something else entirely"), [
    "eg, something else entirely",
  ]);
});
