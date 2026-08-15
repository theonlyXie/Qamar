# Finishing the Qamar database

This plan turns the *Dietitian Knowledge Base, Food Intelligence APIs and
Multi-Agent Reasoning Architecture v1.0* into migrations. It is written against
what is actually live on `stqirjlqzchcoeegumoq` as of 2026-08-15 — migrations
`0001`–`0006`, fifteen tables — not against what the repository claims.

The blueprint's own sentence is the thing to design for:

> The LLM speaks; Qamar decides through evidence, code, constraints and
> verified state.

Almost none of that "verified state" has anywhere to live yet. The current
schema is a competent **consumer calorie tracker**. The blueprint describes a
**clinical reasoning system**. The distance between them is mostly missing
tables, and the order they arrive in matters, because later ones are worthless
without earlier ones.

---

## 1. What exists, and what it is missing

| Blueprint requirement | Section | Today | Verdict |
|---|---|---|---|
| Food Knowledge Graph | §24 | nothing | **absent — biggest gap** |
| Clinical rule objects | §25 | `kb_chunks` prose + embedding | **absent** |
| Source registry | §35 | nothing | **absent** |
| Per-fact provenance on the profile | §2, §26 | flat columns on `profiles` | **absent** |
| DRI / EER reference tables | §3, §21 | `targets.formula_version` text only | **absent** |
| Diet pattern ontology | §4 | nothing | **absent** |
| Clinical modules + risk tier | §6, §7 | `profiles.eligibility_status`, 4 values | **too coarse** |
| Medications & supplements | §17 | nothing | **absent** |
| Labs | §26 | nothing | **absent** |
| Personal energy adaptation | §3, layer L | `weight_entries` only (input, no estimates) | **absent** |
| Evidence packets + verifier results | §27, layer J | `ai_interactions.sources` jsonb | **partial** |
| Clinician review queue | layer N, §37 | nothing | **absent** |
| Evaluation suite | §36 | nothing | **absent** |
| Token / API cost per stage | §31 | nothing | **absent** |
| User assessment, targets, meals, wallet | — | present and sound | ✅ keep |

The retrieval layer deserves a specific note. `kb_documents` + `kb_chunks` is a
prose RAG index, and the blueprint rejects that as sufficient in §25: *"Do not
store guidelines as undifferentiated PDFs alone."* Chunks stay — they are how
§32's reasoner gets narrative context — but they cannot be the thing a
recommendation traces to. A recommendation traces to a **rule object** with a
population, a jurisdiction, a version and a review date. Those are different
tables with different lifecycles, and conflating them is the mistake the
blueprint is warning about.

---

## 2. Fix these before adding anything

Four defects in the existing fifteen tables. Each one will corrupt data that
later phases depend on, so they go first, in `0007`.

**Weight and body fat cannot hold a decimal.** `profiles.weight_kg` and
`profiles.body_fat_pct` are `integer`. A person who weighs 73.5 kg cannot be
recorded, and 22.4% body fat rounds to 22. Meanwhile `weight_entries.value_kg`
is already `numeric` — so the profile and the time series disagree about the
same quantity. This is not cosmetic: §3 asks for a *"smoothed trend, rate of
change, measurement noise"* and §L for an energy model that must not overfit
water-weight swings. Integer kilograms destroy precisely the signal those
engines read. `ai-gateway/model.ts` compounds it — the InBody reader runs every
field through `Math.round()`, so a scan that clearly says 73.5 is truncated on
the way in. Change the columns to `numeric(5,2)` and drop the rounding for
weight and body fat; height in whole centimetres is fine.

**Body scans are logged as meal analyses.** `ai_interactions.kind` allows
`chat | meal_analysis | plan`, but the gateway serves four routes. `/scan/read`
records itself as `meal_analysis` with the question `[body scan]`
(`index.ts:345`). Every accuracy question about scan reading is now
unanswerable without string-matching a free-text field. Add `body_scan` to the
check constraint and pass it through.

**Pregnancy is refused by keyword only.** `scope.ts` hard-refuses pregnancy and
lactation, but no column records either, so the refusal is text-matching and
nothing else. §2 lists *"pregnancy/lactation; pediatric/older-adult status"* as
core life-stage fields, and §3's energy equations select on life stage. Until
that is a field, the safety rule is a regex and the equations cannot see it.

**Allergies are a bare `text[]`.** `profiles.food_exclusions` carries the hard
constraint that Appendix C says must never be violated, with no severity, no
distinction between allergy and dislike, and no provenance. A dislike and an
anaphylaxis risk are the same string today. Split them.

---

## 3. The migration sequence

Ten migrations. The order is a dependency order, not a preference.

### `0007` — schema corrections ✅ applied 2026-08-15
Everything in section 2. No new concepts.

`weight_kg` is `numeric(5,2)` and `body_fat_pct` is `numeric(4,1)`; 73.55 and
22.4 round-trip. `body_scan` is a valid `ai_interactions.kind` and the gateway
uses it. `profiles.life_stage` records pregnancy and lactation — deliberately
*not* wired to `eligibility_status`, because those values block an account and
this scope refuses a topic. `food_restrictions` separates allergy from dislike
and carries severity; the old `food_exclusions` array was migrated in as
allergies of unknown severity, and is retained as a deprecated projection
because the app and gateway still read it.

One consequence worth knowing: `profiles` columns now serialize as JSON
doubles, so `row['weight_kg'] as int?` throws. `supabase_repositories.dart` was
casting exactly that way, and `QamarConfig.useSupabase` turns itself on as soon
as the dart-defines in DEPLOY.md step 5 are set — so it would have crashed on
first real use. Now read as `num` and rounded.

**Remaining:** `Profile` models weight and fat as `int`, so the decimal is kept
in the database and in `weight_entries` — which is what the trend engine reads
— but rounded for display. Carrying it end to end means changing the model, the
steppers and the formatters, and belongs with the adaptation work in `0016`.

---

### `0008` — source registry ✅ applied 2026-08-15
§35, and a prerequisite for everything that ingests anything.

`source_registry` holds the §35 fields, with the three rights kept separate on
purpose: `license_class`, `storage_rights` and `ai_advice_rights` answer
different questions, and "free to read" answers none of them.

The enforcement point is `qamar_source_usable_for_advice(source_id)`, which
fails closed on every axis — unknown source, unknown licence, unanswered rights
question and merely-`degraded` status all return `false`. Verified: `usda_fdc`
→ true; `fatsecret`, an uncleared candidate, and an unknown id → all false.

17 sources seeded. USDA FDC, Open Food Facts and Anthropic are `active`.
**FatSecret is `blocked`** with `ai_advice_rights = false`, which is Appendix
C's requirement expressed as a row the resolver can query rather than a line in
a document. Everything else is `deprecated`, meaning *not cleared* — nothing
may depend on it until someone does the procurement and updates the row.

Scoped to consumer wellness: the disease-specific guideline bodies (ADA, KDIGO,
ESPEN, ASPEN, NICE) are deliberately absent rather than listed as `deprecated`,
because listing them would imply a decision nobody has made. General population
guidance is in, because the requirement engine needs it.

RLS is on with no client policy — this table holds contract terms, pricing
pages and owner names, and has no user-facing use. The service role bypasses
RLS, so the gateway reads it normally.

**Exit:** no ingestion path writes a food or a rule without a `source_id` that
resolves here. Not yet enforced — that constraint lands with `0009`, the first
migration that ingests anything.

---

### `0009` — the Egyptian Food Knowledge Graph
§24. The single biggest piece of work, and the actual product moat — §38 calls
it a *"Qamar-owned Egyptian Food Knowledge Graph"* and the conclusion names the
localized food graph first among the things that make Qamar defensible.

Today every food is free text inside `meal_logs.items` jsonb, resolved live
against USDA and Open Food Facts on each request. Appendix C forbids exactly
this: *"Arabic/Egyptian aliases resolve to canonical Qamar food IDs rather than
being treated as free text forever."*

Tables:

- `foods` — `qamar_food_id`, canonical English, Modern Standard Arabic and
  Egyptian Arabic names, brand, country/region, `food_state` (raw, cooked,
  fried, boiled, grilled, drained, peeled), edible-portion fraction,
  `is_recipe`.
- `food_aliases` — alias, language, dialect, is_misspelling, voice-variant
  flag. This is the table that makes Arabic actually work; §36's food-resolution
  tests are written against it.
- `food_portions` — household measures: loaf, ladle, plate, bowl, tablespoon,
  cup, piece — with gram equivalents, density/yield basis, and which of
  §22's INFOODS conversion rules produced them.
- `food_nutrients` — energy, macros, fibre, sugars, fatty acids, cholesterol,
  vitamins, minerals, per 100 g, with a nutrient-definition version.
- `food_source_links` — USDA FDC ID, national FCT entry, barcode/GTIN, vendor
  IDs, `source_id` → `source_registry`, source timestamp, cache-expiry, and
  **field-level** provenance.
- `recipes` / `recipe_ingredients` — ingredients by weight, yield, cooking
  loss/gain, serving count, regional variant.
- Quality columns on `foods`: source rank, confidence, conflicting-values flag,
  `human_reviewed`, `last_verified`, version history.

Two design rules the blueprint is emphatic about. Vendor IDs live only in
`food_source_links` and never leak upward — §38: *"Vendor-specific responses
terminate at adapters."* And nutrient values carry provenance per field, not
per row, because a food often has energy from USDA and a portion from a
national table.

Seed from FAO/INFOODS Egypt plus USDA FDC (CC0, so unrestricted), then grow
Egyptian coverage by hand. §31 is blunt about the payoff: precomputing common
Egyptian foods *"reducing both external calls and tokens."*

**Exit:** the top few hundred Egyptian dishes and staples resolve locally with
Arabic aliases and household portions, and `meal_logs.items` references
`qamar_food_id` instead of carrying loose strings.

---

### `0010` — DRI reference values and equation versioning
§3 and §21. The requirement engine is code, but the numbers it reads are data
and belong in tables.

- `dri_reference` — nutrient, life stage, sex, age range, value, unit,
  `kind ∈ RDA|AI|UL|AMDR`, source edition/year.
- `equation_versions` — equation name, version, applicable population,
  citation, effective dates.

§21: *"Every stored value must include source edition/year and unit."*
`targets.formula_version` already gestures at this; the values themselves
currently exist nowhere, which means nothing can check them and no test can
pin them.

**Exit:** NASEM DRI for Energy (2023) EER equations and the RDA/AI/UL tables
are queryable, versioned, and covered by the reference cases §3 demands.

---

### `0011` — clinical rule objects
§25, implemented as written. `clinical_rules` with `rule_id`, `source_id`,
`source_version`, `publication_date`, `jurisdiction`, population
(`age_range`, `sex_or_life_stage`, `condition`, `setting`), `prerequisites`,
`recommendation_type ∈ target|limit|prefer|avoid|monitor|refer`, `variable`,
`comparator`, `value`, `unit`, `range`, `strength_of_recommendation`,
`certainty_or_evidence_grade`, `exceptions`, `contraindications`, `monitoring`,
`source_locator` (url, section, table/page/anchor), `licensing_class`,
`curator_id`, `reviewer_id`, `last_verified`, `supersedes_rule_id`.

`supersedes_rule_id` is what makes ADA's annual cycle survivable — §23 requires
the *"current annual edition"*, and without a supersession chain you cannot tell
which edition a past recommendation came from.

Keep `kb_chunks` for narrative retrieval; add `rule_id` to it so a chunk can
point at the rule it supports. §29's Evidence Retrieval Agent then filters on
metadata *before* vector search, exactly as §31 requires.

**Exit:** every recommendation the reasoner may make traces to a row here, and
§36's guideline-applicability tests pass on population filtering.

---

### `0012` — diet pattern ontology
§4. Fourteen patterns, each *"a set of rules, evidence claims, nutrient risks,
use cases and adherence requirements"* — not a label in a prompt.

`diet_patterns` — name, definition, evidence quality, nutrient risks,
contraindications, adherence burden. `diet_pattern_rules` — joins a pattern to
`clinical_rules`.

The blueprint is pointed here: low-carbohydrate needs an actual gram or
percentage threshold because you *"never infer from name alone"*, therapeutic
ketogenic must be separable from consumer keto, and carnivore must carry
explicit evidence-quality metadata rather than being *"treated as equally
evidence-based"*.

**Exit:** §33's reasoner can record *why an alternative pattern was not chosen*,
which requires the alternatives to be rows.

---

### `0013` — assessment depth and per-fact provenance
§2 and §26. `profiles` today is flat columns with one `updated_at` for the
whole row. §2 requires *"field-level confidence, timestamp and source"*, and
Appendix C: *"User profile stores date, source and confidence per
measurement/fact."*

Add `profile_facts` — `user_id`, `domain`, `field`, `value`, `unit`, `source`
(self-reported | device | clinician | derived), `confidence`, `measured_at`,
`recorded_at`, `superseded_by`. Keep `profiles` as the fast current-value
projection; `profile_facts` is the history and the provenance.

Then the domains §2 lists that have no home at all: `user_labs` (value, unit,
reference range, drawn_at), `user_medications` (RxNorm `rxcui`, dose, schedule),
`user_supplements` (DSLD ID, dose), activity/training/sleep, behaviour and
adherence, economics (budget, household size, price sensitivity — §33's
optimizer needs these as soft objectives).

**Exit:** every number the app shows about a person carries a date, a source and
a confidence, and §33's completeness engine can ask only for *decision-changing*
missing fields rather than everything.

---

### `0014` — risk tier, modules and the safety engine
§6 and §7. `profiles.eligibility_status` has four values and cannot express
what §7 needs: *"general wellness, condition-aware education, clinician-guided
care, or high-risk/urgent."*

- `clinical_modules` — the twelve of §6, each with eligibility criteria,
  contraindications, required labs, referral thresholds, source versions,
  and a `governance_state` gate.
- `user_active_modules` — which are live for whom, activated when and why.
- `risk_assessments` — tier per request, flags, allowed actions.
- `red_flag_rules` — the escalation triggers of §7.
- `safety_events` — every hard block and every escalation, queryable.

§37 is the constraint that makes `governance_state` mandatory: *"No new
high-risk clinical module goes live solely because an LLM can answer questions
about it."* A module without sign-off must be unable to activate, and that is a
column, not a policy document.

**Exit:** every gateway request records a tier; no module activates without
recorded sign-off; hard blocks are auditable.

---

### `0015` — evidence packets, verification and cost
§27, layer J, and §31's last bullet.

- `evidence_packets` — the §27 shape: `user_facts_used`, `food_facts`,
  `calculated_targets`, `applicable_rules`, **`excluded_rules` with
  `reason_not_applicable`**, `candidate_decision`, `safety_flags`,
  `uncertainty`, `claims_to_verify`.
- `verifier_results` — `PASS | REVISE`, machine-readable failures, revision
  count. §31 caps this: *"verifier can request one bounded correction"*, so the
  counter is the enforcement point.
- `ai_stage_costs` — tokens and API cost per stage, per §31: *"extractor,
  retrieval, reasoner, verifier and final response each have a ceiling."*
  `ai_interactions` records none of this today, so there is currently no way to
  observe the cost the whole token-minimisation section exists to control.

`excluded_rules` looks like an odd thing to persist until an auditor asks why a
diabetic user never saw a diabetes rule. Then it is the only answer.

**Exit:** any past answer can be reconstructed — facts, rules applied, rules
excluded and why, what the verifier said, what it cost.

---

### `0016` — adaptation, oversight and evals
The last three, all cheap once the above exists.

- `personal_energy_estimates` — §L and §3's energy adaptation: estimate,
  confidence interval, observation window, reason for change, and the bounds it
  is not allowed to exceed. §L: *"changes estimates within defined bounds and
  records why."*
- `clinician_reviews` — layer N's queue: packet, questions, reviewer, decision,
  timestamps.
- `eval_cases` / `eval_runs` — §36's ten test families, frozen. §35 requires a
  *"frozen Qamar evaluation set"* to regression-test against before accepting a
  source update, so this must be data, not a test file that drifts.

**Exit:** §36's suite runs against a pinned set, and a source or model change
can be regression-tested before it ships.

---

## 4. What is not a database problem

Building these tables will not by itself satisfy the blueprint. Three
categories sit outside the schema, and two of them block production regardless
of how good the schema gets.

**Deterministic engines (§3).** *"Do not ask the LLM to do the math."* BMI,
weight trajectory, EER, AMDR, protein selection, micronutrient comparison,
portion and recipe maths, energy adaptation — all code with unit tests,
reference cases and a version. The tables in `0010` hold their inputs; they are
not the engines. Today `ai-gateway` asks the model to compute portions from
per-100 g figures inside a prompt, which is the thing §3 forbids.

**The agent DAG (§28–§29).** Fourteen layers and twelve agents, exchanging
typed evidence packets. The gateway today is a single model call per route.
`0015` gives the packets somewhere to live; the routing, the small-model
extractor, the independent verifier and the safety gate are application work.

**Licensing and governance (§Phase 0).** The blueprint puts this *before*
everything: *"No production 'dietitian' claims until scope is legally/clinically
defined."* Nothing in this plan changes that. Specifically — FatSecret's standard
terms forbid nutrition advice, so it cannot be a dependency without a negotiated
contract; Academy NCPT/NCM/EAL need developer or enterprise licences before any
ingestion; Egypt FCT reuse rights need confirming before a derived commercial
database; and Open Food Facts' ODbL creates share-alike obligations on a derived
database that need a decision, not an assumption. `0008` is where each of those
answers gets recorded once you have it.

---

## 4b. Status — `0007`–`0023` applied, 2026-08-15

52 tables, RLS on every one of them.

| Migration | Landed |
|---|---|
| `0009` food graph | `foods`, `food_aliases`, `food_portions`, `food_nutrients`, `food_source_links`, `recipes`, `recipe_ingredients`, `nutrients` (19 seeded), pg_trgm indexes on names and aliases |
| `0010` reference values | `equation_versions` (5 declared), `dri_reference` (empty by design) |
| `0011` clinical rules | `clinical_rules` with supersession, `kb_chunks.rule_id`, `qamar_rule_applies()` |
| `0012` diet ontology | `diet_patterns` (15 seeded, 10 in consumer scope), `diet_pattern_rules`, `user_diet_strategy` |
| `0013` assessment | `profile_facts` (13 backfilled), `assessment_gaps`, `user_labs`, `user_medications`, `user_supplements`, `interaction_findings` |
| `0014` risk and modules | `clinical_modules` (12 seeded, 1 live), `user_active_modules`, `risk_assessments`, `red_flag_rules` (8), `safety_events` |
| `0015` evidence and cost | `evidence_packets`, `verifier_results`, `ai_stage_costs`, `stage_budgets` (8) |
| `0016` adaptation and oversight | `personal_energy_estimates`, `clinician_reviews`, `eval_cases`, `eval_runs`, `eval_results` |
| `0017` Egyptian food seed | 131 foods, 481 aliases, 69 portions (all `estimated`), 6 recipes, 36 ingredients. No nutrient values yet |
| `0018` resolver | `qamar_resolve_food`, `qamar_resolve_portion`, `qamar_nutrients_per_100g`, `food_graph_coverage` |
| `0019` safety views | `safety_rule_activity`, `safety_daily`, `clinician_queue` |
| `0020` red flag detection | `qamar_weight_trend`, triggers on `weight_entries` and `user_labs` |
| `0021` self-harm rule | ninth `red_flag_rules` row; detection text filled in on three others |
| `0022` cost and rule selection | `model_prices` (9 rows), `qamar_token_cost`, pricing trigger on `ai_stage_costs`, `ai_cost_daily`, `stage_budget_pressure`, `qamar_rule_selection` |
| `0023` hardening | `security_invoker` on the four earlier views, staff views revoked from `anon`/`authenticated`, `search_path` pinned on the `0018` resolver functions |

The gateway now writes an `evidence_packets` row and a set of `ai_stage_costs`
rows for every request, including the ones that fail to parse — a call that
produced nothing usable still cost what it cost, and a run of them is how you
find out the prompt has drifted. `cost_usd` is filled by the `0022` trigger from
`model_prices`, so a price correction is one `UPDATE` and does not need the
edge function redeployed.

`verifier_results` remains empty: `claims_to_verify` is now recorded in a
checkable form on every packet, but nothing checks it yet.

Four constraints were tested by trying to violate them: an unapproved module
would not activate, the one live module did, a 600 kcal energy step was refused
where 100 kcal passed, and the verifier revision cap held.

Two seeded tables are deliberately empty. `dri_reference` waits on ingestion
from the NASEM report, because a value without a citable edition does not
belong in a table that promises traceability. `eval_cases` waits on the first
frozen set.

**Ten tables have RLS on with no policy, which is intentional**: `source_registry`,
`red_flag_rules`, `verifier_results`, `ai_stage_costs`, `stage_budgets`,
`model_prices`, `clinician_reviews`, `eval_cases`, `eval_runs`, `eval_results`. These are staff
and operational surfaces — a user must not read a clinician's notes about them
through the public API, and eval expectations are not user data. The service
role bypasses RLS, so the gateway reads them normally. Anything here that later
needs a human-facing view wants a separate authenticated staff role, not a
policy loosened on these tables.

The same applies to the five staff views — `safety_rule_activity`, `safety_daily`,
`clinician_queue`, `ai_cost_daily`, `stage_budget_pressure`. `0023` revoked
`select` on all of them from `anon` and `authenticated` and switched every view
in the schema to `security_invoker`. Before that, a view in `public` ran with
its owner's rights and was reachable through PostgREST by anyone with an
account, which meant `clinician_queue` — other people's escalations, and the
questions asked about them — was readable by any signed-in user. `service_role`
still reads all of them, which is how the founder console should reach them.

## 5. Order of work

`0007` first and immediately — it is small and it stops bad data. Then `0008`,
because nothing should ingest without a registry entry.

`0009` is the long pole and the differentiator; start it early and expect it to
run for weeks alongside everything else. It maps to the blueprint's Phase 1–2.

`0010` and `0011` unblock the reasoner and can proceed in parallel with `0009`
— different people, different skills. `0012` needs `0011`.

`0013` and `0014` are the gate to any condition-aware feature. Nothing in
Phase 4 may ship before both, because §37's sign-off requirement has nowhere to
be recorded until `0014`.

`0015` and `0016` are last but should not be deferred indefinitely: without
`ai_stage_costs` the cost controls in §31 are unmeasurable, and without frozen
evals every source update is a leap of faith.

## 6. Decisions only you can make

1. ~~**Scope of claim.**~~ **Settled 2026-08-15: consumer wellness.** `0014`
   stays small — a risk tier and a module table, no regulated programme — and
   pregnancy, lactation, pediatrics and disease-specific nutrition therapy stay
   out of scope and refuse rather than answer. Revisit before any Phase 4 work.
2. **Which commercial resolver**, if any — and whether its terms permit
   nutrition advice. This changes what `0009` may cache. FatSecret is recorded
   as blocked until a contract exists; Nutritionix, Edamam, Passio, LogMeal and
   CHOMP sit at `deprecated` awaiting a decision.
3. **Egypt FCT and ODbL rights**, before seeding `0009` from them. Open Food
   Facts is `open_share_alike`, and whether those obligations reach a derived
   Qamar food graph is a legal answer, not an engineering one.
4. **Who owns each source** — `source_registry.owner` is null on all 17 rows.
   §37 wants source owners, not just API-key owners.
5. **Who the licensed clinician reviewer is.** `0014` and `0016` both assume one
   exists; neither can be finished without a name.

Items 2 and 3 now gate the next real work. Settle them before `0009` starts,
because re-seeding a food graph under different licence terms means starting it
again.
