-- The blueprint's kill metrics, computed from rows people already write.
--
-- PostHog carries the funnel for people who consented to service
-- improvement; this is the nightly SQL report that needs no consent, because
-- it is an aggregate over the account's own tables and never leaves the
-- database. Four numbers with a target and a kill line each:
--
--   intake_completion   reached the plan reveal / started the consultation
--                       (target above 70%; below 50%: fix the consultation)
--   day7_logging        logged a meal on day 7 / installs matured to day 7
--                       (target above 40%; below 25%: stop — the habit is
--                       not forming)
--   day30_unprompted    logged a meal on day 30 with no notification that
--                       day / installs matured to day 30
--                       (target above 5%; below 2%: rework nudges and plans)
--   trial_to_paid       paid within 14 days of the trial / trials started
--                       (target above 25%; below 15%: paywall or price)
--
-- Definitions, honestly:
--   "started" is the first saved answer (the profiles row, written on the
--   first answered step), not the tap on Start — that tap is a PostHog event.
--   "day N" is the Nth Cairo date after the profile's first day (day 0).
--   "no notification that day": the app sends push nudges for the first
--   fourteen days only (NudgeSchedule.externalDays), so a day-30 log is
--   unprompted by construction. If that window ever moves past day 30, this
--   metric must learn about notifications.
--   Photo accuracy (the fifth kill line) is the eval suite's number
--   (eval_results), not a usage metric, and is not repeated here.

create or replace function public.qamar_kill_metrics(p_from date, p_to date)
returns table (
  metric text,
  numerator bigint,
  denominator bigint,
  value numeric,
  target numeric,
  kill numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with cohort as (
    select user_id, (timezone('Africa/Cairo', created_at))::date as day0
    from public.profiles
    where (timezone('Africa/Cairo', created_at))::date between p_from and p_to
  ),
  today as (select public.qamar_cairo_today() as d),
  logged_on as (
    -- (user, Cairo date) pairs with at least one meal.
    select distinct m.user_id, (timezone('Africa/Cairo', m.logged_at))::date as day
    from public.meal_logs m
    join cohort c on c.user_id = m.user_id
  ),
  intake as (
    select count(*) as den,
           count(*) filter (where exists (select 1 from public.targets t where t.user_id = c.user_id)) as num
    from cohort c
  ),
  day7 as (
    select count(*) as den,
           count(*) filter (where exists (select 1 from logged_on l where l.user_id = c.user_id and l.day = c.day0 + 7)) as num
    from cohort c, today
    where c.day0 + 7 < today.d
  ),
  day30 as (
    select count(*) as den,
           count(*) filter (where exists (select 1 from logged_on l where l.user_id = c.user_id and l.day = c.day0 + 30)) as num
    from cohort c, today
    where c.day0 + 30 < today.d
  ),
  trials as (
    select count(*) as den,
           count(*) filter (where exists (
             select 1 from public.billing_orders o
             where o.user_id = t.user_id
               and o.status = 'paid'
               and o.paid_at is not null
               and o.paid_at <= t.started_at + interval '14 days'
           )) as num
    from public.plus_trials t, today
    where (timezone('Africa/Cairo', t.started_at))::date between p_from and p_to
      and t.started_at + interval '14 days' < now()
  ),
  rows_ as (
    select 'intake_completion' as metric, num, den, 0.70::numeric as target, 0.50::numeric as kill from intake
    union all
    select 'day7_logging', num, den, 0.40, 0.25 from day7
    union all
    select 'day30_unprompted', num, den, 0.05, 0.02 from day30
    union all
    select 'trial_to_paid', num, den, 0.25, 0.15 from trials
  )
  select metric,
         num::bigint,
         den::bigint,
         case when den = 0 then null else round(num::numeric / den, 4) end,
         target,
         kill
  from rows_;
$$;
revoke all on function public.qamar_kill_metrics(date, date) from public, anon, authenticated;
grant execute on function public.qamar_kill_metrics(date, date) to service_role;

-- ---------------------------------------------------------------------
-- The nightly report: one row per metric per night, for the cohort of the
-- last sixty days of sign-ups (old enough for day 30 to have matured for
-- half of it). Read it with the service role or from the dashboard; no
-- client can.
create table if not exists public.kill_metrics_daily (
  day date not null,
  metric text not null,
  numerator bigint,
  denominator bigint,
  value numeric,
  target numeric,
  kill numeric,
  cohort_from date not null,
  cohort_to date not null,
  recorded_at timestamptz not null default now(),
  primary key (day, metric)
);
alter table public.kill_metrics_daily enable row level security;
revoke all on public.kill_metrics_daily from public, anon, authenticated;

create or replace function public.qamar_record_kill_metrics()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := public.qamar_cairo_today();
begin
  insert into public.kill_metrics_daily (day, metric, numerator, denominator, value, target, kill, cohort_from, cohort_to)
  select v_today, m.metric, m.numerator, m.denominator, m.value, m.target, m.kill, v_today - 60, v_today
  from public.qamar_kill_metrics(v_today - 60, v_today) m
  on conflict (day, metric) do update set
    numerator = excluded.numerator,
    denominator = excluded.denominator,
    value = excluded.value,
    target = excluded.target,
    kill = excluded.kill,
    cohort_from = excluded.cohort_from,
    cohort_to = excluded.cohort_to,
    recorded_at = now();
end;
$$;
revoke all on function public.qamar_record_kill_metrics() from public, anon, authenticated;

-- 22:30 UTC is 00:30 or 01:30 in Cairo, after the day's logs and before
-- anyone reads the report. pg_cron is already enabled by 0044.
do $$
begin
  perform cron.unschedule('qamar-kill-metrics');
exception when others then
  null;
end;
$$;

select cron.schedule(
  'qamar-kill-metrics',
  '30 22 * * *',
  $$ select public.qamar_record_kill_metrics(); $$
);
