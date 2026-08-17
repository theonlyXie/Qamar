-- Risk tier, clinical modules and the safety engine.
--
-- profiles.eligibility_status has four values and cannot express the four
-- operating tiers the safety design needs. The safest architecture is not
-- "answer everything carefully" — it is an explicit scope engine that decides
-- what the system is allowed to do in the current case.
--
-- Scope settled 2026-08-15: consumer wellness. Every module below except
-- general adult wellness ships as not_approved, and the trigger at the bottom
-- makes that a rule rather than an intention — no module activates for a user
-- without recorded sign-off, whatever the reasoner would like to do.

create table if not exists public.clinical_modules (
  slug text primary key,
  name_en text not null,
  name_ar text,
  knowledge_families text,
  eligibility_criteria jsonb not null default '[]',
  contraindications jsonb not null default '[]',
  required_measurements text[] not null default '{}',
  referral_thresholds jsonb not null default '[]',
  min_risk_tier text not null default 'general_wellness' check (min_risk_tier in
    ('general_wellness','condition_aware','clinician_guided','high_risk')),
  -- The gate. A module is not live because a model can answer questions about
  -- it; it is live because a named clinician signed it off on a date.
  governance_state text not null default 'not_approved' check (governance_state in
    ('not_approved','in_review','live','suspended')),
  approved_by text,
  approved_on date,
  source_versions jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (governance_state <> 'live' or (approved_by is not null and approved_on is not null))
);

drop trigger if exists clinical_modules_touch on public.clinical_modules;
create trigger clinical_modules_touch before update on public.clinical_modules
  for each row execute function public.qamar_touch_updated_at();

create table if not exists public.user_active_modules (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  module_slug text not null references public.clinical_modules (slug),
  activated_at timestamptz not null default now(),
  activated_reason text,
  deactivated_at timestamptz,
  unique (user_id, module_slug, activated_at)
);

create index if not exists user_active_modules_open_idx
  on public.user_active_modules (user_id) where deactivated_at is null;

-- Per-request tier decision. Written on every gateway call so that "why did it
-- answer that" has an answer.
create table if not exists public.risk_assessments (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  interaction_id uuid references public.ai_interactions (id) on delete set null,
  risk_tier text not null check (risk_tier in
    ('general_wellness','condition_aware','clinician_guided','high_risk')),
  flags text[] not null default '{}',
  allowed_actions text[] not null default '{}',
  decided_by text not null default 'rules' check (decided_by in ('rules','classifier','model','human')),
  created_at timestamptz not null default now()
);

create index if not exists risk_assessments_user_idx on public.risk_assessments (user_id, created_at desc);

create table if not exists public.red_flag_rules (
  slug text primary key,
  description text not null,
  detection text not null,
  escalate_to text not null check (escalate_to in ('refuse','clinician_review','urgent_referral')),
  min_risk_tier text not null default 'high_risk' check (min_risk_tier in
    ('general_wellness','condition_aware','clinician_guided','high_risk')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Every hard block and every escalation, queryable. This is the table an
-- auditor reads, and the one that answers whether a safety rule ever fired.
create table if not exists public.safety_events (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  interaction_id uuid references public.ai_interactions (id) on delete set null,
  kind text not null check (kind in ('refusal','hard_block','escalation','override_attempt')),
  rule_slug text references public.red_flag_rules (slug),
  reason text not null,
  detail jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists safety_events_user_idx on public.safety_events (user_id, created_at desc);
create index if not exists safety_events_kind_idx on public.safety_events (kind, created_at desc);

-- ---------------------------------------------------------------------
-- The governance gate, enforced
-- ---------------------------------------------------------------------

create or replace function public.qamar_assert_module_live()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_state text;
begin
  select governance_state into v_state
    from public.clinical_modules where slug = new.module_slug;

  if v_state is distinct from 'live' then
    raise exception
      'module % is % and cannot be activated for a user; it needs clinical sign-off first',
      new.module_slug, coalesce(v_state, 'unknown');
  end if;
  return new;
end;
$$;

drop trigger if exists user_active_modules_governance on public.user_active_modules;
create trigger user_active_modules_governance
  before insert on public.user_active_modules
  for each row execute function public.qamar_assert_module_live();

-- ---------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------

alter table public.clinical_modules enable row level security;
drop policy if exists clinical_modules_read on public.clinical_modules;
create policy clinical_modules_read on public.clinical_modules
  for select to authenticated using (governance_state = 'live');

alter table public.red_flag_rules enable row level security;  -- server only, no policy

do $$
declare t text;
begin
  foreach t in array array['user_active_modules','risk_assessments','safety_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_select_own', t);
    execute format(
      'create policy %I on public.%I for select using (auth.uid() = user_id)', t || '_select_own', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Seed
-- ---------------------------------------------------------------------

insert into public.clinical_modules
  (slug, name_en, name_ar, knowledge_families, min_risk_tier, governance_state, approved_by, approved_on)
values
('general_adult_wellness','General adult wellness','صحة عامة للبالغين',
 'DRI/NASEM, WHO, EFSA, DGA','general_wellness','live','product_owner',current_date),
('weight_management','Weight management','إدارة الوزن',
 'NICE, professional guidelines, DRI','condition_aware','not_approved',null,null),
('diabetes','Diabetes / prediabetes','السكري',
 'ADA Standards of Care; medication interaction checks','clinician_guided','not_approved',null,null),
('hypertension','Hypertension / cardiovascular','ضغط الدم',
 'NHLBI DASH, WHO sodium guidance','condition_aware','not_approved',null,null),
('ckd','Chronic kidney disease','أمراض الكلى',
 'KDIGO + renal nutrition sources','high_risk','not_approved',null,null),
('gi_ibs','GI / IBS','الجهاز الهضمي',
 'Evidence-based GI guidance; low-FODMAP under licence','clinician_guided','not_approved',null,null),
('pregnancy','Pregnancy / lactation','الحمل والرضاعة',
 'Life-stage DRI + obstetric guidance','high_risk','not_approved',null,null),
('pediatrics','Pediatrics','الأطفال',
 'Pediatric nutrition standards and growth data','high_risk','not_approved',null,null),
('older_adults','Older adults / frailty','كبار السن',
 'Energy/protein/functional status; malnutrition screening','condition_aware','not_approved',null,null),
('sports','Sports nutrition','التغذية الرياضية',
 'Sports Nutrition Care Manual and sport-specific evidence','general_wellness','not_approved',null,null),
('vegetarian_vegan','Vegetarian / vegan','نباتي',
 'Nutrient adequacy and supplementation evidence','general_wellness','not_approved',null,null),
('clinical_nutrition_support','Enteral / parenteral / severe disease','تغذية علاجية',
 'ASPEN/ESPEN; clinician-controlled only','high_risk','not_approved',null,null)
on conflict (slug) do nothing;

insert into public.red_flag_rules (slug, description, detection, escalate_to, min_risk_tier) values
('eating_disorder','Eating-disorder indicators in language or behaviour',
 'scope.ts keyword set plus intake-pattern signals','clinician_review','high_risk'),
('pregnancy_declared','Pregnancy or lactation recorded or stated',
 'profiles.life_stage <> ''none'' or keyword match','refuse','high_risk'),
('minor','User is, or is asking on behalf of, someone under 18',
 'derived age from birth_date, or keyword match','refuse','high_risk'),
('medical_question','Diagnosis, medication or treatment question',
 'scope.ts MEDICAL keyword set','refuse','high_risk'),
('severe_symptom','Severe or urgent symptom described',
 'symptom keyword set','urgent_referral','high_risk'),
('rapid_weight_change','Major unexplained weight change',
 'weight_entries trend exceeding a safe rate','clinician_review','condition_aware'),
('critical_lab','Lab value flagged critical',
 'user_labs.abnormal_flag in (critical_low, critical_high)','urgent_referral','high_risk'),
('prompt_injection','Retrieved text or user input attempting to override policy',
 'scope.ts INJECTION set plus tool-output sanitisation','refuse','general_wellness')
on conflict (slug) do nothing;
