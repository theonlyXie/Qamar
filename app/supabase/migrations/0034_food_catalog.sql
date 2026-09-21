-- Making the food graph survive a catalogue.
--
-- Until now `foods` held the 131 items the Egyptian seed authored by hand, and
-- every index on it was sized for that. catalog_usda.ts and catalog_off.ts turn
-- it into tens of thousands of rows with up to twenty-six nutrient values each,
-- which is a different table with the same name.
--
-- Two of the three things here are indexes the importers themselves need. Both
-- support the same question, asked once at the start of every run and once
-- again on every resume: what did the last run already finish? Without them
-- that question is a sequential scan of the largest tables in the database, so
-- the answer arrives slowly on the first run and not at all on the tenth.
--
-- What is deliberately NOT here: any change to qamar_resolve_food. Growing the
-- alias table changes what the resolver sees, and the eval suite is the thing
-- that should decide whether the ranking still holds. Ranking is handled by
-- data instead — every imported food carries a source_rank below the 50 the
-- authored seed uses, and every imported alias a priority below the 100 an
-- authored colloquial name uses, so a catalogue row cannot outrank عيش بلدي on
-- a tie.

-- ---------------------------------------------------------------------
-- Resume, in one index each
-- ---------------------------------------------------------------------

-- The importer asks "which external ids has this source already linked?".
-- The existing unique index leads on qamar_food_id, so it cannot answer a
-- query filtered on source_id, and food_source_links_external_idx leads on
-- external_type. Neither helps; this does.
create index if not exists food_source_links_source_idx
  on public.food_source_links (source_id, external_id);

-- And "which foods already carry nutrients at the current set version?".
-- At one nutrient row per food per code, this is the table that gets large
-- first — roughly twenty-six rows for every food imported.
create index if not exists food_nutrients_version_idx
  on public.food_nutrients (nutrient_definition_version);

-- ---------------------------------------------------------------------
-- What actually landed, per source
-- ---------------------------------------------------------------------
-- 0018 already has food_graph_coverage, which answers "how much of the graph
-- has nutrient values" for the graph as a whole. That was the right question
-- when the graph was one authored seed. With two importers it is no longer
-- enough: the number it returns is a blend, and a completely failed Open Food
-- Facts run hides inside a healthy USDA one.
--
-- A half-finished load is the normal failure here, not the exceptional one. A
-- rate limit at request 1,001 leaves a perfectly valid database holding a third
-- of a catalogue, and nothing about the tables says so.
--
-- with_energy against foods is the pair to read. A food with no energy value
-- cannot appear on any screen in the app, so it is imported stock that is not
-- yet usable stock, and the gap between those two columns is what tells you to
-- run the loader again. Re-running resumes rather than duplicating.

create or replace view public.food_catalog_coverage
with (security_invoker = true) as
with linked as (
  select distinct l.source_id, l.qamar_food_id
  from public.food_source_links l
)
select
  l.source_id,
  count(*)                                              as foods,
  count(*) filter (where exists (
    select 1 from public.food_nutrients n
    where n.qamar_food_id = f.qamar_food_id
      and n.nutrient_code = 'energy_kcal'))             as with_energy,
  count(*) filter (where exists (
    select 1 from public.food_nutrients n
    where n.qamar_food_id = f.qamar_food_id))           as with_any_nutrient,
  count(*) filter (where exists (
    select 1 from public.food_portions p
    where p.qamar_food_id = f.qamar_food_id))           as with_portion,
  max(f.created_at)                                     as newest
from linked l
join public.foods f on f.qamar_food_id = l.qamar_food_id
group by l.source_id

union all

-- Everything with no external link at all: the authored Egyptian seed, minus
-- whatever ingest_usda.ts has since mapped to an fdcId. A food can be counted
-- under a source and be authored — that is not double counting, it is the
-- source having supplied values for a row somebody else wrote.
select
  'unlinked',
  count(*),
  count(*) filter (where exists (
    select 1 from public.food_nutrients n
    where n.qamar_food_id = f.qamar_food_id
      and n.nutrient_code = 'energy_kcal')),
  count(*) filter (where exists (
    select 1 from public.food_nutrients n
    where n.qamar_food_id = f.qamar_food_id)),
  count(*) filter (where exists (
    select 1 from public.food_portions p
    where p.qamar_food_id = f.qamar_food_id)),
  max(f.created_at)
from public.foods f
where not exists (
  select 1 from public.food_source_links l where l.qamar_food_id = f.qamar_food_id
);

comment on view public.food_catalog_coverage is
  'One row per ingestion source, plus ''unlinked'' for foods no source has '
  'claimed — mostly the authored Egyptian seed. Read with_energy against '
  'foods: a gap is a half-finished load, which is what a rate-limited '
  'importer leaves behind, and re-running the loader resumes rather than '
  'duplicating. food_graph_coverage in 0018 answers the same question for the '
  'graph as a whole, where one failed source can hide inside a healthy one.';

-- Readable by the app, same as food_graph_coverage and for the same reason: it
-- counts reference rows the app may already read, and reports about nobody.
-- security_invoker keeps RLS on the tables underneath in charge — see 0023 for
-- what happens when a view in public is created without it.

-- ---------------------------------------------------------------------
-- The ranking contract, written down where the data lives
-- ---------------------------------------------------------------------
-- These two numbers are the only thing standing between a working resolver and
-- one that answers عيش with an American wheat bread. They are enforced in the
-- importers and asserted in catalog_test.ts; this is so the next person to add
-- a source finds out before they pick a number rather than after.

comment on column public.foods.source_rank is
  'Higher wins a tie in qamar_resolve_food. 50 is the authored Egyptian seed '
  'and every imported catalogue sits below it: USDA Foundation 45, SR Legacy '
  '40, Survey/FNDDS 35, USDA Branded 25, Open Food Facts 20. A new source '
  'ranks above 50 only if it is better than a dietitian writing the row by '
  'hand.';

comment on column public.food_aliases.priority is
  'Breaks a tie between two foods claiming the same phrase at the same score. '
  'Authored: 140 a distinguishing modifier, 130 a colloquial Egyptian name, '
  '120 a food''s own name, 100 a hand-written alias, 50 a known misspelling. '
  'Imported catalogues use 70 for a source''s own name and 65 for a variant, '
  'so an authored Egyptian name always wins the tie. See 0029 for why a '
  'modifier needs an alias of its own.';
