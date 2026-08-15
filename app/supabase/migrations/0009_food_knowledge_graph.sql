-- The Qamar Egyptian Food Knowledge Graph.
--
-- The proprietary asset. Until now every food was free text inside
-- meal_logs.items, resolved against USDA and Open Food Facts on each request,
-- which the architecture paper's acceptance checklist forbids: Arabic and
-- Egyptian aliases must resolve to canonical Qamar food IDs rather than being
-- treated as free text forever.
--
-- Two rules shape the design. Vendor IDs live only in food_source_links and
-- never leak upward, so any commercial API can be removed without touching
-- anything above the canonical layer. And provenance is per field, not per row,
-- because a dish routinely takes its energy from USDA and its portion from a
-- national table.

create extension if not exists pg_trgm;

-- ---------------------------------------------------------------------
-- Rights provenance on the registry
-- ---------------------------------------------------------------------
-- Licensing is asserted by a person, on a date, against a contract. Recording
-- the assertion separately from the permission is the difference between an
-- audit trail and a rumour.

alter table public.source_registry add column if not exists rights_asserted_by text;
alter table public.source_registry add column if not exists rights_asserted_on date;
alter table public.source_registry add column if not exists contract_reference text;

comment on column public.source_registry.rights_asserted_by is
  'Who asserted the storage/advice rights recorded on this row. Set this '
  'together with ai_advice_rights: permission without an asserting party is '
  'how an unlicensed dependency becomes a production dependency.';

-- ---------------------------------------------------------------------
-- Nutrient dimension
-- ---------------------------------------------------------------------

create table if not exists public.nutrients (
  code text primary key,
  name_en text not null,
  name_ar text,
  unit text not null,
  category text not null check (category in
    ('energy','macro','fatty_acid','amino_acid','vitamin','mineral','other')),
  display_order int not null default 999
);

-- ---------------------------------------------------------------------
-- Canonical foods
-- ---------------------------------------------------------------------

create table if not exists public.foods (
  qamar_food_id uuid primary key default uuid_generate_v4(),
  slug text not null unique,
  name_en text not null,
  name_ar text,           -- Modern Standard Arabic
  name_eg text,           -- Egyptian colloquial, which is what people actually say
  brand text,
  country_region text,

  food_state text not null default 'unspecified' check (food_state in
    ('raw','cooked','boiled','fried','grilled','baked','steamed','dried',
     'canned','prepared','unspecified')),
  preparation_note text,
  -- Fraction of purchased weight that is eaten: bananas have skins.
  edible_portion_fraction numeric(4,3) not null default 1.000
    check (edible_portion_fraction > 0 and edible_portion_fraction <= 1),
  is_recipe boolean not null default false,
  food_group text,

  -- Diet attributes. NULL means unestablished, never "no".
  is_vegetarian boolean,
  is_vegan boolean,
  is_pescatarian boolean,
  contains_gluten boolean,
  allergens text[] not null default '{}',

  -- Quality, per the paper's food-graph quality family.
  source_rank int,
  confidence numeric(3,2) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  has_conflicting_values boolean not null default false,
  human_reviewed boolean not null default false,
  reviewed_by text,
  last_verified timestamptz,
  version int not null default 1,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists foods_group_idx on public.foods (food_group);
create index if not exists foods_recipe_idx on public.foods (is_recipe) where is_recipe;
create index if not exists foods_name_en_trgm on public.foods using gin (name_en gin_trgm_ops);
create index if not exists foods_name_eg_trgm on public.foods using gin (name_eg gin_trgm_ops);

drop trigger if exists foods_touch on public.foods;
create trigger foods_touch before update on public.foods
  for each row execute function public.qamar_touch_updated_at();

-- ---------------------------------------------------------------------
-- Aliases — the table that makes Arabic work
-- ---------------------------------------------------------------------

create table if not exists public.food_aliases (
  id uuid primary key default uuid_generate_v4(),
  qamar_food_id uuid not null references public.foods (qamar_food_id) on delete cascade,
  alias text not null,
  lang text not null check (lang in ('en','ar','eg','translit')),
  is_misspelling boolean not null default false,
  is_voice_variant boolean not null default false,
  -- Higher wins when two foods claim the same phrase.
  priority int not null default 100,
  created_at timestamptz not null default now(),
  unique (qamar_food_id, alias, lang)
);

create index if not exists food_aliases_lookup_idx on public.food_aliases (lower(alias));
-- Trigram, because Egyptian spelling of the same dish varies per person and
-- exact match would send most of them to a paid API for no reason.
create index if not exists food_aliases_trgm on public.food_aliases using gin (alias gin_trgm_ops);

-- ---------------------------------------------------------------------
-- Portions — Egyptian household measures
-- ---------------------------------------------------------------------

create table if not exists public.food_portions (
  id uuid primary key default uuid_generate_v4(),
  qamar_food_id uuid not null references public.foods (qamar_food_id) on delete cascade,
  label_en text not null,
  label_ar text,
  grams numeric(9,2) not null check (grams > 0),
  is_household boolean not null default true,
  is_default boolean not null default false,
  -- How the gram figure was arrived at, per INFOODS method.
  basis text not null default 'estimated' check (basis in
    ('measured','density','yield','vendor','estimated')),
  source_id text references public.source_registry (source_id),
  confidence numeric(3,2) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  created_at timestamptz not null default now(),
  unique (qamar_food_id, label_en)
);

create index if not exists food_portions_food_idx on public.food_portions (qamar_food_id);
-- At most one default portion per food.
create unique index if not exists food_portions_one_default
  on public.food_portions (qamar_food_id) where is_default;

-- ---------------------------------------------------------------------
-- Nutrition — long, not wide
-- ---------------------------------------------------------------------
-- Vitamins, minerals and amino acids arrive over time and a wide table would
-- need a migration for each. Long also lets provenance sit on the individual
-- value, which is the requirement.

create table if not exists public.food_nutrients (
  id uuid primary key default uuid_generate_v4(),
  qamar_food_id uuid not null references public.foods (qamar_food_id) on delete cascade,
  nutrient_code text not null references public.nutrients (code),
  amount numeric(12,4) not null,
  -- Everything normalizes to per 100 g of edible portion unless stated.
  per_basis text not null default 'per_100g' check (per_basis in ('per_100g','per_100ml','per_serving')),
  source_id text references public.source_registry (source_id),
  nutrient_definition_version text,
  confidence numeric(3,2) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  created_at timestamptz not null default now(),
  unique (qamar_food_id, nutrient_code, per_basis)
);

create index if not exists food_nutrients_food_idx on public.food_nutrients (qamar_food_id);

-- ---------------------------------------------------------------------
-- Source links — where vendor IDs are allowed to exist, and nowhere else
-- ---------------------------------------------------------------------

create table if not exists public.food_source_links (
  id uuid primary key default uuid_generate_v4(),
  qamar_food_id uuid not null references public.foods (qamar_food_id) on delete cascade,
  source_id text not null references public.source_registry (source_id),
  external_id text not null,
  external_type text not null check (external_type in
    ('fdc_id','gtin','vendor_id','fct_entry','url','other')),
  url text,
  retrieved_at timestamptz not null default now(),
  -- Honours storage_rights on the registry: a time_limited_cache source must
  -- set this, and a 'none' source must not be linked here at all.
  cache_expires_at timestamptz,
  -- {"energy_kcal": "usda_fdc", "portion_loaf": "fao_infoods_egypt"}
  field_provenance jsonb not null default '{}',
  unique (qamar_food_id, source_id, external_id)
);

create index if not exists food_source_links_food_idx on public.food_source_links (qamar_food_id);
create index if not exists food_source_links_external_idx on public.food_source_links (external_type, external_id);

-- ---------------------------------------------------------------------
-- Recipes — how a national dish gets priced
-- ---------------------------------------------------------------------
-- No food database contains koshary. It is built from ingredients, and this is
-- where that construction is recorded rather than re-derived by a model on
-- every request.

create table if not exists public.recipes (
  qamar_food_id uuid primary key references public.foods (qamar_food_id) on delete cascade,
  yield_g numeric(9,2) check (yield_g is null or yield_g > 0),
  servings numeric(6,2) check (servings is null or servings > 0),
  cooking_method text,
  -- <1 for water loss when roasting, >1 for absorption when boiling rice.
  loss_gain_factor numeric(5,3) not null default 1.000 check (loss_gain_factor > 0),
  region_variant text,
  household_note text,
  source_id text references public.source_registry (source_id),
  confidence numeric(3,2) check (confidence is null or (confidence >= 0 and confidence <= 1))
);

create table if not exists public.recipe_ingredients (
  id uuid primary key default uuid_generate_v4(),
  recipe_id uuid not null references public.recipes (qamar_food_id) on delete cascade,
  ingredient_food_id uuid not null references public.foods (qamar_food_id),
  grams numeric(9,2) not null check (grams > 0),
  is_optional boolean not null default false,
  note text,
  sort_order int not null default 0,
  unique (recipe_id, ingredient_food_id, note)
);

create index if not exists recipe_ingredients_recipe_idx on public.recipe_ingredients (recipe_id);

-- ---------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------
-- Reference knowledge, not user data: any signed-in user may read it, only the
-- service role writes it during ingestion. Same posture as kb_documents.

do $$
declare t text;
begin
  foreach t in array array[
    'nutrients','foods','food_aliases','food_portions','food_nutrients',
    'food_source_links','recipes','recipe_ingredients'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Seed: the nutrient dimension
-- ---------------------------------------------------------------------
-- Only the nutrients the app already shows plus the ones the wellness modules
-- need. Food values themselves are an ingestion job, not a migration.

insert into public.nutrients (code, name_en, name_ar, unit, category, display_order) values
  ('energy_kcal','Energy','طاقة','kcal','energy',1),
  ('protein_g','Protein','بروتين','g','macro',2),
  ('carbs_g','Carbohydrate','كربوهيدرات','g','macro',3),
  ('fat_g','Fat','دهون','g','macro',4),
  ('fiber_g','Fibre','ألياف','g','macro',5),
  ('sugars_g','Sugars','سكريات','g','macro',6),
  ('sat_fat_g','Saturated fat','دهون مشبعة','g','fatty_acid',7),
  ('sodium_mg','Sodium','صوديوم','mg','mineral',8),
  ('potassium_mg','Potassium','بوتاسيوم','mg','mineral',9),
  ('calcium_mg','Calcium','كالسيوم','mg','mineral',10),
  ('iron_mg','Iron','حديد','mg','mineral',11),
  ('zinc_mg','Zinc','زنك','mg','mineral',12),
  ('vitamin_d_ug','Vitamin D','فيتامين د','µg','vitamin',13),
  ('vitamin_b12_ug','Vitamin B12','فيتامين ب١٢','µg','vitamin',14),
  ('folate_ug','Folate','فولات','µg','vitamin',15),
  ('vitamin_c_mg','Vitamin C','فيتامين ج','mg','vitamin',16),
  ('vitamin_a_ug','Vitamin A','فيتامين أ','µg','vitamin',17),
  ('iodine_ug','Iodine','يود','µg','mineral',18),
  ('water_g','Water','ماء','g','other',19)
on conflict (code) do nothing;
