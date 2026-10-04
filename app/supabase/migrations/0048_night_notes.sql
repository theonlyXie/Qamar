-- The night sentence, and tomorrow as the wall.
--
-- The blueprint's night step: at 22:00 Su generates tomorrow from today's log
-- and writes one sentence the person sees next morning. For Qamar+ the plan
-- is behind it; for the free tier the sentence is visible and the plan is
-- locked — paywall number four. The gateway's night job writes both (see
-- ai-gateway/index.ts, nightlyPlans); this file gives it a place to write the
-- sentence, two Cairo-time helpers, and makes the lock real in the database
-- rather than only in the app.

create table if not exists public.night_notes (
  user_id uuid not null references auth.users (id) on delete cascade,
  -- The day the sentence is about: tomorrow when written, today when read.
  day date not null,
  sentence_ar text not null,
  sentence_en text not null,
  plan_kcal int not null,
  -- What was logged the day before, in Cairo time, when the sentence was written.
  today_kcal int not null,
  created_at timestamptz not null default now(),
  primary key (user_id, day)
);
alter table public.night_notes enable row level security;
drop policy if exists night_notes_select_own on public.night_notes;
create policy night_notes_select_own on public.night_notes
  for select using (auth.uid() = user_id);
-- Written by the gateway with the service role only.
revoke insert, update, delete on public.night_notes from anon, authenticated;

-- Tomorrow's plan belongs to Qamar+. The free tier keeps today's and past
-- plans (they were built on request) and never sees a future row; a member
-- sees them all. The gateway enforces the same rule on /plan/generate, and
-- the phone never wrote plans itself — the gateway does, with the service
-- role — so the write policies go.
drop policy if exists meal_plans_select_own on public.meal_plans;
create policy meal_plans_select_own on public.meal_plans
  for select using (
    auth.uid() = user_id
    and (plan_date <= public.qamar_cairo_today() or public.qamar_is_plus(user_id))
  );
drop policy if exists meal_plans_insert_own on public.meal_plans;
drop policy if exists meal_plans_update_own on public.meal_plans;
revoke insert, update, delete on public.meal_plans from anon, authenticated;
grant execute on function public.qamar_is_plus(uuid) to service_role;

-- Calories logged on one Cairo day — the "today" the sentence compares with.
create or replace function public.qamar_day_kcal(p_user_id uuid, p_day date)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(kcal), 0)::int
  from public.meal_logs
  where user_id = p_user_id
    and (timezone('Africa/Cairo', logged_at))::date = p_day;
$$;
revoke all on function public.qamar_day_kcal(uuid, date) from public, anon, authenticated;
grant execute on function public.qamar_day_kcal(uuid, date) to service_role;

-- Everyone who logged a meal today (Cairo): the night job's free-tier audience.
create or replace function public.qamar_active_today()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select distinct user_id
  from public.meal_logs
  where (timezone('Africa/Cairo', logged_at))::date = public.qamar_cairo_today();
$$;
revoke all on function public.qamar_active_today() from public, anon, authenticated;
grant execute on function public.qamar_active_today() to service_role;
