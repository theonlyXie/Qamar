-- The daily quest is real, or it is absent (O2).
--
-- Until now the quest was one hardcoded line on the phone, "Log lunch before
-- 4pm", and qamar_complete_quest paid 250 Su to whoever tapped Accept,
-- whether or not lunch was ever logged. Now:
--   - the server chooses one quest per Cairo day from what the day actually
--     lacks, and stores it in daily_quests;
--   - it is paid inside the existing earn triggers, by the row that satisfies
--     it (a meal, a glass of water), under the same key as before,
--     quest:<user>:<day>, so it still pays at most once a day;
--   - no tap pays: qamar_complete_quest loses its authenticated grant.
-- The amount stays 250 (su_economy_config.daily_quest).
--
-- The kinds only ever ADD something to the day. A kind that restricts (stay
-- under, skip a meal, a deficit) must never be added. app/test/quest_test.dart
-- reads this file's enum and fails if the Dart and SQL kinds drift, or if a
-- kind or its words restrict.
--   lunch_by_16     no lunch logged yet: log lunch before 16:00 Cairo, so
--                   dinner can still be adjusted.
--   protein_dinner  under half the day's protein target by 17:00: a dinner
--                   with 20 g of protein or more.
--   water_6         under 1.5 litres today: six glasses (1,500 ml, any unit).
-- If a quest expires unpaid, the next one the day lacks is chosen. "Not
-- today" puts the quest away for the rest of the day. A day with no real gap
-- has no quest.

do $$
begin
  create type public.quest_kind as enum ('lunch_by_16', 'protein_dinner', 'water_6');
exception when duplicate_object then
  null;
end;
$$;

create table if not exists public.daily_quests (
  user_id uuid not null references auth.users (id) on delete cascade,
  -- The Cairo date it belongs to.
  day date not null,
  kind public.quest_kind not null,
  chosen_at timestamptz not null default now(),
  expires_at timestamptz not null,
  paid_at timestamptz,
  skipped_at timestamptz,
  primary key (user_id, day, kind)
);
alter table public.daily_quests enable row level security;
drop policy if exists daily_quests_select_own on public.daily_quests;
create policy daily_quests_select_own on public.daily_quests
  for select using (auth.uid() = user_id);
revoke insert, update, delete on public.daily_quests from anon, authenticated;

-- A Cairo wall-clock time on a Cairo date, as an instant.
create or replace function public.qamar_cairo_at(p_day date, p_hour int)
returns timestamptz
language sql
immutable
set search_path = public
as $$
  select (p_day::timestamp + make_interval(hours => p_hour)) at time zone 'Africa/Cairo';
$$;
revoke all on function public.qamar_cairo_at(date, int) from public, anon, authenticated;

-- Whether [q] is satisfied by what is logged: rows written between its
-- choosing and its expiry, whenever they reached the server (an offline log
-- replayed later still counts for its own time).
create or replace function public.qamar_quest_met(p_user_id uuid, p_kind public.quest_kind, p_day date, p_from timestamptz, p_to timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case p_kind
    when 'lunch_by_16' then exists (
      select 1 from public.meal_logs m
      where m.user_id = p_user_id
        and m.logged_at >= p_from and m.logged_at <= p_to
        and m.logged_at >= public.qamar_cairo_at(p_day, 11)
        and m.logged_at < public.qamar_cairo_at(p_day, 16))
    when 'protein_dinner' then exists (
      select 1 from public.meal_logs m
      where m.user_id = p_user_id
        and m.logged_at >= p_from and m.logged_at <= p_to
        and m.logged_at >= public.qamar_cairo_at(p_day, 17)
        and m.protein_g >= 20)
    when 'water_6' then (
      select coalesce(sum(w.amount_ml), 0) >= 1500 from public.water_logs w
      where w.user_id = p_user_id
        and (timezone('Africa/Cairo', w.logged_at))::date = p_day
        and w.logged_at <= p_to)
  end;
$$;
revoke all on function public.qamar_quest_met(uuid, public.quest_kind, date, timestamptz, timestamptz) from public, anon, authenticated;

-- Today's quest for [p_user_id] at [p_now]: the one paid today (done), else
-- the one running, else a new one chosen from what the day lacks, else none.
-- Put away with "not today", there is none for the rest of the day.
-- Internal: the clock is a parameter so the choice can be tested.
create or replace function public.qamar_quest_for(p_user_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := (timezone('Africa/Cairo', p_now))::date;
  v_hour int := extract(hour from timezone('Africa/Cairo', p_now))::int;
  v_row public.daily_quests;
  v_kind public.quest_kind;
  v_expires timestamptz;
  v_protein int;
  v_target int;
  v_water int;
begin
  select * into v_row from public.daily_quests
  where user_id = p_user_id and day = v_day and paid_at is not null
  limit 1;
  if found then
    return jsonb_build_object('day', v_day, 'kind', v_row.kind, 'expires_at', v_row.expires_at, 'done', true);
  end if;

  if exists (select 1 from public.daily_quests where user_id = p_user_id and day = v_day and skipped_at is not null) then
    return null;
  end if;

  select * into v_row from public.daily_quests
  where user_id = p_user_id and day = v_day and paid_at is null and skipped_at is null and expires_at > p_now
  order by chosen_at desc
  limit 1;
  if found then
    return jsonb_build_object('day', v_day, 'kind', v_row.kind, 'expires_at', v_row.expires_at, 'done', false);
  end if;

  -- What the day lacks, in the order the day runs. A kind already used
  -- today is not asked again.
  if v_hour < 15
     and not exists (select 1 from public.daily_quests where user_id = p_user_id and day = v_day and kind = 'lunch_by_16')
     and not exists (
       select 1 from public.meal_logs m
       where m.user_id = p_user_id
         and m.logged_at >= public.qamar_cairo_at(v_day, 11)
         and m.logged_at < public.qamar_cairo_at(v_day, 17)) then
    v_kind := 'lunch_by_16';
    v_expires := public.qamar_cairo_at(v_day, 16);
  end if;

  if v_kind is null and v_hour >= 17 and v_hour < 22
     and not exists (select 1 from public.daily_quests where user_id = p_user_id and day = v_day and kind = 'protein_dinner') then
    select t.protein_g into v_target from public.targets t
    where t.user_id = p_user_id and (t.valid_to is null or t.valid_to > p_now)
    order by t.confirmed_at desc
    limit 1;
    select coalesce(sum(m.protein_g), 0) into v_protein from public.meal_logs m
    where m.user_id = p_user_id and (timezone('Africa/Cairo', m.logged_at))::date = v_day;
    if v_target is not null and v_target > 0 and v_protein * 2 < v_target then
      v_kind := 'protein_dinner';
      v_expires := public.qamar_cairo_at(v_day, 24);
    end if;
  end if;

  if v_kind is null and v_hour < 21
     and not exists (select 1 from public.daily_quests where user_id = p_user_id and day = v_day and kind = 'water_6') then
    select coalesce(sum(w.amount_ml), 0) into v_water from public.water_logs w
    where w.user_id = p_user_id and (timezone('Africa/Cairo', w.logged_at))::date = v_day;
    if v_water < 1500 then
      v_kind := 'water_6';
      v_expires := public.qamar_cairo_at(v_day, 24);
    end if;
  end if;

  if v_kind is null then
    return null;
  end if;
  insert into public.daily_quests (user_id, day, kind, chosen_at, expires_at)
  values (p_user_id, v_day, v_kind, p_now, v_expires)
  on conflict do nothing;
  return jsonb_build_object('day', v_day, 'kind', v_kind, 'expires_at', v_expires, 'done', false);
end;
$$;
revoke all on function public.qamar_quest_for(uuid, timestamptz) from public, anon, authenticated;

-- The phone's read: today's quest for whoever is signed in.
create or replace function public.qamar_today_quest()
returns jsonb
language sql
volatile
security definer
set search_path = public
as $$
  select case when auth.uid() is null then null else public.qamar_quest_for(auth.uid(), now()) end;
$$;
revoke all on function public.qamar_today_quest() from public, anon;
grant execute on function public.qamar_today_quest() to authenticated;

-- "Not today": the quest is put away until tomorrow. Nothing is paid.
create or replace function public.qamar_skip_quest()
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update public.daily_quests
  set skipped_at = now()
  where user_id = auth.uid()
    and day = public.qamar_cairo_today()
    and paid_at is null
    and skipped_at is null;
$$;
revoke all on function public.qamar_skip_quest() from public, anon;
grant execute on function public.qamar_skip_quest() to authenticated;

-- Pays the quest of the Cairo day of [p_at] if what is logged now satisfies
-- it. At most once a day: the ledger key is the one the old tap used. Never
-- throws: a quest must not stop a meal or a glass from being saved.
create or replace function public.qamar_pay_quest_if_met(p_user_id uuid, p_at timestamptz)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := (timezone('Africa/Cairo', p_at))::date;
  v_row public.daily_quests;
  v_paid int := 0;
begin
  for v_row in
    select * from public.daily_quests
    where user_id = p_user_id and day = v_day and paid_at is null and skipped_at is null
    order by chosen_at
  loop
    if public.qamar_quest_met(p_user_id, v_row.kind, v_day, v_row.chosen_at, v_row.expires_at) then
      v_paid := public.qamar_su_earn(
        p_user_id,
        coalesce(public.qamar_su_value('daily_quest'), 250),
        'daily_quest',
        'quest:' || p_user_id::text || ':' || v_day::text
      );
      update public.daily_quests set paid_at = now()
      where user_id = p_user_id and day = v_day and kind = v_row.kind;
      insert into public.quest_completions (user_id, day, quest)
      values (p_user_id, v_day, v_row.kind::text)
      on conflict do nothing;
      exit;
    end if;
  end loop;
  return v_paid;
exception
  when others then
    raise warning 'qamar_pay_quest_if_met failed for %: %', p_user_id, sqlerrm;
    return 0;
end;
$$;
revoke all on function public.qamar_pay_quest_if_met(uuid, timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- The earn triggers of 0046, unchanged but for the quest: the row that
-- satisfies it pays it.
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

  perform public.qamar_pay_quest_if_met(new.user_id, new.logged_at);
  return new;
exception
  -- Points must never stop a meal being saved.
  when others then
    raise warning 'qamar_earn_on_meal failed for %: %', new.user_id, sqlerrm;
    return new;
end;
$$;
revoke all on function public.qamar_earn_on_meal() from public, anon, authenticated;

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
  if v_today <= coalesce(public.qamar_su_value('water_sips_paid_daily'), 8) then
    v_amount := case
      when public.qamar_is_plus(new.user_id) then coalesce(public.qamar_su_value('water_sip'), 10)
      else coalesce(public.qamar_su_value('water_sip_lite'), 5)
    end;
    perform public.qamar_su_earn(new.user_id, v_amount, 'water', 'water:' || new.id::text);
  end if;
  -- The sixth glass pays the water quest even past the paid glasses.
  perform public.qamar_pay_quest_if_met(new.user_id, new.logged_at);
  return new;
exception
  when others then
    raise warning 'qamar_earn_on_water failed for %: %', new.user_id, sqlerrm;
    return new;
end;
$$;
revoke all on function public.qamar_earn_on_water() from public, anon, authenticated;

-- No tap pays the quest any more. The function stays for the service role
-- (an operator correcting a day by hand), not for the phone.
revoke execute on function public.qamar_complete_quest(uuid) from authenticated;
