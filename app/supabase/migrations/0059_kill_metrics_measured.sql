-- The kill metrics, measured rather than asserted.
--
-- This replaces qamar_kill_metrics as a whole. It is the one migration that
-- does, and it has one owner (O13), so no two replacements can overwrite
-- each other. It also adds the columns the new definitions read.
--
-- What each number is now, and what changed against the target it was set
-- against:
--
--   Day 0 is the install: auth.users.created_at. The app signs in
--   anonymously at launch, before the welcome screen, so an account is an
--   app open. 0047 counted from the profile, which is only written once the
--   first question is answered. That left everyone who never answered it
--   out of every denominator. "Installs" is the blueprint's own word for
--   those denominators. One known skew: a member who signs in on a new phone
--   leaves behind an unused anonymous account. It counts as an install that
--   never logged, so every number errs low, never high. The phone's
--   fourteen-day push window now starts from the same server day
--   (qamar_account_day0), so a reinstall followed by a sign-in no longer
--   restarts the pushes.
--
--   intake_completion    reached the plan reveal / pressed Start (the tap is
--                        recorded in intake_starts since 0057; before that,
--                        the first saved answer stands in). This is the
--                        blueprint's definition, so the 70% target and 50%
--                        kill line stand. Expect a lower number than 0047
--                        gave: the first question's drop-off is now inside
--                        it. A Start counts once it is a Cairo day old.
--   install_to_start     new: installs that pressed Start. It measures the
--                        welcome screen. No line is set for it, so target
--                        and kill are null.
--   day7_logging         installs with a meal log on day 7 exactly. This is
--                        the blueprint's pre-committed definition and is
--                        kept exactly: a window would read higher and
--                        flatter a kill line set against a single day. Only
--                        the denominator moved, to installs, which is
--                        stricter.
--   week1_logging        new and diagnostic, with no kill line: installs
--                        with a log on any of days 1 to 7, so one noisy
--                        date is not the only view of the first week.
--   day30_unprompted     installs with at least one log on day 30 whose
--                        prompt was not a push. meal_logs.prompt records it
--                        now; 0047 only asserted it ("pushes stop at day 14,
--                        so a day-30 log is unprompted by construction"),
--                        which the free week's and the paid month's
--                        reminders, and a reinstall, all made false. A log
--                        that began from the orb's waiting question counts
--                        here, because that is the app itself and not a
--                        notification. That is the reading the 5% target
--                        and 2% kill line were set against ("no
--                        notification that day"), so both stand. A null
--                        prompt means unknown and never counts.
--   day30_cold           new and stricter, with no kill line: day-30 logs
--                        with prompt = 'none', meaning neither a push nor
--                        the orb's question.
--   trial_to_paid        paid by the trial's end + 7 days / trials started,
--                        read once that point has passed. The blueprint says
--                        "paying at day 14"; for the organic 7-day trial
--                        that is the same moment. It used to be start + 14,
--                        which gave a 14-day trial (Pro code, invitation) no
--                        days at all after it ended. The 25% target and 15%
--                        kill line stand.
--   trial_to_paid_organic / _pro / _invitation
--                        the same, split by plus_trials.source. The organic
--                        row carries the 25% / 15% line: below 15%, the
--                        blueprint's framing test runs before any price
--                        change. Pro and invitation have no line; the
--                        blueprint only asks that they convert at about
--                        twice the organic rate. A trial with no source
--                        recorded is attributed from the tables that
--                        existed when it started:
--                          - an invitation redeemed within the hour before
--                            it, or
--                          - a Pro referral that already existed.
--                        A code typed only at checkout does not make a
--                        trial "pro": pro_referrals rows are written at
--                        payment, so counting them would label only the
--                        people who converted.
--   month2_retention     new: payers whose first paid order is in the window
--                        and who made a second paid order within 37 days of
--                        the first (the month plus a week). An earned month
--                        moves the next payment by 30 days, so a member who
--                        earned one gets 30 days more. This is the
--                        blueprint's gate for an annual tier; the spec's
--                        decision threshold is 60%, with no kill line.
--
-- Idempotent against the live database: add column if not exists, create or
-- replace.

-- ---------------------------------------------------------------------
-- What the metrics read
-- ---------------------------------------------------------------------

-- Captured on the phone when the log starts, not when it is confirmed, because
-- by then the waiting question has gone:
--   push     a notification was tapped within 30 minutes before the log
--   in_app   the log began from holding the orb while Qamar's question waited
--   none     everything else — including a log from the tree while the orb
--            pulsed, which is the habit itself
-- orb_waiting: a question was waiting when the log started, whatever the path.
-- Both are null on rows written before this existed: unknown.
alter table public.meal_logs
  add column if not exists prompt text check (prompt in ('push', 'in_app', 'none')),
  add column if not exists orb_waiting boolean;

-- organic / pro / invitation, written where each trial is started.
alter table public.plus_trials
  add column if not exists source text check (source in ('organic', 'pro', 'invitation'));

-- Day 0 of this account, for the phone's fourteen-day push window: the same
-- day the metrics count from, and one a reinstall does not move.
create or replace function public.qamar_account_day0()
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select u.created_at from auth.users u where u.id = auth.uid();
$$;
revoke all on function public.qamar_account_day0() from public, anon;
grant execute on function public.qamar_account_day0() to authenticated;

-- ---------------------------------------------------------------------
-- The numbers
-- ---------------------------------------------------------------------

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
  with today as (select public.qamar_cairo_today() as d),
  installs as (
    select u.id as user_id, (timezone('Africa/Cairo', u.created_at))::date as day0
    from auth.users u
    where (timezone('Africa/Cairo', u.created_at))::date between p_from and p_to
  ),
  starters as (
    -- Pressed Start: the tap (0057), or before that existed the first saved
    -- answer — whichever came first.
    select s.user_id, (timezone('Africa/Cairo', min(s.at)))::date as day
    from (
      select user_id, started_at as at from public.intake_starts
      union all
      select user_id, created_at from public.profiles
    ) s
    group by s.user_id
  ),
  intake as (
    select count(*) as den,
           count(*) filter (where exists (select 1 from public.targets t where t.user_id = s.user_id)) as num
    from starters s, today
    where s.day between p_from and p_to
      and s.day < today.d
  ),
  install_start as (
    select count(*) as den,
           count(*) filter (where exists (select 1 from starters s where s.user_id = i.user_id)) as num
    from installs i, today
    where i.day0 < today.d
  ),
  day7 as (
    select count(*) as den,
           count(*) filter (where exists (
             select 1 from public.meal_logs m
             where m.user_id = i.user_id
               and (timezone('Africa/Cairo', m.logged_at))::date = i.day0 + 7
           )) as num
    from installs i, today
    where i.day0 + 7 < today.d
  ),
  week1 as (
    select count(*) as den,
           count(*) filter (where exists (
             select 1 from public.meal_logs m
             where m.user_id = i.user_id
               and (timezone('Africa/Cairo', m.logged_at))::date between i.day0 + 1 and i.day0 + 7
           )) as num
    from installs i, today
    where i.day0 + 7 < today.d
  ),
  day30 as (
    select count(*) as den,
           count(*) filter (where exists (
             select 1 from public.meal_logs m
             where m.user_id = i.user_id
               and (timezone('Africa/Cairo', m.logged_at))::date = i.day0 + 30
               and m.prompt in ('in_app', 'none')
           )) as num_unprompted,
           count(*) filter (where exists (
             select 1 from public.meal_logs m
             where m.user_id = i.user_id
               and (timezone('Africa/Cairo', m.logged_at))::date = i.day0 + 30
               and m.prompt = 'none'
           )) as num_cold
    from installs i, today
    where i.day0 + 30 < today.d
  ),
  trials as (
    select t.user_id,
           t.ends_at,
           coalesce(
             t.source,
             case
               when exists (
                 select 1 from public.invitations v
                 where v.redeemed_by = t.user_id
                   and v.redeemed_at is not null
                   and v.redeemed_at between t.started_at - interval '1 hour' and t.started_at
               ) then 'invitation'
               when exists (
                 select 1 from public.pro_referrals r
                 where r.user_id = t.user_id and r.started_at <= t.started_at
               ) then 'pro'
               else 'organic'
             end
           ) as source,
           exists (
             select 1 from public.billing_orders o
             where o.user_id = t.user_id
               and o.status = 'paid'
               and o.paid_at is not null
               and o.paid_at <= t.ends_at + interval '7 days'
           ) as paid
    from public.plus_trials t
    where (timezone('Africa/Cairo', t.started_at))::date between p_from and p_to
      and t.ends_at + interval '7 days' < now()
  ),
  payers as (
    select o.user_id,
           min(o.paid_at) as first_paid
    from public.billing_orders o
    where o.status = 'paid' and o.paid_at is not null
    group by o.user_id
  ),
  renewals as (
    select p.user_id,
           p.first_paid + interval '37 days'
             + case when exists (select 1 from public.earned_months e where e.user_id = p.user_id)
                    then interval '30 days' else interval '0 days' end as due_by
    from payers p
    where (timezone('Africa/Cairo', p.first_paid))::date between p_from and p_to
  ),
  month2 as (
    select count(*) as den,
           count(*) filter (where (
             select count(*) from public.billing_orders o
             where o.user_id = r.user_id
               and o.status = 'paid'
               and o.paid_at is not null
               and o.paid_at <= r.due_by
           ) >= 2) as num
    from renewals r
    where r.due_by < now()
  ),
  rows_ as (
    select 'intake_completion' as metric, num, den, 0.70::numeric as target, 0.50::numeric as kill from intake
    union all
    select 'install_to_start', num, den, null, null from install_start
    union all
    select 'day7_logging', num, den, 0.40, 0.25 from day7
    union all
    select 'week1_logging', num, den, null, null from week1
    union all
    select 'day30_unprompted', num_unprompted, den, 0.05, 0.02 from day30
    union all
    select 'day30_cold', num_cold, den, null, null from day30
    union all
    select 'trial_to_paid', count(*) filter (where paid), count(*), 0.25, 0.15 from trials
    union all
    select 'trial_to_paid_organic', count(*) filter (where paid), count(*), 0.25, 0.15 from trials where source = 'organic'
    union all
    select 'trial_to_paid_pro', count(*) filter (where paid), count(*), null, null from trials where source = 'pro'
    union all
    select 'trial_to_paid_invitation', count(*) filter (where paid), count(*), null, null from trials where source = 'invitation'
    union all
    select 'month2_retention', num, den, 0.60, null from month2
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

comment on column public.meal_logs.prompt is
  'What started this log: push (a notification tapped within 30 minutes), in_app (the orb''s waiting question, held), none. Captured when the log starts. Null: written before 0059, unknown.';
comment on column public.meal_logs.orb_waiting is
  'A meal question was waiting on the orb when this log started, whatever the path. Null: unknown.';
comment on column public.plus_trials.source is
  'organic / pro / invitation, written where the trial starts. Null rows are attributed by qamar_kill_metrics from what existed when the trial started.';
