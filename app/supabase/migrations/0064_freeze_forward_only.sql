-- A streak freeze covers the day it is redeemed and later days, never a day
-- already missed (O4, seat 4).
--
-- 0042 let a token rescue the day before it was bought ("a token bought today
-- can rescue yesterday": redeemed_on - 1 <= v_cursor). That is the "restore
-- my streak" purchase the blueprint forbids (line 1267: "Streak freeze costs
-- points; there is no 'restore my streak' purchase"), and it put the price
-- of a freeze in front of someone on the morning after a break, when losing
-- the run hurts most. A freeze is insurance, bought before the day it covers:
-- the one it is redeemed on (today never breaks a run before it ends, so a
-- token bought on a day with no meal yet still covers that day) or a later one.
--
-- Only the one comparison changes; the rest of qamar_streak_snapshot is 0042's
-- as written. Days a token has already covered keep their used_on and still
-- count, so no run anyone already has is taken away by this. The grant is
-- re-stated, and anon loses the execute that Supabase's default privileges
-- gave it: 0042 revoked only public, and a guest account signs in as
-- authenticated, so nothing that reads a streak needs anon. Idempotent.

create or replace function public.qamar_streak_snapshot(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := public.qamar_cairo_today();
  v_cursor date;
  v_current int := 0;
  v_best int := 0;
  v_run int := 0;
  v_prev date;
  v_day date;
  v_today_counted boolean;
  v_freeze uuid;
  v_frozen date[] := '{}';
  v_available int;
begin
  perform public.qamar_assert_wallet_owner(p_user_id);

  create temp table if not exists _qamar_days (d date primary key) on commit drop;
  delete from _qamar_days;
  insert into _qamar_days
  select distinct (timezone('Africa/Cairo', logged_at))::date
  from public.meal_logs
  where user_id = p_user_id
  on conflict do nothing;
  insert into _qamar_days
  select used_on from public.streak_freezes
  where user_id = p_user_id and used_on is not null
  on conflict do nothing;

  v_today_counted := exists (select 1 from _qamar_days where d = v_today);
  v_cursor := case when v_today_counted then v_today else v_today - 1 end;

  loop
    if exists (select 1 from _qamar_days where d = v_cursor) then
      v_current := v_current + 1;
      v_cursor := v_cursor - 1;
      continue;
    end if;
    -- An empty day: only a gap between logged days is worth a freeze, and
    -- only while the run is alive (v_current > 0 or it is yesterday).
    exit when v_cursor < v_today - 1 and v_current = 0;
    -- Forward only: a token covers the day it was redeemed on or a later
    -- one, never a day already over when it was bought (0064).
    select id into v_freeze
    from public.streak_freezes
    where user_id = p_user_id
      and used_on is null
      and redeemed_on <= v_cursor
    order by redeemed_on
    limit 1;
    exit when v_freeze is null;
    -- A freeze only bridges to a logged day; it never pads a run that has
    -- already ended.
    exit when not exists (select 1 from _qamar_days where d = v_cursor - 1);
    update public.streak_freezes set used_on = v_cursor where id = v_freeze;
    insert into _qamar_days values (v_cursor) on conflict do nothing;
    v_frozen := array_append(v_frozen, v_cursor);
    v_current := v_current + 1;
    v_cursor := v_cursor - 1;
  end loop;

  -- Best run over all data.
  for v_day in select d from _qamar_days order by d loop
    if v_prev is not null and v_day = v_prev + 1 then
      v_run := v_run + 1;
    else
      v_run := 1;
    end if;
    v_prev := v_day;
    if v_run > v_best then v_best := v_run; end if;
  end loop;
  if v_current > v_best then v_best := v_current; end if;

  select count(*) into v_available from public.streak_freezes
  where user_id = p_user_id and used_on is null;

  select coalesce(array_agg(used_on order by used_on), '{}') into v_frozen
  from public.streak_freezes
  where user_id = p_user_id and used_on is not null and used_on >= v_today - 60;

  return jsonb_build_object(
    'current', v_current,
    'best', v_best,
    'today_counted', v_today_counted,
    'freezes_available', v_available,
    'frozen_days', to_jsonb(v_frozen)
  );
end;
$$;

revoke all on function public.qamar_streak_snapshot(uuid) from public, anon;
grant execute on function public.qamar_streak_snapshot(uuid) to authenticated;
