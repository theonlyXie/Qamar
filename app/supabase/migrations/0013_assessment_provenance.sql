-- Assessment depth and per-fact provenance.
--
-- profiles is flat columns with one updated_at for the whole row, so nothing
-- can say when the weight was measured, whether a device or the user supplied
-- it, or how much to trust it. The requirement is explicit: date, source and
-- confidence per measurement.
--
-- profiles stays as the current-value projection, because the app reads it on
-- every screen and a join per field would be absurd. profile_facts is the
-- history and the provenance underneath it.

create table if not exists public.profile_facts (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  domain text not null check (domain in
    ('identity','anthropometric','goal','activity','diet_history','preference',
     'culture','economics','health_context','behaviour','sleep','other')),
  field text not null,
  value_text text,
  value_num numeric(14,4),
  value_json jsonb,
  unit text,
  source text not null default 'self_reported' check (source in
    ('self_reported','device','clinician','derived','imported')),
  device_name text,
  confidence numeric(3,2) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  measured_at timestamptz,
  recorded_at timestamptz not null default now(),
  -- Facts are never updated in place: a correction supersedes its predecessor
  -- so the trail of what was believed when survives.
  superseded_by uuid references public.profile_facts (id),
  check (value_text is not null or value_num is not null or value_json is not null)
);

create index if not exists profile_facts_current_idx
  on public.profile_facts (user_id, domain, field) where superseded_by is null;
create index if not exists profile_facts_history_idx
  on public.profile_facts (user_id, field, recorded_at desc);

-- What the assessment still needs. The completeness engine writes here so it
-- can ask only for what changes the decision, rather than interrogating people.
create table if not exists public.assessment_gaps (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  field text not null,
  why_it_matters text,
  blocks_decision boolean not null default false,
  asked_count int not null default 0,
  last_asked_at timestamptz,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, field)
);

create index if not exists assessment_gaps_open_idx
  on public.assessment_gaps (user_id) where resolved_at is null;

-- ---------------------------------------------------------------------
-- Labs
-- ---------------------------------------------------------------------
-- Out of scope to interpret in the wellness tier, but recording them is what
-- lets a red-flag rule fire and a referral happen.

create table if not exists public.user_labs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  analyte text not null,
  loinc_code text,
  value numeric(14,4) not null,
  unit text not null,
  reference_low numeric(14,4),
  reference_high numeric(14,4),
  abnormal_flag text check (abnormal_flag is null or abnormal_flag in ('low','high','critical_low','critical_high','normal')),
  drawn_at timestamptz,
  source text not null default 'self_reported',
  note text,
  created_at timestamptz not null default now()
);

create index if not exists user_labs_user_idx on public.user_labs (user_id, analyte, drawn_at desc);

-- ---------------------------------------------------------------------
-- Medications and supplements
-- ---------------------------------------------------------------------
-- Normalized identity, so an interaction check has something stable to match
-- on. Qamar never changes a medication; it records one and, where relevant,
-- surfaces an interaction for a clinician or pharmacist to decide about.

create table if not exists public.user_medications (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name_as_entered text not null,
  rxcui text,                     -- RxNorm concept
  dose text,
  schedule text,
  started_on date,
  stopped_on date,
  source text not null default 'self_reported',
  created_at timestamptz not null default now()
);

create index if not exists user_medications_user_idx on public.user_medications (user_id) where stopped_on is null;
create index if not exists user_medications_rxcui_idx on public.user_medications (rxcui);

create table if not exists public.user_supplements (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name_as_entered text not null,
  dsld_id text,                   -- NIH Dietary Supplement Label Database
  brand text,
  dose text,
  schedule text,
  started_on date,
  stopped_on date,
  source text not null default 'self_reported',
  created_at timestamptz not null default now()
);

create index if not exists user_supplements_user_idx on public.user_supplements (user_id) where stopped_on is null;

-- Findings, not decisions. severity drives escalation; the recommendation is
-- always to discuss it with a clinician or pharmacist, never to change a dose.
create table if not exists public.interaction_findings (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  medication_id uuid references public.user_medications (id) on delete cascade,
  supplement_id uuid references public.user_supplements (id) on delete cascade,
  food_label text,
  severity text not null check (severity in ('info','caution','serious')),
  summary text not null,
  source_id text references public.source_registry (source_id),
  source_locator jsonb not null default '{}',
  surfaced_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists interaction_findings_user_idx on public.interaction_findings (user_id, severity);

-- ---------------------------------------------------------------------
-- Access — all of this is the user's own health data
-- ---------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array[
    'profile_facts','assessment_gaps','user_labs','user_medications',
    'user_supplements','interaction_findings'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_select_own', t);
    execute format(
      'create policy %I on public.%I for select using (auth.uid() = user_id)', t || '_select_own', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert_own', t);
    execute format(
      'create policy %I on public.%I for insert with check (auth.uid() = user_id)', t || '_insert_own', t);
    execute format('drop policy if exists %I on public.%I', t || '_update_own', t);
    execute format(
      'create policy %I on public.%I for update using (auth.uid() = user_id)', t || '_update_own', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete_own', t);
    execute format(
      'create policy %I on public.%I for delete using (auth.uid() = user_id)', t || '_delete_own', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Backfill: the profile as it stands becomes the first set of facts
-- ---------------------------------------------------------------------
-- Recorded as self_reported with the profile's own updated_at, because that is
-- honestly all that is known about where these numbers came from.

insert into public.profile_facts (user_id, domain, field, value_num, unit, source, measured_at, recorded_at)
select p.user_id, 'anthropometric', 'height_cm', p.height_cm, 'cm', 'self_reported', p.updated_at, p.updated_at
from public.profiles p where p.height_cm is not null
union all
select p.user_id, 'anthropometric', 'weight_kg', p.weight_kg, 'kg', 'self_reported', p.updated_at, p.updated_at
from public.profiles p where p.weight_kg is not null
union all
select p.user_id, 'anthropometric', 'body_fat_pct', p.body_fat_pct, '%', 'self_reported', p.updated_at, p.updated_at
from public.profiles p where p.body_fat_pct is not null
union all
select p.user_id, 'activity', 'activity_factor', p.activity_factor, null, 'self_reported', p.updated_at, p.updated_at
from public.profiles p where p.activity_factor is not null;

insert into public.profile_facts (user_id, domain, field, value_text, source, measured_at, recorded_at)
select p.user_id, 'goal', 'goal', p.goal, 'self_reported', p.updated_at, p.updated_at
from public.profiles p where p.goal is not null
union all
select p.user_id, 'identity', 'gender', p.gender, 'self_reported', p.updated_at, p.updated_at
from public.profiles p where p.gender is not null
union all
select p.user_id, 'identity', 'life_stage', p.life_stage, 'self_reported', p.updated_at, p.updated_at
from public.profiles p;
