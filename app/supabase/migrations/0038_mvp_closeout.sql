-- Qamar MVP closeout: server Su awards, current Plus helper, daily quest,
-- reminders, reports, analytics, profile cosmetics, account wipe.
--
-- Migration filenames 0033–0037 were renamed so each version number is unique.
-- `IF NOT EXISTS` / `create or replace` keep this file safe if an older
-- duplicate name already applied the same objects on a live database.

-- ---------------------------------------------------------------------------
-- Profile flags (calm mode, orb cosmetic, achievements, insight unlocks)
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists calm_mode boolean not null default false;

alter table public.profiles
  add column if not exists orb_cosmetic text not null default 'default';

alter table public.profiles
  add column if not exists achievements text[] not null default '{}';

alter table public.profiles
  add column if not exists insight_unlocks integer not null default 0;

-- ---------------------------------------------------------------------------
-- Reminders (local times as HH:MM; client also stores locally)
-- ---------------------------------------------------------------------------
create table if not exists public.user_reminders (
  user_id uuid primary key references auth.users (id) on delete cascade,
  breakfast_hhmm text not null default '08:00',
  lunch_hhmm text not null default '13:00',
  dinner_hhmm text not null default '19:00',
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.user_reminders enable row level security;

drop policy if exists "user_reminders_own" on public.user_reminders;
create policy "user_reminders_own"
  on public.user_reminders for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Food / advice / app reports (no PII required)
-- ---------------------------------------------------------------------------
create table if not exists public.food_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('food', 'advice', 'app')),
  detail text not null check (char_length(detail) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists food_reports_user_idx
  on public.food_reports (user_id, created_at desc);

alter table public.food_reports enable row level security;

drop policy if exists "food_reports_insert_own" on public.food_reports;
create policy "food_reports_insert_own"
  on public.food_reports for insert
  with check (auth.uid() = user_id);

drop policy if exists "food_reports_select_own" on public.food_reports;
create policy "food_reports_select_own"
  on public.food_reports for select
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Content-free analytics (event name only — never food, chat, or photos)
-- ---------------------------------------------------------------------------
create table if not exists public.app_events (
  id bigserial primary key,
  user_id uuid references auth.users (id) on delete set null,
  name text not null check (char_length(name) between 1 and 80),
  created_at timestamptz not null default now()
);

create index if not exists app_events_created_idx
  on public.app_events (created_at desc);

alter table public.app_events enable row level security;

drop policy if exists "app_events_insert_own" on public.app_events;
create policy "app_events_insert_own"
  on public.app_events for insert
  with check (auth.uid() = user_id);

-- No select for authenticated users.

-- ---------------------------------------------------------------------------
-- Founder ops views (no secrets). Grant to service_role only.
-- ---------------------------------------------------------------------------
create or replace view public.ops_daily_signups
with (security_invoker = true) as
select date_trunc('day', created_at at time zone 'Africa/Cairo')::date as cairo_day,
       count(*)::int as signups
from public.profiles
group by 1
order by 1 desc;

create or replace view public.ops_plus_subscribers
with (security_invoker = true) as
select count(*) filter (where status = 'active' and period_end > now())::int as active_plus,
       count(*)::int as entitlement_rows
from public.entitlements;

revoke all on public.ops_daily_signups from public, anon, authenticated;
revoke all on public.ops_plus_subscribers from public, anon, authenticated;
grant select on public.ops_daily_signups to service_role;
grant select on public.ops_plus_subscribers to service_role;

-- ---------------------------------------------------------------------------
-- Plus entitlement helper — current period, fail-closed
-- (qamar_has_paid_plus is "ever paid"; this is "Plus is on right now")
-- ---------------------------------------------------------------------------
create or replace function public.qamar_plus_active(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.entitlements e
    where e.user_id = p_user_id
      and e.status = 'active'
      and e.period_end > now()
  );
$$;

revoke all on function public.qamar_plus_active(uuid) from public;
grant execute on function public.qamar_plus_active(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Daily quest: 250 Su, once per Cairo day
-- ---------------------------------------------------------------------------
create or replace function public.qamar_complete_daily_quest()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  day date;
  idem text;
  already boolean;
  meal_count int;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  day := public.qamar_cairo_today();
  idem := 'quest:' || uid::text || ':' || day::text;

  select exists (
    select 1 from public.su_point_ledger
    where user_id = uid and idempotency_key = idem
  ) into already;
  if already then
    return jsonb_build_object(
      'credited', false,
      'cairo_day', day,
      'amount', 250
    );
  end if;

  -- The quest is "log a meal today", not a button that mints points.
  select count(*) into meal_count
  from public.meal_logs
  where user_id = uid
    and (timezone('Africa/Cairo', logged_at))::date = day;
  if meal_count < 1 then
    raise exception 'log a meal today first';
  end if;

  perform public.qamar_wallet_credit_internal(uid, 250, 'daily_quest', idem);
  return jsonb_build_object(
    'credited', true,
    'cairo_day', day,
    'amount', 250
  );
end;
$$;

revoke all on function public.qamar_complete_daily_quest() from public;
grant execute on function public.qamar_complete_daily_quest() to authenticated;

-- ---------------------------------------------------------------------------
-- Server Su awards: first meal 500, later meals 100, first target 1000
-- ---------------------------------------------------------------------------
create or replace function public.qamar_on_meal_log_award()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meal_count int;
begin
  select count(*) into meal_count
  from public.meal_logs
  where user_id = new.user_id;

  if meal_count = 1 then
    perform public.qamar_wallet_credit_internal(
      new.user_id,
      500,
      'first_meal',
      'first_meal:' || new.user_id::text
    );
  else
    perform public.qamar_wallet_credit_internal(
      new.user_id,
      100,
      'meal_log',
      'meal:' || new.id::text
    );
  end if;
  return new;
exception
  when others then
    raise warning 'qamar_on_meal_log_award failed for %: %', new.user_id, sqlerrm;
    return new;
end;
$$;

drop trigger if exists trg_meal_log_award on public.meal_logs;
create trigger trg_meal_log_award
  after insert on public.meal_logs
  for each row
  execute function public.qamar_on_meal_log_award();

create or replace function public.qamar_on_first_target_award()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_count int;
begin
  select count(*) into target_count
  from public.targets
  where user_id = new.user_id;
  if target_count = 1 then
    perform public.qamar_wallet_credit_internal(
      new.user_id,
      1000,
      'onboarding',
      'onboarding:' || new.user_id::text
    );
  end if;
  return new;
exception
  when others then
    raise warning 'qamar_on_first_target_award failed for %: %', new.user_id, sqlerrm;
    return new;
end;
$$;

drop trigger if exists trg_first_target_award on public.targets;
create trigger trg_first_target_award
  after insert on public.targets
  for each row
  execute function public.qamar_on_first_target_award();

-- ---------------------------------------------------------------------------
-- Account wipe (cannot delete auth.users from SQL — client signs out after)
-- ---------------------------------------------------------------------------
create or replace function public.qamar_delete_my_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  delete from public.food_reports where user_id = uid;
  delete from public.user_reminders where user_id = uid;
  delete from public.app_events where user_id = uid;
  delete from public.wallet_redemptions where user_id = uid;
  delete from public.su_point_ledger where user_id = uid;
  delete from public.wallet_accounts where user_id = uid;
  delete from public.ai_usage_days where user_id = uid;
  delete from public.meal_logs where user_id = uid;
  delete from public.meal_drafts where user_id = uid;
  delete from public.weight_entries where user_id = uid;
  delete from public.water_logs where user_id = uid;
  delete from public.quests where user_id = uid;
  delete from public.targets where user_id = uid;

  update public.profile_facts set superseded_by = null where user_id = uid;
  delete from public.profile_facts where user_id = uid;
  delete from public.assessment_gaps where user_id = uid;
  delete from public.user_labs where user_id = uid;
  delete from public.user_medications where user_id = uid;
  delete from public.user_supplements where user_id = uid;
  delete from public.interaction_findings where user_id = uid;
  delete from public.meal_plans where user_id = uid;
  delete from public.ai_interactions where user_id = uid;

  delete from public.affiliate_ledger where user_id = uid;
  delete from public.affiliate_payouts where user_id = uid;
  delete from public.promo_codes where owner_user_id = uid;
  delete from public.billing_events
    where order_id in (select id from public.billing_orders where user_id = uid);
  delete from public.billing_orders where user_id = uid;
  delete from public.entitlements where user_id = uid;
  delete from public.consents where user_id = uid;
  delete from public.profiles where user_id = uid;
end;
$$;

revoke all on function public.qamar_delete_my_data() from public;
grant execute on function public.qamar_delete_my_data() to authenticated;

drop policy if exists profile_facts_delete_own on public.profile_facts;
create policy profile_facts_delete_own
  on public.profile_facts for delete
  using (auth.uid() = user_id);
