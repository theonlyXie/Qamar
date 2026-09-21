# Qamar AI gateway

The app never holds a model key. It calls this with the user's Supabase JWT;
this decides whether the question may be answered at all, gathers evidence,
calls the model, and records what happened.

```
POST /ai-gateway/chat/reply     { message, lang }
POST /ai-gateway/meal/analyze   { inputType, text?, mediaPath?, lang? }
POST /ai-gateway/plan/generate  { date?, lang? }
```

## Deploy

```bash
supabase functions deploy ai-gateway --project-ref <ref>

supabase secrets set ANTHROPIC_API_KEY=sk-ant-...   # required
supabase secrets set VOYAGE_API_KEY=pa-...          # required for retrieval
# supabase secrets set OPENAI_API_KEY=sk-...        # alternative to Voyage
# supabase secrets set USDA_API_KEY=...             # optional, better whole-food data
# supabase secrets set QAMAR_MODEL=claude-sonnet-5  # optional
```

Then point the app at it:

```bash
flutter run --dart-define=AI_GATEWAY_URL=https://<ref>.supabase.co/functions/v1/ai-gateway
```

## The three rules this enforces

**1. Nutrition and training only.** `scope.ts` classifies every question
*before* the model is called, so an out-of-scope question costs nothing and
cannot be argued around by the question itself. It refuses six ways — medical,
disordered eating, pregnancy, minors, off-topic, and attempts to rewrite the
assistant's job — each with real copy in Arabic and English rather than a bare
"I can't". Refusal checks run before the topic match, so "what should I eat
while pregnant" refuses on pregnancy rather than passing as a food question.

**2. Grounded or silent.** The model answers from retrieved passages plus
looked-up food data. If retrieval returns nothing, the endpoint refuses rather
than letting the model answer from memory — that is the rule that stops this
becoming a general chatbot the moment the knowledge base is thin.

**3. Numbers come from databases, not the model.** Food figures are looked up
in USDA FoodData Central and Open Food Facts and handed to the model as
per-100g facts to divide. Anything unresolved is marked low confidence so the
user can see which numbers are measured and which are estimates.

Eligibility is re-checked here too: a blocked or under-18 profile is refused at
the gateway, so calling the API directly does not get around what the app shows.

## The knowledge base is empty until you fill it

`kb_documents` / `kb_chunks` (migration 0005) hold the guidance the assistant
reasons from. **Until they have content, every chat call refuses with
`no_grounding`** — by design, not a bug.

To ingest: chunk each source to roughly 500–800 tokens, embed with the same
model as `EMBEDDING_MODEL` (default `voyage-3`, 1024 dims — it must match
`kb_chunks.embedding`), and insert with the service role. Sensible starting
sources, licence permitting:

| Domain | Source |
|---|---|
| nutrition | WHO healthy-diet guidance, EFSA dietary reference values |
| nutrition | NIH Office of Dietary Supplements fact sheets |
| nutrition | Egyptian food composition tables (for local dishes) |
| training | ACSM physical-activity guidelines, WHO activity guidelines |

Check each licence before storing text verbatim; `kb_documents.licence` is
there to record what you may quote.

## Filling the food graph

`qamar_resolve_food` answers from the local graph first and falls through to an
external API only on a miss. Every food in the graph is therefore one fewer
paid lookup, one less round trip, and one more number the user sees as measured
rather than estimated. There are four loaders, and the GitHub Action **Load
Qamar's data** runs any of them from a dropdown.

| Script | What it does | Adds rows to |
|---|---|---|
| `ingest.ts` | Embeds the knowledge base | `kb_documents`, `kb_chunks` |
| `ingest_usda.ts` | Finds a USDA match for each of the 131 authored Egyptian foods | `food_nutrients` |
| `catalog_usda.ts` | Imports USDA's own catalogue as new foods | `foods` and everything hanging off it |
| `catalog_off.ts` | Imports packaged products from Open Food Facts | same |

Run `ingest_usda.ts` before `catalog_usda.ts`. Both write USDA data, and the
first maps fdcIds onto the hand-authored Egyptian foods; the catalogue importer
then recognises those ids and refreshes their numbers instead of creating a
second, worse row for the same food.

```bash
# ~15,000 generic foods: Foundation, SR Legacy and Survey/FNDDS.
deno run --allow-net --allow-env catalog_usda.ts

# Egyptian packaged products. No API key needed.
deno run --allow-net --allow-env --allow-read catalog_off.ts --countries=egypt

# All of Open Food Facts, from the ODbL export. The search API stops paging at
# ten thousand results; this does not.
curl -O https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz
deno run --allow-net --allow-env --allow-read catalog_off.ts --jsonl=openfoodfacts-products.jsonl.gz
```

Both take `--limit=N`, `--batch=N` and `--dry-run`. Both resume: a rate limit
at request 1,001 leaves a third of a catalogue and re-running picks up where it
stopped, because "done" is read from the database rather than kept in the
process. `select * from food_catalog_coverage` reports what landed, per source.

### What the importers will not do

**Nothing the registry has not cleared.** Every loader calls
`assertStorageAllowed` against `source_registry` before its first write. USDA
is public domain and Open Food Facts is ODbL; everything else in that table is
`blocked` or not yet cleared, and FatSecret is blocked specifically because its
terms forbid using the API to give dietary advice, which is the product. The
registry row is also the off switch — set a source to `blocked` and its
importer stops, with no code change.

**Nothing that would edit the authored Egyptian layer.** An imported slug
carries its external id, so a catalogue row cannot land on `baladi_bread`. A
food a source already links — every food `ingest_usda.ts` mapped onto the seed
— gets its nutrient values refreshed and nothing else: no new aliases, no new
portions, no renaming. The authored layer is the asset; a bulk importer is not
allowed to rewrite it.

**Nothing implausible.** Crowd-sourced data has kilojoules in the kcal field
and milligrams in a grams field. Both produce a confident wrong number, which
is worse than a gap: a missing food shows as an estimate the user can correct,
a wrong one shows as a figure they will not question. `screenNutrients` drops
the individual value that is out of range, and rejects the whole food when its
stated energy cannot be produced by its own macros.

**Nothing that outranks the seed.** Every imported food gets a `source_rank`
below the 50 the authored seed uses, and every imported alias a `priority`
below the 100 a hand-written alias uses. When an imported bread and
`baladi_bread` both answer to عيش at the same score, the authored row wins.

### Scale

Foundation, SR Legacy and Survey together are about 15,000 foods and fit inside
one api.data.gov hourly quota (1,000 requests). USDA Branded is roughly two
million rows of American supermarket packaging — a hundred thousand detail
requests, a hundred hours — so `--datasets=branded` exists but is not the
default. Packaged goods belong to Open Food Facts, which carries Egyptian
products USDA has never heard of, and whose full export is one download.

## Costs and limits, before this goes live

Nothing here rate-limits per user yet. `ai_interactions` records every call and
is the table to meter against. Decide a per-day cap before launch, or a single
user can run up the model bill on your behalf.
