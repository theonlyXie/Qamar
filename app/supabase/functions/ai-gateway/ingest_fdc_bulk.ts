// Bulk import of USDA FoodData Central.
//
// ingest_usda.ts searches the API one food at a time and was built for a
// curated catalogue of 131 Egyptian dishes. This is the other half: the whole
// generic food world, loaded from the published CSV exports.
//
//   Foundation      ~350 foods, the deepest nutrient detail USDA has
//   SR Legacy     ~7,800 generic foods — every raw and basic cooked item
//   Survey/FNDDS  ~7,000 *prepared* dishes: burgers, pizza, fried chicken,
//                        the things a keyword list and a raw-ingredient table
//                        both miss entirely
//
// Usage (the workflow does the download and unzip):
//   deno run --allow-read --allow-net --allow-env ingest_fdc_bulk.ts <dir> <data_type>
//
// Deliberately NOT the Branded dataset. That is 422 MB and about two million
// supermarket products, nearly all American, and loading it would put two
// million aliases in front of a resolver whose whole job is to know that
// كشري means koshary. Branded food belongs behind a barcode lookup, where the
// user has told us exactly which product they mean.

// Read lazily rather than at module load: importing this file to test the
// parser must not require --allow-env, and a module that reads the
// environment just by being imported is awkward to reuse anywhere.
const env = (k: string) => Deno.env.get(k);

/** USDA nutrient ids to Qamar codes. Anything unlisted is ignored. */
const NUTRIENT_MAP: Record<string, string> = {
  "1008": "energy_kcal",
  "1003": "protein_g",
  "1005": "carbs_g",
  "1004": "fat_g",
  "1079": "fiber_g",
  "2000": "sugars_g",
  "1258": "sat_fat_g",
  "1093": "sodium_mg",
  "1092": "potassium_mg",
  "1087": "calcium_mg",
  "1089": "iron_mg",
  "1090": "magnesium_mg",
  "1095": "zinc_mg",
  "1103": "selenium_ug",
  "1100": "iodine_ug",
  "1106": "vitamin_a_ug",
  "1162": "vitamin_c_mg",
  "1114": "vitamin_d_ug",
  "1109": "vitamin_e_mg",
  "1165": "thiamin_mg",
  "1166": "riboflavin_mg",
  "1167": "niacin_mg",
  "1175": "vitamin_b6_mg",
  "1177": "folate_ug",
  "1190": "folate_ug", // DFE — preferred, see PREFERRED below
  "1178": "vitamin_b12_ug",
  "1051": "water_g",
};

/** Where two USDA ids map to one code, this one wins. */
const PREFERRED = new Set(["1190"]);

const NUTRIENT_SET_VERSION = "fdc-bulk-2026-08";

/**
 * How much a bulk-imported food is trusted against the curated catalogue.
 *
 * Lower than anything hand-written. The resolver breaks ties on source_rank,
 * so an imported "Rice, white, cooked" must never outrank the Egyptian رز that
 * somebody chose the aliases for. Fifteen thousand new foods are only an
 * improvement if they lose every argument with the hundred and thirty-one.
 */
const BULK_SOURCE_RANK = 10;
const CURATED_MIN_RANK = 50;

interface FoodRow {
  fdcId: string;
  description: string;
  category: string | null;
}

// ---- CSV -----------------------------------------------------------------

/**
 * A single CSV record, honouring quotes and embedded commas.
 *
 * USDA descriptions are full of commas ("Beef, ground, 80% lean meat / 20%
 * fat, raw"), so a split(",") loses the food's name on the first field.
 */
function parseCsvLine(line: string): string[] {
  const out: string[] = [];
  let cur = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quoted) {
      if (c === '"') {
        if (line[i + 1] === '"') { cur += '"'; i++; } else quoted = false;
      } else cur += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { out.push(cur); cur = ""; }
    else cur += c;
  }
  out.push(cur);
  return out;
}

/**
 * Streams a CSV file a row at a time.
 *
 * food_nutrient.csv for SR Legacy is around 700,000 rows. Reading it into an
 * array first is the difference between this running in a CI job and being
 * killed by the runner.
 */
async function* csvRows(path: string): AsyncGenerator<Record<string, string>> {
  const file = await Deno.open(path, { read: true });
  const decoder = new TextDecoderStream();
  const lines = file.readable.pipeThrough(decoder);
  let header: string[] | null = null;
  let carry = "";

  for await (const chunk of lines) {
    const parts = (carry + chunk).split("\n");
    carry = parts.pop() ?? "";
    for (const raw of parts) {
      const line = raw.replace(/\r$/, "");
      if (!line.trim()) continue;
      const cells = parseCsvLine(line);
      if (!header) { header = cells.map((h) => h.replace(/"/g, "").trim()); continue; }
      const row: Record<string, string> = {};
      header.forEach((h, i) => row[h] = cells[i] ?? "");
      yield row;
    }
  }
  if (carry.trim() && header) {
    const cells = parseCsvLine(carry.replace(/\r$/, ""));
    const row: Record<string, string> = {};
    header.forEach((h, i) => row[h] = cells[i] ?? "");
    yield row;
  }
}

// ---- naming --------------------------------------------------------------

/** A stable, unique, readable key for a USDA food. */
function slugFor(fdcId: string, description: string): string {
  const base = description
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 48);
  return `fdc_${base || "food"}_${fdcId}`;
}

/**
 * The searchable name.
 *
 * USDA writes "Beef, ground, 80% lean meat / 20% fat, raw", which nobody
 * types. The first comma-separated part is almost always the food itself, so
 * it becomes a second alias and gives the resolver something a person would
 * actually write.
 */
function aliasesFor(description: string): string[] {
  const full = description.trim();
  const head = full.split(",")[0].trim();
  const set = new Set<string>([full.toLowerCase()]);
  if (head.length > 2 && head.length < full.length) set.add(head.toLowerCase());
  return [...set];
}

// ---- database ------------------------------------------------------------

async function db(path: string, init: RequestInit = {}): Promise<Response> {
  const key = env("SUPABASE_SERVICE_ROLE_KEY")!;
  const res = await fetch(`${env("SUPABASE_URL")}/rest/v1/${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      apikey: key,
      Authorization: `Bearer ${key}`,
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) throw new Error(`${path}: ${res.status} ${(await res.text()).slice(0, 300)}`);
  return res;
}

async function upsert(table: string, conflict: string, rows: unknown[]): Promise<void> {
  for (let i = 0; i < rows.length; i += 500) {
    await db(`${table}?on_conflict=${conflict}`, {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify(rows.slice(i, i + 500)),
    });
  }
}

// ---- run -----------------------------------------------------------------

async function main() {
  const dir = Deno.args[0];
  const dataType = Deno.args[1] ?? "sr_legacy";
  if (!env("SUPABASE_URL") || !env("SUPABASE_SERVICE_ROLE_KEY")) {
    console.error("set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY");
    Deno.exit(1);
  }
  if (!dir) {
    console.error("usage: ingest_fdc_bulk.ts <unzipped-csv-dir> [data_type]");
    Deno.exit(1);
  }

  // Which foods this export contains, and what they are called.
  console.log(`reading ${dir}/food.csv`);
  const foods = new Map<string, FoodRow>();
  for await (const r of csvRows(`${dir}/food.csv`)) {
    const id = r.fdc_id?.trim();
    const desc = (r.description ?? "").trim();
    if (!id || !desc) continue;
    foods.set(id, { fdcId: id, description: desc, category: r.food_category_id || null });
  }
  console.log(`  ${foods.size} foods`);

  // Which of them are already here, so a re-run is an update and not a
  // duplicate catalogue.
  const existing = new Map<string, string>();
  let from = 0;
  for (;;) {
    const res = await db(
      `foods?select=qamar_food_id,slug&slug=like.fdc_*&limit=1000&offset=${from}`,
    );
    const page = await res.json() as { qamar_food_id: string; slug: string }[];
    page.forEach((f) => existing.set(f.slug, f.qamar_food_id));
    if (page.length < 1000) break;
    from += 1000;
  }
  console.log(`  ${existing.size} already imported`);

  // Insert the foods that are new. Everything imported is marked unreviewed
  // and low-ranked: it is a reference table, not a curated catalogue.
  const newFoods = [...foods.values()].filter((f) => !existing.has(slugFor(f.fdcId, f.description)));
  console.log(`  ${newFoods.length} to insert`);
  for (let i = 0; i < newFoods.length; i += 500) {
    const batch = newFoods.slice(i, i + 500).map((f) => ({
      slug: slugFor(f.fdcId, f.description),
      name_en: f.description,
      name_ar: null,
      name_eg: null,
      food_state: "unspecified",
      is_recipe: false,
      source_rank: BULK_SOURCE_RANK,
      confidence: 0.8,
      human_reviewed: false,
    }));
    const res = await db("foods?on_conflict=slug", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=representation" },
      body: JSON.stringify(batch),
    });
    for (const row of await res.json() as { qamar_food_id: string; slug: string }[]) {
      existing.set(row.slug, row.qamar_food_id);
    }
    if (i % 2500 === 0) console.log(`  inserted ${i + batch.length}/${newFoods.length}`);
  }

  // Aliases. Low priority so a curated Egyptian alias always wins a tie.
  const aliasRows: unknown[] = [];
  for (const f of foods.values()) {
    const id = existing.get(slugFor(f.fdcId, f.description));
    if (!id) continue;
    for (const a of aliasesFor(f.description)) {
      aliasRows.push({ qamar_food_id: id, alias: a, lang: "en", priority: BULK_SOURCE_RANK });
    }
  }
  console.log(`  ${aliasRows.length} aliases`);
  await upsert("food_aliases", "qamar_food_id,alias,lang", aliasRows);

  // Nutrients, streamed. One food's rows are flushed as soon as the next
  // food's begin, so memory stays flat across 700,000 rows.
  console.log(`reading ${dir}/food_nutrient.csv`);
  let pending: Record<string, { amount: number; preferred: boolean }> = {};
  let currentFdc = "";
  let written = 0;
  const buffer: unknown[] = [];

  const flush = async (force = false) => {
    if (buffer.length >= 1000 || (force && buffer.length > 0)) {
      await upsert("food_nutrients", "qamar_food_id,nutrient_code,per_basis", buffer.splice(0));
    }
  };

  const emit = (fdc: string) => {
    const food = foods.get(fdc);
    if (!food) return;
    const id = existing.get(slugFor(fdc, food.description));
    if (!id) return;
    for (const [code, v] of Object.entries(pending)) {
      buffer.push({
        qamar_food_id: id,
        nutrient_code: code,
        amount: v.amount,
        per_basis: "per_100g",
        source_id: "usda_fdc",
        nutrient_definition_version: NUTRIENT_SET_VERSION,
        confidence: 0.9,
      });
      written++;
    }
  };

  for await (const r of csvRows(`${dir}/food_nutrient.csv`)) {
    const fdc = r.fdc_id?.trim();
    if (!fdc) continue;
    if (fdc !== currentFdc) {
      if (currentFdc) emit(currentFdc);
      await flush();
      pending = {};
      currentFdc = fdc;
    }
    const code = NUTRIENT_MAP[r.nutrient_id?.trim()];
    if (!code) continue;
    const amount = Number(r.amount);
    if (!Number.isFinite(amount)) continue;
    const preferred = PREFERRED.has(r.nutrient_id.trim());
    const seen = pending[code];
    // A preferred id overwrites; a non-preferred one never overwrites it.
    if (!seen || (preferred && !seen.preferred)) pending[code] = { amount, preferred };
  }
  if (currentFdc) emit(currentFdc);
  await flush(true);

  console.log(`\ndone — ${newFoods.length} new foods, ${written} nutrient rows (${dataType})`);
  console.log("imported foods are unreviewed and rank below the curated catalogue.");
  console.log(`curated foods keep source_rank >= ${CURATED_MIN_RANK}; these are ${BULK_SOURCE_RANK}.`);
}

if (import.meta.main) await main();

export { aliasesFor, parseCsvLine, slugFor };
