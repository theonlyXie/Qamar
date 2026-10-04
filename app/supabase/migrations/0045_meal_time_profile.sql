-- When this person actually eats.
--
-- The blueprint's nudge lands "at the user's own meal times". Nothing is
-- asked at intake; the times are learned from the meals they log. Each slot
-- (breakfast < 11:00, lunch 11:00–16:59, dinner from 17:00 — the same cut the
-- app uses) reports the median minute of the day over the last 30 days once
-- it has at least three logs, and null before that, so the app keeps a
-- typical hour until the person's own pattern is real.
--
-- Cairo local time, as the rest of the day logic. A member living an hour
-- away gets a nudge an hour off until this learns from their logs, which it
-- does within a week of normal use.

create or replace function public.qamar_meal_time_profile(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with logs as (
    select timezone('Africa/Cairo', logged_at) as local_at
    from public.meal_logs
    where user_id = p_user_id
      and logged_at >= now() - interval '30 days'
      and (auth.role() = 'service_role' or auth.uid() = p_user_id)
  ),
  minutes as (
    select
      extract(hour from local_at)::int * 60 + extract(minute from local_at)::int as minute,
      case
        when extract(hour from local_at) < 11 then 'breakfast'
        when extract(hour from local_at) < 17 then 'lunch'
        else 'dinner'
      end as slot
    from logs
  ),
  medians as (
    select slot, percentile_cont(0.5) within group (order by minute) as median, count(*) as n
    from minutes
    group by slot
  )
  select jsonb_build_object(
    'breakfast', (select round(median)::int from medians where slot = 'breakfast' and n >= 3),
    'lunch',     (select round(median)::int from medians where slot = 'lunch' and n >= 3),
    'dinner',    (select round(median)::int from medians where slot = 'dinner' and n >= 3)
  );
$$;

revoke all on function public.qamar_meal_time_profile(uuid) from public, anon;
grant execute on function public.qamar_meal_time_profile(uuid) to authenticated, service_role;
