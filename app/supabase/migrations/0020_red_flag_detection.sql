-- Detection for the red flags that had none.
--
-- 0014 defined eight rules; five had detection behind them and three did not,
-- which meant they read as zero in safety_rule_activity forever and a reader
-- could not tell "never triggered" from "quietly broken". Two of the three are
-- fixed here. The third, severe_symptom, is a keyword set and lives in
-- scope.ts with the other refusals.
--
-- Both are triggers rather than application code on purpose. A weight arriving
-- from the app, from a device sync or from a support tool is the same weight,
-- and a safety rule that only fires on one of those paths is worse than none,
-- because it looks like coverage.
--
-- SECURITY DEFINER because they write to safety_events, which has no client
-- insert policy — the user causing the flag must not be the one who could
-- suppress it.

-- ---------------------------------------------------------------------
-- Weight trend
-- ---------------------------------------------------------------------

create or replace function public.qamar_weight_trend(
  p_user_id uuid,
  p_days int default 30
) returns table (
  first_kg numeric,
  last_kg numeric,
  days_spanned numeric,
  measurements int,
  change_kg numeric,
  pct_change numeric,
  kg_per_week numeric
)
language sql
stable
set search_path = public
as $$
  with w as (
    select value_kg, measured_at
    from public.weight_entries
    where user_id = p_user_id
      and value_kg is not null
      and measured_at >= now() - make_interval(days => p_days)
  ),
  bounds as (
    select
      (select value_kg from w order by measured_at asc limit 1) as first_kg,
      (select value_kg from w order by measured_at desc limit 1) as last_kg,
      (select measured_at from w order by measured_at asc limit 1) as t0,
      (select measured_at from w order by measured_at desc limit 1) as t1,
      (select count(*) from w) as n
  )
  select
    b.first_kg,
    b.last_kg,
    round((extract(epoch from (b.t1 - b.t0)) / 86400.0)::numeric, 2),
    b.n::int,
    round((b.last_kg - b.first_kg)::numeric, 2),
    case when b.first_kg > 0
      then round(((b.last_kg - b.first_kg) / b.first_kg * 100)::numeric, 2) end,
    case when b.t1 > b.t0
      then round((((b.last_kg - b.first_kg) / (extract(epoch from (b.t1 - b.t0)) / 86400.0)) * 7)::numeric, 3) end
  from bounds b
  where b.n >= 2;
$$;

comment on function public.qamar_weight_trend is
  'Raw trend over a window. Deliberately not smoothed: this is the screening '
  'input, and the adaptation engine does its own noise handling separately.';

-- ---------------------------------------------------------------------
-- rapid_weight_change
-- ---------------------------------------------------------------------
-- Screening threshold, not a clinical determination: 5% of body weight inside
-- 30 days, needing at least three measurements over at least 14 days so a
-- mis-typed number or a single odd morning cannot trip it. What happens next
-- is a human looking, which is the whole point of the escalation route.

create or replace function public.qamar_flag_rapid_weight_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  t record;
  recent int;
begin
  select * into t from public.qamar_weight_trend(new.user_id, 30);
  if t is null or t.measurements < 3 or t.days_spanned < 14 then
    return new;
  end if;
  if t.pct_change is null or abs(t.pct_change) < 5 then
    return new;
  end if;

  -- Debounce. Without this, every weigh-in during a genuine trend files another
  -- review and buries the queue the flag exists to populate.
  select count(*) into recent
  from public.safety_events
  where user_id = new.user_id
    and rule_slug = 'rapid_weight_change'
    and created_at > now() - interval '7 days';
  if recent > 0 then
    return new;
  end if;

  insert into public.safety_events (user_id, kind, rule_slug, reason, detail)
  values (new.user_id, 'escalation', 'rapid_weight_change',
          'weight changed ' || t.pct_change || '% in ' || t.days_spanned || ' days',
          jsonb_build_object(
            'first_kg', t.first_kg, 'last_kg', t.last_kg,
            'pct_change', t.pct_change, 'kg_per_week', t.kg_per_week,
            'days_spanned', t.days_spanned, 'measurements', t.measurements));

  insert into public.clinician_reviews
    (user_id, trigger_rule, priority, review_packet, explicit_questions)
  values (new.user_id, 'rapid_weight_change', 'routine',
          jsonb_build_object(
            'rule', 'rapid_weight_change',
            'first_kg', t.first_kg, 'last_kg', t.last_kg,
            'pct_change', t.pct_change, 'kg_per_week', t.kg_per_week,
            'window_days', t.days_spanned, 'measurements', t.measurements,
            'automated_action', 'flagged, no change to the user plan'),
          array[
            'Is this change explained by the user''s stated goal and intake?',
            'Does the rate need slowing, or the target revisiting?',
            'Any sign this should leave general wellness scope?'
          ]);

  return new;
exception
  -- A logging failure must never stop someone recording their weight.
  when others then
    raise warning 'qamar_flag_rapid_weight_change failed for %: %', new.user_id, sqlerrm;
    return new;
end;
$$;

drop trigger if exists weight_entries_red_flag on public.weight_entries;
create trigger weight_entries_red_flag
  after insert on public.weight_entries
  for each row execute function public.qamar_flag_rapid_weight_change();

-- ---------------------------------------------------------------------
-- critical_lab
-- ---------------------------------------------------------------------
-- Urgent, and it does not wait for the user to ask a question. A critical
-- value sitting unread in a table is the scenario the referral engine exists
-- to prevent.

create or replace function public.qamar_flag_critical_lab()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.abnormal_flag is null
     or new.abnormal_flag not in ('critical_low', 'critical_high') then
    return new;
  end if;

  insert into public.safety_events (user_id, kind, rule_slug, reason, detail)
  values (new.user_id, 'escalation', 'critical_lab',
          new.analyte || ' flagged ' || new.abnormal_flag,
          jsonb_build_object(
            'analyte', new.analyte, 'value', new.value, 'unit', new.unit,
            'reference_low', new.reference_low, 'reference_high', new.reference_high,
            'flag', new.abnormal_flag, 'drawn_at', new.drawn_at));

  insert into public.clinician_reviews
    (user_id, trigger_rule, priority, review_packet, explicit_questions)
  values (new.user_id, 'critical_lab', 'urgent',
          jsonb_build_object(
            'rule', 'critical_lab',
            'analyte', new.analyte, 'value', new.value, 'unit', new.unit,
            'flag', new.abnormal_flag, 'drawn_at', new.drawn_at,
            'automated_action', 'flagged urgently; Qamar gives no interpretation'),
          array[
            'Has the user been advised to contact their clinician?',
            'Should nutrition guidance be suspended pending review?'
          ]);

  return new;
exception
  when others then
    raise warning 'qamar_flag_critical_lab failed for %: %', new.user_id, sqlerrm;
    return new;
end;
$$;

drop trigger if exists user_labs_red_flag on public.user_labs;
create trigger user_labs_red_flag
  after insert on public.user_labs
  for each row execute function public.qamar_flag_critical_lab();

revoke all on function public.qamar_flag_rapid_weight_change() from public, anon, authenticated;
revoke all on function public.qamar_flag_critical_lab() from public, anon, authenticated;
