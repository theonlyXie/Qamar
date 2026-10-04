-- No quest on the general-guidance route (O2, seat 4's review of 75a0730).
--
-- Someone who answered pregnancy, breastfeeding or a condition under care is
-- deliberately given no target: a safety decision. A quest reads the day
-- against a target and a plan ("Logged early, I can still adjust dinner";
-- "Protein is today's gap so far"), and there is neither. So a day has a
-- quest only when the person has a current target and profiles.life_stage
-- is 'none', and still not on a fasting day (0063). A chronic condition has
-- no column on the server; it has no target row either (the consultation
-- saves a target only on the target route), so it has no quest. The phone
-- hides the quest on that route too (AppState.questDue).
--
-- qamar_quest_for and qamar_pay_quest_if_met are 0063's, with its fasting
-- check widened to this one.

create or replace function public.qamar_quest_eligible(p_user_id uuid, p_day date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not public.qamar_fasting_on(p_user_id, p_day)
     and not exists (select 1 from public.profiles p where p.user_id = p_user_id and p.life_stage <> 'none')
     and exists (
       select 1 from public.targets t
       where t.user_id = p_user_id and (t.valid_to is null or t.valid_to > now())
     );
$$;
revoke all on function public.qamar_quest_eligible(uuid, date) from public, anon, authenticated;

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
  -- No quest where there is no target to read the day against, and none on
  -- a fasting day (0063), done or open.
  if not public.qamar_quest_eligible(p_user_id, v_day) then
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
  -- A quest chosen before the day stopped being eligible (the fast switched
  -- on, or a safety answer given) is not paid.
  if not public.qamar_quest_eligible(p_user_id, v_day) then
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
