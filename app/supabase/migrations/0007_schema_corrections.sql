-- Four corrections to the existing tables, before the knowledge-base work
-- starts writing data through them.
--
-- None of these add a concept. They fix places where the current shape either
-- destroys information or cannot express something the safety rules already
-- depend on. They come first because every one of them corrupts data that the
-- later migrations read, and a wrong number that is already stored is much
-- more expensive than a column that was never right.

-- ---------------------------------------------------------------------
-- 1. Weight and body fat could not hold a decimal
-- ---------------------------------------------------------------------
--
-- weight_kg and body_fat_pct were integer. A person who weighs 73.5 kg could
-- not be recorded, and 22.4% body fat rounded to 22. weight_entries.value_kg
-- is already numeric, so the profile and the time series disagreed about the
-- same quantity.
--
-- This is not cosmetic. The smoothed weight trend, its rate of change, and the
-- personal energy model that will read both are exactly the things that need
-- sub-kilogram resolution: a whole kilogram is larger than the weekly signal
-- they are trying to separate from daily water noise.
--
-- numeric(5,2) and numeric(4,1) comfortably cover the existing ranges, which
-- are re-applied unchanged. The integer values already stored convert exactly.

alter table public.profiles drop constraint if exists profiles_weight_kg_check;
alter table public.profiles alter column weight_kg type numeric(5,2);
alter table public.profiles add constraint profiles_weight_kg_check
  check (weight_kg >= 30 and weight_kg <= 250);

alter table public.profiles drop constraint if exists profiles_body_fat_pct_check;
alter table public.profiles alter column body_fat_pct type numeric(4,1);
alter table public.profiles add constraint profiles_body_fat_pct_check
  check (body_fat_pct >= 3 and body_fat_pct <= 70);

-- Height in whole centimetres is fine and stays integer.

-- ---------------------------------------------------------------------
-- 2. Body scans were being recorded as meal analyses
-- ---------------------------------------------------------------------
--
-- The gateway serves four routes but ai_interactions.kind allowed three, so
-- /scan/read logged itself as 'meal_analysis' with the question '[body scan]'.
-- Any question about how well the scan reader performs then required
-- string-matching a free-text column.

alter table public.ai_interactions drop constraint if exists ai_interactions_kind_check;
alter table public.ai_interactions add constraint ai_interactions_kind_check
  check (kind in ('chat', 'meal_analysis', 'plan', 'body_scan'));

-- Reclassify anything already logged under the old workaround.
update public.ai_interactions
   set kind = 'body_scan'
 where kind = 'meal_analysis'
   and question = '[body scan]';

-- ---------------------------------------------------------------------
-- 3. Pregnancy and lactation had no column
-- ---------------------------------------------------------------------
--
-- scope.ts hard-refuses both, but nothing recorded either, so the refusal was
-- a keyword match against the question and nothing more: a user who told the
-- app they were pregnant during onboarding and then asked a plainly worded
-- calorie question got a normal answer, computed by equations that assume a
-- non-pregnant adult.
--
-- Recording it fixes both halves — the refusal becomes a fact lookup rather
-- than a regex, and the requirement engine can see a life stage its equations
-- are not valid for.
--
-- Deliberately NOT wired to eligibility_status. Those values block an account;
-- this scope refuses a topic. Someone who is pregnant is still entitled to the
-- rest of the app, and conflating the two would lock them out of it.

alter table public.profiles add column if not exists life_stage text not null default 'none';

alter table public.profiles drop constraint if exists profiles_life_stage_check;
alter table public.profiles add constraint profiles_life_stage_check
  check (life_stage in ('none', 'pregnant', 'lactating'));

comment on column public.profiles.life_stage is
  'Pregnancy/lactation status. Out of scope for consumer wellness: the gateway '
  'must refuse nutrition targets and plans when this is not ''none'', and the '
  'requirement engine must not compute EER for these life stages. Pediatric and '
  'older-adult status derive from birth_date and are not stored here.';

-- ---------------------------------------------------------------------
-- 4. Allergies and dislikes were the same untyped array
-- ---------------------------------------------------------------------
--
-- profiles.food_exclusions is text[]. It carries the constraint that must
-- never be violated by a meal plan, with no severity, no provenance, and no
-- way to tell an anaphylaxis risk from someone not liking okra. The model
-- prompt says "an allergy is not a preference" while being handed a list that
-- cannot tell it which is which.
--
-- The optimizer that arrives later needs this split at the schema level: an
-- allergy is a hard constraint that makes a plan infeasible, a dislike is a
-- soft objective that costs it points.

create table if not exists public.food_restrictions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Free text until the food graph lands, then this gains a qamar_food_id.
  label text not null,
  kind text not null check (kind in ('allergy', 'intolerance', 'dislike', 'religious', 'medical')),
  -- Only meaningful for allergy and intolerance. NULL means not yet
  -- established, which consumers of this table must treat as the most severe
  -- case, never as absent.
  severity text check (severity in ('anaphylaxis', 'severe', 'moderate', 'mild')),
  source text not null default 'self_reported',
  note text,
  created_at timestamptz not null default now(),
  unique (user_id, label, kind)
);

create index if not exists food_restrictions_user_idx
  on public.food_restrictions (user_id, kind);

alter table public.food_restrictions enable row level security;
drop policy if exists food_restrictions_select_own on public.food_restrictions;
create policy food_restrictions_select_own on public.food_restrictions
  for select using (auth.uid() = user_id);
drop policy if exists food_restrictions_insert_own on public.food_restrictions;
create policy food_restrictions_insert_own on public.food_restrictions
  for insert with check (auth.uid() = user_id);
drop policy if exists food_restrictions_update_own on public.food_restrictions;
create policy food_restrictions_update_own on public.food_restrictions
  for update using (auth.uid() = user_id);
drop policy if exists food_restrictions_delete_own on public.food_restrictions;
create policy food_restrictions_delete_own on public.food_restrictions
  for delete using (auth.uid() = user_id);

-- Migrate what is already there. Everything becomes an allergy of unknown
-- severity, because that is how the app has been treating the list — the
-- prompt forbids suggesting any of it — and because guessing downward on a
-- safety constraint is the one direction that can hurt somebody.
insert into public.food_restrictions (user_id, label, kind, severity, source)
select p.user_id, trim(x), 'allergy', null, 'migrated_from_food_exclusions'
from public.profiles p
cross join lateral unnest(coalesce(p.food_exclusions, '{}'::text[])) as x
where trim(x) <> ''
on conflict (user_id, label, kind) do nothing;

-- food_exclusions is deliberately left in place. The Flutter app and the
-- gateway both read it, and dropping it would break the running app for a
-- migration that is meant to be safe. It becomes the denormalized projection
-- of this table; the readers move over, and it is dropped once nothing reads
-- it.
comment on column public.profiles.food_exclusions is
  'DEPRECATED, retained so existing readers keep working. food_restrictions is '
  'the source of truth: it separates allergy from dislike and carries severity. '
  'New writers must write both until the gateway and app are migrated.';
