-- Su Points are earned on the server, or they are not earned.
--
-- Until now the only server-side credit was the signup bonus. Meals, the
-- daily quest and onboarding were credited on the phone, and the next
-- hydrate replaced that number with the ledger's — so a backed user watched
-- every point they earned disappear. The blueprint's rule is "Qamar posts
-- earn events, never mints": here the events are the rows people already
-- write (a meal, a glass of water) and two small RPCs (the quest, the
-- onboarding bonus), and the amounts live in one config table. The phone
-- keeps showing its optimistic number and re-reads the wallet right after,
-- so the two agree within a second.
--
-- Group caps, for now: a per-user daily ceiling on earned points. The
-- federated group ledger the blueprint describes posts to this later.

create table if not exists public.su_economy_config (
  key text primary key,
  value int not null
);

insert into public.su_economy_config (key, value) values
  ('meal_logged', 100),
  ('first_meal', 500),
  ('onboarding', 1000),
  ('daily_quest', 250),
  ('water_sip', 10),
  ('water_sip_lite', 5),          -- half rate on the free tier
  ('water_sips_paid_daily', 8),   -- a full water day; the ninth glass is just water
  ('streak_week', 100),           -- the ring completes at day 7 (the blueprint's weekly loop)
  ('daily_cap', 1500)             -- earned points per Cairo day, one-offs excluded
on conflict (key) do update set value = excluded.value;

alter table public.su_economy_config enable row level security;
drop policy if exists su_economy_config_read on public.su_economy_config;
create policy su_economy_config_read on public.su_economy_config for select using (true);
revoke insert, update, delete on public.su_economy_config from anon, authenticated;

create or replace function public.qamar_su_value(p_key text)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select value from public.su_economy_config where key = p_key;
$$;
revoke all on function public.qamar_su_value(text) from public, anon;
grant execute on function public.qamar_su_value(text) to authenticated, service_role;

-- Points earned so far this Cairo day, one-offs excluded.
create or replace function public.qamar_su_earned_today(p_user_id uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(delta), 0)::int
  from public.su_point_ledger
  where user_id = p_user_id
    and delta > 0
    and reason not in ('signup_bonus', 'onboarding')
    and (timezone('Africa/Cairo', created_at))::date = public.qamar_cairo_today();
$$;
revoke all on function public.qamar_su_earned_today(uuid) from public, anon, authenticated;

-- Credits up to the daily cap, idempotently. Returns what was credited.
-- Trusted: callable only from the functions below.
create or replace function public.qamar_su_earn(
  p_user_id uuid,
  p_amount int,
  p_reason text,
  p_key text
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room int := coalesce(public.qamar_su_value('daily_cap'), 1500) - public.qamar_su_earned_today(p_user_id);
  v_amount int := least(p_amount, greatest(v_room, 0));
begin
  if v_amount <= 0 then
    return 0;
  end if;
  if exists (select 1 from public.su_point_ledger where user_id = p_user_id and idempotency_key = p_key) then
    return 0;
  end if;
  perform public.qamar_wallet_credit_internal(p_user_id, v_amount, p_reason, p_key);
  return v_amount;
end;
$$;
revoke all on function public.qamar_su_earn(uuid, int, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- A logged meal earns. The first meal ever earns more. A streak that
-- reaches a multiple of seven today pays the week bonus once for that day.
create or replace function public.qamar_earn_on_meal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count bigint;
  v_snap jsonb;
  v_current int;
begin
  select count(*) into v_count from public.meal_logs where user_id = new.user_id;
  if v_count <= 1 then
    perform public.qamar_su_earn(new.user_id, coalesce(public.qamar_su_value('first_meal'), 500), 'first_meal', 'meal:' || new.id::text);
  else
    perform public.qamar_su_earn(new.user_id, coalesce(public.qamar_su_value('meal_logged'), 100), 'meal_logged', 'meal:' || new.id::text);
  end if;

  v_snap := public.qamar_streak_snapshot(new.user_id);
  v_current := coalesce((v_snap ->> 'current')::int, 0);
  if v_current > 0 and v_current % 7 = 0 and coalesce((v_snap ->> 'today_counted')::boolean, false) then
    perform public.qamar_su_earn(
      new.user_id,
      coalesce(public.qamar_su_value('streak_week'), 100),
      'streak_week',
      'streak:' || new.user_id::text || ':' || public.qamar_cairo_today()::text
    );
  end if;
  return new;
exception
  -- Points must never stop a meal being saved.
  when others then
    raise warning 'qamar_earn_on_meal failed for %: %', new.user_id, sqlerrm;
    return new;
end;
$$;
revoke all on function public.qamar_earn_on_meal() from public, anon, authenticated;

drop trigger if exists qamar_on_meal_logged on public.meal_logs;
create trigger qamar_on_meal_logged
  after insert on public.meal_logs
  for each row execute function public.qamar_earn_on_meal();

-- ---------------------------------------------------------------------
-- A glass of water earns, at half rate on the free tier, for the first
-- eight glasses of the day.
create or replace function public.qamar_earn_on_water()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today bigint;
  v_amount int;
begin
  select count(*) into v_today
  from public.water_logs
  where user_id = new.user_id
    and (timezone('Africa/Cairo', logged_at))::date = public.qamar_cairo_today();
  if v_today > coalesce(public.qamar_su_value('water_sips_paid_daily'), 8) then
    return new;
  end if;
  v_amount := case
    when public.qamar_is_plus(new.user_id) then coalesce(public.qamar_su_value('water_sip'), 10)
    else coalesce(public.qamar_su_value('water_sip_lite'), 5)
  end;
  perform public.qamar_su_earn(new.user_id, v_amount, 'water', 'water:' || new.id::text);
  return new;
exception
  when others then
    raise warning 'qamar_earn_on_water failed for %: %', new.user_id, sqlerrm;
    return new;
end;
$$;
revoke all on function public.qamar_earn_on_water() from public, anon, authenticated;

drop trigger if exists qamar_on_water_logged on public.water_logs;
create trigger qamar_on_water_logged
  after insert on public.water_logs
  for each row execute function public.qamar_earn_on_water();

-- ---------------------------------------------------------------------
-- The daily quest: once per Cairo day, whatever the phone says.
create table if not exists public.quest_completions (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  quest text not null default 'primary',
  created_at timestamptz not null default now(),
  primary key (user_id, day)
);
alter table public.quest_completions enable row level security;
drop policy if exists quest_completions_select_own on public.quest_completions;
create policy quest_completions_select_own on public.quest_completions
  for select using (auth.uid() = user_id);
revoke insert, update, delete on public.quest_completions from anon, authenticated;

create or replace function public.qamar_complete_quest(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := public.qamar_cairo_today();
  v_credited int := 0;
begin
  perform public.qamar_assert_wallet_owner(p_user_id);
  insert into public.quest_completions (user_id, day) values (p_user_id, v_day)
  on conflict do nothing;
  if found then
    v_credited := public.qamar_su_earn(
      p_user_id,
      coalesce(public.qamar_su_value('daily_quest'), 250),
      'daily_quest',
      'quest:' || p_user_id::text || ':' || v_day::text
    );
  end if;
  return jsonb_build_object('day', v_day, 'credited', v_credited);
end;
$$;
revoke all on function public.qamar_complete_quest(uuid) from public, anon;
grant execute on function public.qamar_complete_quest(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- Finishing onboarding: once per account, outside the daily cap.
create or replace function public.qamar_grant_onboarding(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := 'onboarding_' || p_user_id::text;
  v_amount int := coalesce(public.qamar_su_value('onboarding'), 1000);
begin
  perform public.qamar_assert_wallet_owner(p_user_id);
  if exists (select 1 from public.su_point_ledger where user_id = p_user_id and idempotency_key = v_key) then
    return jsonb_build_object('credited', 0);
  end if;
  perform public.qamar_wallet_credit_internal(p_user_id, v_amount, 'onboarding', v_key);
  return jsonb_build_object('credited', v_amount);
end;
$$;
revoke all on function public.qamar_grant_onboarding(uuid) from public, anon;
grant execute on function public.qamar_grant_onboarding(uuid) to authenticated, service_role;
