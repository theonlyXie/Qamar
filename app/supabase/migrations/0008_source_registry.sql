-- The source registry.
--
-- Small, unglamorous, and early, because it is what turns a licensing
-- checklist into something the code can enforce. The acceptance checklist in
-- the architecture paper requires that FatSecret be blocked from
-- dietitian-advice production use unless a Qamar-compatible contract is
-- signed. A line in a document does not block anything. A row with
-- ai_advice_rights = false, consulted by the food resolver, does.
--
-- Every later migration that ingests something — foods, clinical rules,
-- supplement labels — references a source_id here, so that every stored fact
-- can answer three questions: where did this come from, are we allowed to keep
-- it, and are we allowed to base advice on it.
--
-- Scope note: seeded for consumer wellness. The disease-specific guideline
-- bodies (ADA, KDIGO, ESPEN, ASPEN, NICE) are deliberately absent — they
-- belong to the condition-aware phase, and listing them here as 'deprecated'
-- would imply a decision nobody has made yet. General population guidance
-- (NASEM, WHO, EFSA, DGA) is in, because the requirement engine needs it.

create table if not exists public.source_registry (
  source_id text primary key,
  name text not null,
  kind text not null check (kind in (
    'food_composition',      -- USDA FDC, national food composition tables
    'commercial_food_api',   -- FatSecret, Nutritionix, Edamam, Passio, CHOMP
    'open_product_data',     -- Open Food Facts
    'population_guidance',   -- NASEM DRI, WHO, EFSA, DGA
    'supplement',            -- NIH ODS, DSLD
    'medication',            -- RxNorm, DailyMed
    'telemetry',             -- Google Health, HealthKit, Health Connect
    'model_provider',
    'other'
  )),

  official_docs_url text,
  api_base_url text,
  auth_method text,
  pricing_url text,
  terms_url text,

  -- The three rights that decide what Qamar may do with the data. They are
  -- separate on purpose: "free to read" says nothing about whether results may
  -- be cached, and caching rights say nothing about whether advice may rest on
  -- them.
  license_class text not null default 'unknown' check (license_class in (
    'public_domain',            -- CC0 / US federal work: unrestricted
    'open_permissive',          -- open licence, no share-alike obligation
    'open_share_alike',         -- ODbL and similar: obligations on derived DBs
    'proprietary_licensed',     -- commercial, contract signed and on file
    'proprietary_unlicensed',   -- commercial, no contract: do not depend on it
    'unknown'
  )),
  storage_rights text not null default 'unknown' check (storage_rights in (
    'none',                -- query-time only, nothing may be persisted
    'transient_cache',     -- short-lived cache only
    'time_limited_cache',  -- cache up to cache_ttl_hours
    'indefinite',          -- may be stored in the knowledge layer
    'unknown'
  )),
  cache_ttl_hours int check (cache_ttl_hours is null or cache_ttl_hours > 0),
  -- NULL means nobody has established the answer. Treated as false everywhere
  -- it matters: an unanswered licensing question is not permission.
  ai_advice_rights boolean,

  regions_languages text[],
  rate_limits text,

  -- Operational health, per the recheck discipline the paper asks for.
  last_manual_review date,
  last_healthcheck timestamptz,
  expected_schema_hash text,
  owner text,
  status text not null default 'deprecated' check (status in (
    'active',      -- cleared and in use
    'degraded',    -- reachable but failing checks
    'blocked',     -- must not be called; licensing or safety
    'deprecated'   -- not cleared for use; the default until someone clears it
  )),
  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists source_registry_status_idx on public.source_registry (status);

-- Procurement metadata: contract terms, pricing pages, named owners. Server
-- only. RLS is enabled with no client policy, which denies anon and
-- authenticated outright while the service role continues to bypass it. That
-- is the intent, not an oversight — there is no user-facing reason to read
-- this table.
alter table public.source_registry enable row level security;

create or replace function public.qamar_touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists source_registry_touch on public.source_registry;
create trigger source_registry_touch
  before update on public.source_registry
  for each row execute function public.qamar_touch_updated_at();

-- ---------------------------------------------------------------------
-- The enforcement point
-- ---------------------------------------------------------------------
--
-- Fails closed on every axis. An unknown source, an unknown licence, an
-- unanswered advice-rights question and a source that is merely 'degraded' all
-- return false. Callers get permission only when someone has affirmatively
-- recorded it.

create or replace function public.qamar_source_usable_for_advice(p_source_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select s.status = 'active'
        and s.ai_advice_rights is true
        and s.license_class <> 'proprietary_unlicensed'
     from public.source_registry s
     where s.source_id = p_source_id),
    false
  );
$$;

revoke all on function public.qamar_source_usable_for_advice(text) from public;
revoke execute on function public.qamar_source_usable_for_advice(text) from anon, authenticated;

comment on function public.qamar_source_usable_for_advice(text) is
  'True only when a source is active, has recorded AI-advice rights, and is not '
  'an unlicensed commercial dependency. Fails closed: unknown source, unknown '
  'licence, or unanswered rights question all return false.';

-- ---------------------------------------------------------------------
-- Seed
-- ---------------------------------------------------------------------
--
-- Two sources are active because the gateway already calls them and both are
-- open. Everything else is 'deprecated', which here means "not cleared", not
-- "abandoned" — nothing may depend on those rows until someone does the
-- procurement work and updates them.
--
-- Prices and terms are deliberately not stored. They move, and a stale price
-- in a database is worse than no price. The URLs are what get rechecked.

insert into public.source_registry (
  source_id, name, kind, official_docs_url, api_base_url, auth_method,
  pricing_url, terms_url, license_class, storage_rights, ai_advice_rights,
  regions_languages, status, notes
) values

-- ---- in use today ----
('usda_fdc', 'USDA FoodData Central', 'food_composition',
 'https://fdc.nal.usda.gov/api-guide', 'https://api.nal.usda.gov/fdc/v1', 'api_key',
 null, null, 'public_domain', 'indefinite', true,
 array['global','en'], 'active',
 'CC0/public domain. Unrestricted storage and redistribution; the scientific backbone for generic foods. Prefer bulk download over per-item API calls at scale.'),

('open_food_facts', 'Open Food Facts', 'open_product_data',
 'https://openfoodfacts.github.io/openfoodfacts-server/api/', 'https://world.openfoodfacts.org', 'none',
 null, null, 'open_share_alike', 'indefinite', true,
 array['global','en','ar'], 'active',
 'Database ODbL, contents DbCL, images CC BY-SA. Share-alike obligations attach to a derived database and need a legal decision before the food graph is seeded from it. Crowd-sourced: always carry confidence and prefer authoritative sources on conflict.'),

-- ---- blocked on licensing ----
('fatsecret', 'FatSecret Platform', 'commercial_food_api',
 'https://platform.fatsecret.com/docs/guides', 'https://platform.fatsecret.com/rest', 'oauth2',
 'https://platform.fatsecret.com/api-editions', 'https://platform.fatsecret.com/terms',
 'proprietary_unlicensed', 'none', false,
 array['eg','ar','en'], 'blocked',
 'BLOCKED. Standard Platform API terms prohibit using the API to provide diet, nutrition or health advice, guidance or diagnosis — which is the product. Strategically the best Arabic/Egypt coverage, so it is worth negotiating written terms that permit the AI dietitian use case. Do not build a production dependency until that contract exists.'),

-- ---- candidates, not cleared ----
('nutritionix', 'Nutritionix / Syndigo', 'commercial_food_api',
 'https://developer.nutritionix.com/docs/v2', null, 'api_key',
 'https://www.nutritionix.com/api', null, 'proprietary_unlicensed', 'unknown', null,
 array['global','en'], 'deprecated',
 'Strong natural-language logging and branded/restaurant coverage. Bulk database licensing is the option to price if durable local storage is needed.'),

('edamam', 'Edamam', 'commercial_food_api',
 'https://developer.edamam.com/food-database-api-docs', 'https://api.edamam.com', 'app_id_key',
 null, null, 'proprietary_unlicensed', 'unknown', null,
 array['global','en'], 'deprecated',
 'Parser and recipe analysis. Standard plans are request-driven and restrict local mirroring; treat as an online resolver unless separately licensed.'),

('passio', 'Passio Nutrition-AI', 'commercial_food_api',
 'https://www.passio.ai/platform', null, 'api_key',
 'https://www.passio.ai/pricing', null, 'proprietary_unlicensed', 'unknown', null,
 array['global','en'], 'deprecated',
 'Multimodal intake: photo, voice, barcode, OCR. Candidate for the image bake-off against LogMeal. Generate endpoint paths from authenticated docs rather than hardcoding.'),

('logmeal', 'LogMeal', 'commercial_food_api',
 'https://logmeal.com/api/', null, 'api_key',
 'https://logmeal.com/api/pricing/', null, 'proprietary_unlicensed', 'unknown', null,
 array['global','en'], 'deprecated',
 'Food vision alternative to Passio. Never let photo recognition produce a precise nutrient number without user confirmation when portion confidence is low.'),

('chomp', 'CHOMP', 'commercial_food_api',
 'https://chompthis.com/api/', null, 'api_key',
 'https://chompthis.com/api/', null, 'proprietary_unlicensed', 'unknown', null,
 array['global','en'], 'deprecated',
 'Packaged and branded foods. Caching rights differ materially by plan, so storage_rights must be set from the contracted tier before use.'),

-- ---- the Egyptian seed ----
('fao_infoods_egypt', 'FAO/INFOODS Egypt Food Composition Tables', 'food_composition',
 'https://www.fao.org/infoods/infoods/tables-and-databases/egypt/en/', null, 'none',
 null, null, 'unknown', 'unknown', null,
 array['eg','ar','en'], 'deprecated',
 'The intended seed for the Egyptian food graph, from the Egyptian Nutrition Institute. Confirm the current edition and reuse rights for a commercial derived database before ingesting. Older tables need treating as a reference, not as complete modern market coverage.'),

('fao_infoods_standards', 'FAO/INFOODS Standards, Guidelines and Density Database', 'food_composition',
 'https://www.fao.org/infoods/infoods/standards-guidelines/en/', null, 'none',
 null, null, 'unknown', 'unknown', null,
 array['global','en'], 'deprecated',
 'Method rather than data: food-matching rules and household-volume-to-weight conversion. Shapes how food_portions is built.'),

-- ---- population guidance for the requirement engine ----
('nasem_dri', 'NASEM Dietary Reference Intakes', 'population_guidance',
 'https://www.nationalacademies.org/publications/26818', null, 'none',
 null, null, 'unknown', 'unknown', null,
 array['global','en'], 'deprecated',
 'Primary source for the 2023 energy equations and the RDA/AI/UL tables. Reports are free to read; publication rights still apply to reproduction. Every stored value needs its edition year and unit.'),

('who_nutrition', 'WHO Nutrition Guidance', 'population_guidance',
 'https://www.who.int/health-topics/nutrition', null, 'none',
 null, null, 'unknown', 'unknown', null,
 array['global','en','ar'], 'deprecated',
 'Global healthy-diet, sodium and sugar guardrails. Free to access; confirm reuse terms before redistributing text.'),

('efsa_drv', 'EFSA Dietary Reference Values', 'population_guidance',
 'https://www.efsa.europa.eu/en/topics/topic/dietary-reference-values', null, 'none',
 null, null, 'unknown', 'unknown', null,
 array['eu','en'], 'deprecated',
 'European reference family; useful as a cross-check layer and when internationalizing beyond Egypt.'),

('dga_2025', 'Dietary Guidelines for Americans 2025-2030', 'population_guidance',
 'https://www.dietaryguidelines.gov/', null, 'none',
 null, null, 'public_domain', 'indefinite', null,
 array['us','en'], 'deprecated',
 'Pattern-level guidance only. US servings and policy must not become the Egyptian default without localization.'),

-- ---- supplements ----
('nih_ods', 'NIH Office of Dietary Supplements Fact Sheets', 'supplement',
 'https://ods.od.nih.gov/api/', null, 'none',
 null, null, 'public_domain', 'indefinite', null,
 array['us','en'], 'deprecated',
 'Supplement and nutrient evidence for retrieval. Not product-label truth — that is DSLD.'),

('nih_dsld', 'NIH Dietary Supplement Label Database', 'supplement',
 'https://dsld.od.nih.gov/api-guide', 'https://api.ods.od.nih.gov/dsld/v9', 'none',
 null, null, 'public_domain', 'indefinite', null,
 array['us','en'], 'deprecated',
 'Supplement product labels, brands and ingredients. US market coverage, so Egyptian product matching will be partial.'),

-- ---- model provider ----
('anthropic', 'Anthropic Messages API', 'model_provider',
 'https://docs.anthropic.com', 'https://api.anthropic.com', 'api_key',
 null, null, 'proprietary_licensed', 'none', null,
 array['global','en','ar'], 'active',
 'The reasoning and vision provider behind ai-gateway. Registered so model version changes are tracked alongside data sources; a model change must never silently alter clinical rules.')

on conflict (source_id) do nothing;
