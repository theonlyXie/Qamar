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

`kb_sources.json` holds the corpus in the shape `ingest.ts` reads. Run it with
an embedding key and it chunks, embeds and inserts:

```bash
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... VOYAGE_API_KEY=... \
  deno run --allow-net --allow-env --allow-read ingest.ts kb_sources.json
```

**Retrieval only sees a chunk that carries an embedding**, so this is the whole
of the work — a row inserted by hand with a null vector is invisible.

Size the corpus against what the retriever asks for. `retrieve()` takes the top
6 chunks within one domain (8 for plan generation) above a 0.25 similarity
floor. A domain holding 6 chunks therefore returns all of them for every
question, whatever was asked, and retrieval is doing no work at all. The live
project sat at 10 nutrition and 2 training chunks; `kb_sources.json` adds 4 and
7. That is enough for the retriever to start choosing, and it is still a thin
corpus — the number to aim at is several times the top-k per domain, which
means a real content pass with a nutritionist rather than more files like this
one.

Sensible sources to grow it with, licence permitting:

| Domain | Source |
|---|---|
| nutrition | WHO healthy-diet guidance, EFSA dietary reference values |
| nutrition | NIH Office of Dietary Supplements fact sheets |
| nutrition | Egyptian food composition tables (for local dishes) |
| training | ACSM physical-activity guidelines, WHO activity guidelines |

Check each licence before storing text verbatim; `kb_documents.licence` is
there to record what you may quote.

## The food graph has names but no numbers until you fill it

Migrations 0017 and 0054 seed `foods`, `food_aliases`, `food_portions` and
`recipes` — every Egyptian name, portion and recipe composition — and
deliberately **not one nutrient value**. Per-100g figures come from USDA
FoodData Central through `ingest_usda.ts`, so every number traces to a
laboratory analysis, and a composite dish (koshary, a taameya sandwich) is
computed from its ingredients by `qamar_nutrients_per_100g` rather than looked
up. Until the ingest has run, every dish is a resolvable name with no
nutrition, and the gateway falls back to an external lookup for it.

```bash
USDA_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
  deno run --allow-net --allow-env supabase/functions/ai-gateway/ingest_usda.ts [--limit N] [--dry-run]
```

How it decides:

- It takes every `foods` row with `is_recipe = false` and searches USDA for
  `name_en` plus `food_state` (`"Beef, ground, 80% lean meat / 20% fat raw"`).
  The ingredient rows in 0054 are named to overlap the USDA description on
  purpose; keep doing that when adding one.
- A match below the token-overlap floor (0.45) is left alone and listed at the
  end. A wrong food is worse than a missing one.
- A **hand-mapped id wins over the search.** For an item USDA cannot find under
  any English name — عيش بلدي, جبنة قريش, فسيخ — decide the closest generic USDA
  food yourself, then insert a `food_source_links` row with `source_id =
  'usda_fdc'`, `external_type = 'fdc_id'` and the id, and re-run. The importer
  fetches that id directly. The row is the record of who decided what.
- Zero is a value. Water, salt and brewed tea report 0 kcal and are loaded;
  only a food with *no* energy field at all is skipped.
- A food counts as done when it carries the current `NUTRIENT_SET_VERSION`;
  widening `NUTRIENT_MAP` and bumping the version re-fetches everything.

Then check what the dishes can do with it:

```sql
select * from dish_nutrient_readiness where not computable;
```

One row per recipe dish; `missing_ingredients` names the ingredient without an
energy value that is holding the dish back. A dish returns no nutrition at all
until every non-optional ingredient has one, rather than an undercount from the
ingredients that happened to load.

Ingredients 0054 added for the new recipes, expected to match USDA by name:
wheat flour, semolina, phyllo dough, puff pastry, bread crumbs, cornstarch,
rice flour, couscous, white and whole-wheat toast, heavy cream, dry whole milk,
sweetened condensed milk, mozzarella, cheddar, cream cheese, ground beef,
ground lamb, chicken liver, roasted and stewed whole chicken, duck, squab
(pigeon), quail, rabbit, beef tripe, beef brain, beef shank, beef bologna,
fried squid, blue crab, sea bass, Atlantic mackerel, tomato paste, green beans,
artichoke, sweet corn, pumpkin, mushrooms, celery, peppermint, spring onion,
beets, turnip, dill pickles, Swiss chard, french fries, dried apricots, dried
figs, prunes, raisins, tamarind, brewed hibiscus tea, raw orange juice, tap
water, table salt, cumin, coriander seed, anise, fenugreek, ground cinnamon,
ginger root, distilled vinegar, mayonnaise, pistachios, desiccated coconut, jam,
vanilla ice cream.

Migration 0055 already carries the hand-mapped ids for every 0054 ingredient
and for the 0017 ingredients the first ingest left empty (the three breads,
laban rayeb, corn oil, almonds, mango and the other Foundation-Foods rows that
have no energy value). Items still to map if the search misses them, because
USDA has no Egyptian row: areesh / white / roumy / istanbouli cheese, eshta,
samna, Egyptian sausage, basterma, feseekh, molokhia leaves, taro, halawa,
erksous, sugarcane juice, and the generic soft drink. Map each to the closest
USDA relative and say so in the row.

## Clinical rules, and the gate in front of them

`qamar_rule_selection` (0022) returned nothing for every request, for two
reasons rather than one: `clinical_rules` was empty, **and** every guidance body
in `source_registry` was seeded `deprecated` with `ai_advice_rights` null, which
`qamar_source_usable_for_advice` reads as "no". Filling the table without
opening that gate would have changed nothing.

Migration 0056 opens the gate for the sources whose licence is not in question
— works of the US federal government, public domain by 17 U.S.C. § 105 — and
seeds 17 rules from them: the Dietary Guidelines quantitative limits (sodium,
added sugars, saturated fat, fibre), the Physical Activity Guidelines, and the
NIH ODS reference intakes. WHO, EFSA and NASEM stay `deprecated` on purpose:
their numbers are quotable, their licences are recorded as `unknown`, and that
is a determination for someone with the authority to make it.

```sql
select * from clinical_rule_review where needs_review;
```

Every row 0056 seeded is `needs_review`, because `reviewer_id` is null on all of
them. The selection function has no review gate — an uncurated rule still
reaches the reasoner, which is the right default when the alternative is
silence — so this view is how an operator sees what nobody has checked. The DGA
rows cite the 2020–2025 edition, which the 2025–2030 edition supersedes; each
needs re-verifying against the current one.

## Costs and limits, before this goes live

Nothing here rate-limits per user yet. `ai_interactions` records every call and
is the table to meter against. Decide a per-day cap before launch, or a single
user can run up the model bill on your behalf.
