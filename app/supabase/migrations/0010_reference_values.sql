-- Reference values and equation versioning.
--
-- The requirement engine is code, but the numbers it reads are data. Today
-- targets.formula_version names a formula whose coefficients exist nowhere,
-- which means nothing can check the engine and no test can pin it.
--
-- Deliberately NOT seeded with nutrient values. Every row here has to carry its
-- source edition and unit, and reproducing DRI tables from memory would put
-- unciteable numbers behind a provenance column — the exact failure this schema
-- exists to prevent. Ingest them from the NASEM report; the tables and the
-- constraints are ready for it.

create table if not exists public.equation_versions (
  id uuid primary key default uuid_generate_v4(),
  name text not null,                  -- 'EER', 'BMI', 'protein_target'
  version text not null,               -- 'NASEM-2023', 'Mifflin-StJeor-1990'
  source_id text references public.source_registry (source_id),
  citation text,
  -- Who it is valid for. An equation applied outside its population is a
  -- silent error, so applicability is stored rather than assumed.
  population text,
  min_age_years numeric(5,2),
  max_age_years numeric(5,2),
  -- 'any' rather than NULL so the uniqueness below stays a plain constraint.
  sex_or_life_stage text not null default 'any',
  -- Coefficients live here so a correction is a data change, not a deploy.
  coefficients jsonb,
  unit text,
  effective_from date,
  effective_to date,
  is_default boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  unique (name, version, sex_or_life_stage)
);

create index if not exists equation_versions_name_idx on public.equation_versions (name);
create unique index if not exists equation_versions_one_default
  on public.equation_versions (name) where is_default;

create table if not exists public.dri_reference (
  id uuid primary key default uuid_generate_v4(),
  nutrient_code text not null references public.nutrients (code),
  -- RDA and AI are targets, UL is a ceiling, AMDR is a percentage band.
  kind text not null check (kind in ('RDA','AI','UL','AMDR','EAR')),
  sex text not null default 'any' check (sex in ('male','female','any')),
  life_stage text not null default 'adult' check (life_stage in
    ('infant','child','adolescent','adult','older_adult','pregnancy','lactation')),
  min_age_years numeric(5,2) not null,
  max_age_years numeric(5,2),
  value_low numeric(12,4),
  value_high numeric(12,4),
  unit text not null,
  source_id text references public.source_registry (source_id),
  source_edition text not null,
  source_locator text,
  notes text,
  created_at timestamptz not null default now(),
  check (value_low is not null or value_high is not null),
  check (max_age_years is null or max_age_years > min_age_years),
  unique (nutrient_code, kind, sex, life_stage, min_age_years)
);

create index if not exists dri_reference_lookup_idx
  on public.dri_reference (nutrient_code, kind, sex, life_stage);

alter table public.equation_versions enable row level security;
drop policy if exists equation_versions_read on public.equation_versions;
create policy equation_versions_read on public.equation_versions
  for select to authenticated using (true);

alter table public.dri_reference enable row level security;
drop policy if exists dri_reference_read on public.dri_reference;
create policy dri_reference_read on public.dri_reference
  for select to authenticated using (true);

-- Equation rows are declared without coefficients: the engine that implements
-- each one fills them in from the source document, and the unit tests pin them.
-- A row with coefficients still null means "specified, not yet implemented",
-- which is a state worth being able to query.
insert into public.equation_versions
  (name, version, source_id, citation, population, min_age_years, sex_or_life_stage, unit, is_default, notes)
values
  ('BMI','WHO-classification','who_nutrition',
   'WHO body mass index classification',
   'adults', 18, 'any', 'kg/m2', true,
   'weight_kg / height_m^2. Screening index only, never a standalone prescription engine.'),

  ('EER','NASEM-2023','nasem_dri',
   'NASEM, Dietary Reference Intakes for Energy (2023)',
   'healthy adults', 19, 'any', 'kcal/day', true,
   'Primary energy equation. Coefficients pending ingestion from the report; select by age, sex, life stage and physical activity level. Not valid for pregnancy or lactation, which are out of scope.'),

  ('protein_target','AMDR-plus-goal','nasem_dri',
   'NASEM AMDR with goal and training adjustment',
   'healthy adults', 18, 'any', 'g/kg/day', true,
   'Range, not a single default grams/kg. Selected from life stage, goal, training load and energy balance.'),

  ('fiber_target','AI-adequate-intake','nasem_dri',
   'NASEM Adequate Intake for total fibre',
   'healthy adults', 18, 'any', 'g/day', true,
   'Guideline-driven, modified by energy intake.'),

  ('fluid_target','AI-adequate-intake','nasem_dri',
   'NASEM Adequate Intake for total water',
   'healthy adults', 18, 'any', 'mL/day', true,
   'Modified by climate and activity, which matters more in Egypt than the base figure does.')
on conflict (name, version, sex_or_life_stage) do nothing;

comment on table public.dri_reference is
  'Empty by design until ingested from source documents. Every row must carry '
  'source_edition and unit; a value without a citable edition does not belong '
  'here, because the engines that read it promise traceability.';
