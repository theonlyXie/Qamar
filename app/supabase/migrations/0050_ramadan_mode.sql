-- Ramadan as a product mode (the blueprint's acquisition loop).
--
-- "Ramadan mode free for everyone → suhoor and iftar plans, hydration windows
-- → 30-day Ramadan log: 500 points → Eid report: what changed in 30 days →
-- keep the plan going? standard price."
--
-- Three things live here: the season's dates (a moon sighting can move them
-- a day, so the operator corrects this row rather than shipping an app
-- update), the fasting switch on the profile (the night job reads it and
-- writes a fasting day instead of three meals), and the month bonus.

alter table public.profiles add column if not exists fasting_mode text not null default 'none';
alter table public.profiles drop constraint if exists profiles_fasting_mode_check;
alter table public.profiles add constraint profiles_fasting_mode_check check (fasting_mode in ('none', 'ramadan'));

create table if not exists public.app_seasons (
  key text primary key,
  name_ar text not null,
  name_en text not null,
  starts_on date not null,
  ends_on date not null,
  eid_on date not null,
  check (ends_on >= starts_on and eid_on > ends_on)
);
alter table public.app_seasons enable row level security;
drop policy if exists app_seasons_read on public.app_seasons;
create policy app_seasons_read on public.app_seasons for select using (true);
revoke insert, update, delete on public.app_seasons from anon, authenticated;

-- Umm al-Qura's expectation for 1448: first fast Monday 8 February 2027,
-- 29 days, Eid al-Fitr Tuesday 9 March 2027. `do nothing` on purpose: once
-- the operator has corrected the dates after the sighting, a redeploy must
-- not put the estimate back.
insert into public.app_seasons (key, name_ar, name_en, starts_on, ends_on, eid_on) values
  ('ramadan_1448', 'رمضان 1448', 'Ramadan 1448', '2027-02-08', '2027-03-08', '2027-03-09')
on conflict (key) do nothing;

insert into public.su_economy_config (key, value) values ('season_full_log', 500)
on conflict (key) do update set value = excluded.value;

-- The season in view: from a week before the first fast to a week after Eid.
create or replace function public.qamar_current_season()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'key', s.key,
    'name_ar', s.name_ar,
    'name_en', s.name_en,
    'starts_on', s.starts_on,
    'ends_on', s.ends_on,
    'eid_on', s.eid_on
  )
  from public.app_seasons s
  where public.qamar_cairo_today() between s.starts_on - 7 and s.eid_on + 7
  order by s.starts_on
  limit 1;
$$;
revoke all on function public.qamar_current_season() from public;
grant execute on function public.qamar_current_season() to anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- The month bonus: a meal logged on every day of the season pays 500 once.
-- Everyone, fasting or not — the blueprint's line is "30-day Ramadan log",
-- and a person who ate and logged through the month kept the habit too.
create or replace function public.qamar_earn_on_meal_season()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := (timezone('Africa/Cairo', new.logged_at))::date;
  v_season public.app_seasons;
  v_logged int;
  v_key text;
begin
  select * into v_season from public.app_seasons s where v_day between s.starts_on and s.ends_on limit 1;
  if not found then
    return new;
  end if;
  v_key := 'season:' || v_season.key || ':' || new.user_id::text;
  if exists (select 1 from public.su_point_ledger where user_id = new.user_id and idempotency_key = v_key) then
    return new;
  end if;
  select count(distinct (timezone('Africa/Cairo', m.logged_at))::date) into v_logged
  from public.meal_logs m
  where m.user_id = new.user_id
    and (timezone('Africa/Cairo', m.logged_at))::date between v_season.starts_on and v_season.ends_on;
  if v_logged >= (v_season.ends_on - v_season.starts_on + 1) then
    perform public.qamar_wallet_credit_internal(
      new.user_id,
      coalesce(public.qamar_su_value('season_full_log'), 500),
      'season_log',
      v_key
    );
  end if;
  return new;
exception
  when others then
    raise warning 'qamar_earn_on_meal_season failed for %: %', new.user_id, sqlerrm;
    return new;
end;
$$;
revoke all on function public.qamar_earn_on_meal_season() from public, anon, authenticated;

drop trigger if exists qamar_on_meal_logged_season on public.meal_logs;
create trigger qamar_on_meal_logged_season
  after insert on public.meal_logs
  for each row execute function public.qamar_earn_on_meal_season();

-- A one-off, like the others: it does not eat the day's earning cap.
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
    and reason not in ('signup_bonus', 'onboarding', 'invitation_converted', 'invitation_paid', 'season_log')
    and (timezone('Africa/Cairo', created_at))::date = public.qamar_cairo_today();
$$;
revoke all on function public.qamar_su_earned_today(uuid) from public, anon, authenticated;
