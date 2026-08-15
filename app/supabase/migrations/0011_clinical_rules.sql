-- Clinical rule objects.
--
-- kb_chunks is a prose index: text plus an embedding. The architecture paper
-- rejects that as sufficient — "do not store guidelines as undifferentiated
-- PDFs alone" — because a recommendation has to trace to something with a
-- population, a jurisdiction, a version and a review date. Chunks stay for
-- narrative retrieval and gain a pointer to the rule they support.
--
-- The point of the population columns is that the retriever filters on
-- metadata *before* vector similarity. Retrieving a pregnancy rule for a
-- non-pregnant adult and then hoping the reasoner notices is the failure mode
-- this prevents.

create table if not exists public.clinical_rules (
  rule_id uuid primary key default uuid_generate_v4(),
  source_id text not null references public.source_registry (source_id),
  source_version text not null,
  publication_date date,
  jurisdiction text,

  -- Population applicability.
  condition text not null default 'general_wellness',
  min_age_years numeric(5,2),
  max_age_years numeric(5,2),
  sex text not null default 'any' check (sex in ('male','female','any')),
  life_stage text not null default 'any' check (life_stage in
    ('any','adult','older_adult','adolescent','child','pregnancy','lactation')),
  setting text,
  prerequisites jsonb not null default '[]',

  recommendation_type text not null check (recommendation_type in
    ('target','limit','prefer','avoid','monitor','refer')),
  variable text,
  comparator text check (comparator is null or comparator in ('<','<=','=','>=','>','between','n/a')),
  value_low numeric(12,4),
  value_high numeric(12,4),
  unit text,
  -- The human-readable form the reasoner is handed. Compact on purpose: the
  -- packet carries this, not the source document.
  compact_recommendation text not null,

  strength_of_recommendation text,
  certainty_or_evidence_grade text,
  exceptions jsonb not null default '[]',
  contraindications jsonb not null default '[]',
  monitoring jsonb not null default '[]',

  source_locator jsonb not null default '{}',   -- {url, section, table, page, anchor}
  licensing_class text,

  curator_id text,
  reviewer_id text,
  last_verified timestamptz,
  -- The chain that makes an annual guideline cycle survivable: you can always
  -- tell which edition a past recommendation came from.
  supersedes_rule_id uuid references public.clinical_rules (rule_id),
  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (max_age_years is null or min_age_years is null or max_age_years > min_age_years)
);

create index if not exists clinical_rules_applicability_idx
  on public.clinical_rules (condition, life_stage, sex, is_active);
create index if not exists clinical_rules_source_idx on public.clinical_rules (source_id);
create index if not exists clinical_rules_supersedes_idx on public.clinical_rules (supersedes_rule_id);

drop trigger if exists clinical_rules_touch on public.clinical_rules;
create trigger clinical_rules_touch before update on public.clinical_rules
  for each row execute function public.qamar_touch_updated_at();

-- A chunk may now point at the rule it supports, so narrative context and the
-- citable rule travel together instead of being two unrelated retrievals.
alter table public.kb_chunks add column if not exists rule_id uuid
  references public.clinical_rules (rule_id) on delete set null;
create index if not exists kb_chunks_rule_idx on public.kb_chunks (rule_id);

-- kb_documents.domain was nutrition|training only. Rules arrive from bodies
-- that are neither.
alter table public.kb_documents drop constraint if exists kb_documents_domain_check;
alter table public.kb_documents add constraint kb_documents_domain_check
  check (domain in ('nutrition','training','clinical','supplement','safety'));

alter table public.clinical_rules enable row level security;
drop policy if exists clinical_rules_read on public.clinical_rules;
create policy clinical_rules_read on public.clinical_rules
  for select to authenticated using (is_active);

-- ---------------------------------------------------------------------
-- Applicability, as a function rather than as reasoner judgement
-- ---------------------------------------------------------------------
-- Whether a rule applies to a person is arithmetic. Doing it in SQL means the
-- retriever cannot accidentally hand the reasoner something out of population,
-- and means excluded_rules in the evidence packet can record a real reason.

create or replace function public.qamar_rule_applies(
  p_rule public.clinical_rules,
  p_age_years numeric,
  p_sex text,
  p_life_stage text,
  p_condition text default 'general_wellness'
) returns boolean
language sql
immutable
set search_path = public
as $$
  select p_rule.is_active
     and (p_rule.condition = 'general_wellness' or p_rule.condition = p_condition)
     and (p_rule.sex = 'any' or p_sex is null or p_rule.sex = p_sex)
     and (p_rule.life_stage = 'any' or p_life_stage is null or p_rule.life_stage = p_life_stage)
     and (p_rule.min_age_years is null or p_age_years is null or p_age_years >= p_rule.min_age_years)
     and (p_rule.max_age_years is null or p_age_years is null or p_age_years <= p_rule.max_age_years);
$$;

comment on function public.qamar_rule_applies is
  'Population filter applied before semantic retrieval. A rule that fails this '
  'must be recorded in the evidence packet as excluded, with the reason, rather '
  'than silently dropped.';
