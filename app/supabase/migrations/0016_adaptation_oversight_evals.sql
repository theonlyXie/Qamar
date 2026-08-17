-- Adaptation, human oversight, and the evaluation set.
--
-- The last three, all cheap now that the rest exists. weight_entries has been
-- collecting the input for the adaptation engine since 0001 with nowhere to put
-- the output; the review queue is what makes an escalation land somewhere; and
-- the eval set has to be data rather than a test file, because a source update
-- must be regression-tested against a frozen set that does not drift with the
-- code.

-- ---------------------------------------------------------------------
-- Personal energy model
-- ---------------------------------------------------------------------
-- Estimates change within defined bounds and record why. Both halves matter:
-- an unbounded estimator recalibrates a person's whole day off three noisy
-- mornings, and an unexplained one cannot be debugged when it does.

create table if not exists public.personal_energy_estimates (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  estimated_tdee_kcal numeric(8,2) not null,
  confidence_low numeric(8,2),
  confidence_high numeric(8,2),
  -- What it was computed from.
  window_start date not null,
  window_end date not null,
  observation_days int not null check (observation_days > 0),
  intake_days_logged int,
  weight_measurements int,
  method text not null default 'energy_balance' check (method in
    ('energy_balance','bayesian','robust_regression','equation_only')),
  equation_version_id uuid references public.equation_versions (id),
  -- The guardrail. A step larger than this is rejected, not applied.
  max_step_kcal numeric(8,2) not null default 150,
  previous_estimate_kcal numeric(8,2),
  reason text not null,
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  check (window_end >= window_start),
  check (confidence_high is null or confidence_low is null or confidence_high >= confidence_low)
);

create index if not exists personal_energy_current_idx
  on public.personal_energy_estimates (user_id, created_at desc) where superseded_at is null;

-- Rejects a jump bigger than the recorded bound. The engine is expected to
-- clamp before writing; this is the backstop for when it does not.
create or replace function public.qamar_assert_energy_step()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.previous_estimate_kcal is not null
     and abs(new.estimated_tdee_kcal - new.previous_estimate_kcal) > new.max_step_kcal then
    raise exception
      'energy estimate moved % kcal in one step, bound is %; clamp it or widen max_step_kcal with a reason',
      round(abs(new.estimated_tdee_kcal - new.previous_estimate_kcal)), new.max_step_kcal;
  end if;
  return new;
end;
$$;

drop trigger if exists personal_energy_step_guard on public.personal_energy_estimates;
create trigger personal_energy_step_guard
  before insert on public.personal_energy_estimates
  for each row execute function public.qamar_assert_energy_step();

-- ---------------------------------------------------------------------
-- Human oversight
-- ---------------------------------------------------------------------

create table if not exists public.clinician_reviews (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  task_id uuid references public.evidence_packets (task_id) on delete set null,
  safety_event_id uuid references public.safety_events (id) on delete set null,
  trigger_rule text references public.red_flag_rules (slug),
  -- Minimal relevant profile plus flags and evidence. Deliberately a packet,
  -- not a transcript: a reviewer needs the decision, not the conversation.
  review_packet jsonb not null default '{}',
  explicit_questions text[] not null default '{}',
  status text not null default 'queued' check (status in
    ('queued','in_review','resolved','dismissed','escalated')),
  priority text not null default 'routine' check (priority in ('routine','urgent')),
  reviewer_id text,
  decision text,
  decision_note text,
  queued_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create index if not exists clinician_reviews_queue_idx
  on public.clinician_reviews (status, priority, queued_at) where status in ('queued','in_review');

-- ---------------------------------------------------------------------
-- Evaluation set
-- ---------------------------------------------------------------------
-- The ten test families. Frozen: a source or model change is regression-tested
-- against these before it is accepted.

create table if not exists public.eval_cases (
  id uuid primary key default uuid_generate_v4(),
  family text not null check (family in
    ('nutrition_arithmetic','food_resolution','guideline_applicability','safety',
     'evidence_grounding','meal_optimization','longitudinal_adaptation',
     'arabic_ux','cost_tokens','adversarial_reliability')),
  slug text not null unique,
  description text not null,
  input jsonb not null,
  expected jsonb not null,
  tolerance jsonb not null default '{}',
  -- Frozen cases are the regression baseline and must not be edited in place;
  -- supersede them instead.
  is_frozen boolean not null default true,
  supersedes_case_id uuid references public.eval_cases (id),
  created_at timestamptz not null default now()
);

create index if not exists eval_cases_family_idx on public.eval_cases (family);

create table if not exists public.eval_runs (
  id uuid primary key default uuid_generate_v4(),
  label text not null,
  -- Kept separate on purpose: a model upgrade must never be mistaken for a
  -- clinical-content change, and vice versa.
  model_version text,
  clinical_content_version text,
  food_data_version text,
  trigger text not null default 'manual' check (trigger in
    ('manual','source_update','model_update','scheduled','pre_release')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  passed int not null default 0,
  failed int not null default 0,
  notes text
);

create table if not exists public.eval_results (
  id uuid primary key default uuid_generate_v4(),
  run_id uuid not null references public.eval_runs (id) on delete cascade,
  case_id uuid not null references public.eval_cases (id) on delete cascade,
  passed boolean not null,
  actual jsonb,
  failure_detail text,
  cost_usd numeric(12,6),
  latency_ms int,
  created_at timestamptz not null default now(),
  unique (run_id, case_id)
);

create index if not exists eval_results_run_idx on public.eval_results (run_id, passed);

-- ---------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------

alter table public.personal_energy_estimates enable row level security;
drop policy if exists personal_energy_select_own on public.personal_energy_estimates;
create policy personal_energy_select_own on public.personal_energy_estimates
  for select using (auth.uid() = user_id);

-- The review queue, the eval set and its results are staff surfaces. Server
-- only: a user must not be able to read a clinician's notes about them through
-- the public API, and eval expectations are not user data.
alter table public.clinician_reviews enable row level security;
alter table public.eval_cases enable row level security;
alter table public.eval_runs enable row level security;
alter table public.eval_results enable row level security;
