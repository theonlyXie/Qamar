-- The quest on a fasting day, and what it pays within the day's cap (O2,
-- seat 4's review of 0061). A new migration, not an edit to 0061, so the
-- review reads as its own diff.
--
-- 1. No quest on a fasting day. 0061 never read the fasting mode, so in
--    Ramadan someone fasting with no meal logged by 15:00 was offered "Log
--    lunch before 4pm" and 250 Su: currency for eating in daylight, against
--    the mode they chose. Now, with fasting_mode 'ramadan' and today inside
--    a season's starts_on..ends_on (app_seasons, 0050), nothing is chosen,
--    and a quest chosen before the fast was switched on is not paid.
-- 2. The amount is true. qamar_su_earn credits within the day's cap, so on a
--    day already at 1,500 a met quest was marked paid with 0 credited, while
--    the card said "+250". The answer now carries what it would pay today
--    (pays) and, once done, what it did credit (credited). The card shows
--    those numbers and no coin when they are 0.
-- qamar_quest_met is unchanged, and it must never gain a kcal condition or
-- an upper bound on what is eaten: app/test/quest_test.dart reads its latest
-- definition and fails if it does.

alter table public.daily_quests add column if not exists credited int;

-- Fasting today: the Ramadan mode is on and the day is inside a season.
create or replace function public.qamar_fasting_on(p_user_id uuid, p_day date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.profiles p where p.user_id = p_user_id and p.fasting_mode = 'ramadan')
     and exists (select 1 from public.app_seasons s where p_day between s.starts_on and s.ends_on);
$$;
revoke all on function public.qamar_fasting_on(uuid, date) from public, anon, authenticated;

-- What a quest met now would credit: the quest's amount, within the room the
-- day's cap has left.
create or replace function public.qamar_quest_pays(p_user_id uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select least(
    coalesce(public.qamar_su_value('daily_quest'), 250),
    greatest(coalesce(public.qamar_su_value('daily_cap'), 1500) - public.qamar_su_earned_today(p_user_id), 0)
  );
$$;
revoke all on function public.qamar_quest_pays(uuid) from public, anon, authenticated;

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
  -- A fasting day has no quest, done or open.
  if public.qamar_fasting_on(p_user_id, v_day) then
    return null;
  end if;

  select * into v_row from public.daily_quests
  where user_id = p_user_id and day = v_day and paid_at is not null
  limit 1;
  if found then
    return jsonb_build_object('day', v_day, 'kind', v_row.kind, 'expires_at', v_row.expires_at, 'done', true,
      'credited', coalesce(v_row.credited, 0));
  end if;

  if exists (select 1 from public.daily_quests where user_id = p_user_id and day = v_day and skipped_at is not null) then
    return null;
  end if;

  select * into v_row from public.daily_quests
  where user_id = p_user_id and day = v_day and paid_at is null and skipped_at is null and expires_at > p_now
  order by chosen_at desc
  limit 1;
  if found then
    return jsonb_build_object('day', v_day, 'kind', v_row.kind, 'expires_at', v_row.expires_at, 'done', false,
      'pays', public.qamar_quest_pays(p_user_id));
  end if;

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
  return jsonb_build_object('day', v_day, 'kind', v_kind, 'expires_at', v_expires, 'done', false,
    'pays', public.qamar_quest_pays(p_user_id));
end;
$$;
revoke all on function public.qamar_quest_for(uuid, timestamptz) from public, anon, authenticated;

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
  -- A quest chosen before the fast was switched on is not paid during it.
  if public.qamar_fasting_on(p_user_id, v_day) then
    return 0;
  end if;
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
      update public.daily_quests set paid_at = now(), credited = v_paid
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
