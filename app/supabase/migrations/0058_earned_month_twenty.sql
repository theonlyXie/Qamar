-- The earned month: 20 logged days in the first 30 of paid membership,
-- not 28.
--
-- REVERSAL of a documented decision. The blueprint's paywall carries an
-- "earned-month promo (28/30 days)", and 0052 built it as written. That
-- number rewarded only the people who were never going to leave. 28 of 30
-- means logging on 93% of days in the first paid month, in a product whose
-- own pre-committed day-7 target is 40%. Almost nobody can reach it, so it
-- changes nobody's behaviour at the margin: it is a rebate for the most
-- committed, not a reason for anyone else to keep going. 20 of 30 is two
-- thirds of the days. A normal good month reaches it, so it works as a goal
-- while the month is being lived. Agreed by seats 1 and 5 (O14). Reverting
-- this migration's rows back to 28 restores the blueprint's number, and no
-- code changes are needed for that.
--
-- The threshold is no longer a constant inside a function. Both numbers
-- live in billing_config, where the operator can tune them without a
-- release, and qamar_earned_month_status reports them as `needed` and
-- `window_days`. Every sentence in the app that states the rule reads those
-- two fields and never writes its own number.
--
-- Everything else is 0052's: the window opens on the Cairo day of the first
-- paid order, logged days come from meal_logs, it happens once per account,
-- and the grant appends 30 days.
--
-- Idempotent against the live database: if not exists, on conflict do
-- nothing (a value the operator has since tuned is kept), create or
-- replace.

create table if not exists public.billing_config (
  key text primary key,
  value int not null check (value >= 0)
);

insert into public.billing_config (key, value) values
  ('earned_month_needed', 20),
  ('earned_month_window', 30)
on conflict (key) do nothing;

alter table public.billing_config enable row level security;
drop policy if exists billing_config_read on public.billing_config;
create policy billing_config_read on public.billing_config for select using (true);
revoke insert, update, delete on public.billing_config from anon, authenticated;

create or replace function public.qamar_earned_month_status(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today date := public.qamar_cairo_today();
  v_needed int := coalesce((select value from public.billing_config where key = 'earned_month_needed'), 20);
  v_window int := greatest(coalesce((select value from public.billing_config where key = 'earned_month_window'), 30), 1);
  v_start date;
  v_end date;
  v_logged int := 0;
  v_claimed public.earned_months;
begin
  if auth.role() <> 'service_role' and (auth.uid() is null or auth.uid() <> p_user_id) then
    raise exception 'not authorised to read this promo';
  end if;

  select * into v_claimed from public.earned_months where user_id = p_user_id;

  select (timezone('Africa/Cairo', min(paid_at)))::date
    into v_start
  from public.billing_orders
  where user_id = p_user_id and status = 'paid' and paid_at is not null;

  if v_start is null then
    return jsonb_build_object(
      'open', false,
      'needed', v_needed,
      'window_days', v_window,
      'logged_days', 0,
      'days_left', 0,
      'eligible', false,
      'claimed', v_claimed.user_id is not null,
      'granted_until', v_claimed.granted_until
    );
  end if;

  v_end := v_start + (v_window - 1);

  select count(distinct (timezone('Africa/Cairo', logged_at))::date)
    into v_logged
  from public.meal_logs
  where user_id = p_user_id
    and (timezone('Africa/Cairo', logged_at))::date between v_start and v_end;

  return jsonb_build_object(
    'open', v_claimed.user_id is null and v_today <= v_end,
    'window_start', v_start,
    'window_end', v_end,
    'needed', v_needed,
    'window_days', v_window,
    'logged_days', v_logged,
    'days_left', greatest(0, v_end - v_today),
    'eligible', v_claimed.user_id is null and v_logged >= v_needed,
    'claimed', v_claimed.user_id is not null,
    'granted_until', v_claimed.granted_until
  );
end;
$$;

revoke all on function public.qamar_earned_month_status(uuid) from public, anon;
grant execute on function public.qamar_earned_month_status(uuid) to authenticated, service_role;

-- Unchanged from 0052 apart from where the threshold comes from, which it
-- reads through qamar_earned_month_status. It is re-created here so the
-- pair travels together.
create or replace function public.qamar_claim_earned_month(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status jsonb;
  v_current_end timestamptz;
  v_provider text;
  v_end timestamptz;
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised to grant the earned month';
  end if;

  perform pg_advisory_xact_lock(hashtext('earned_month:' || p_user_id::text));

  v_status := public.qamar_earned_month_status(p_user_id);
  if (v_status->>'claimed')::boolean then
    raise exception 'earned month already granted';
  end if;
  if not (v_status->>'eligible')::boolean then
    raise exception 'not yet earned';
  end if;

  select period_end, provider into v_current_end, v_provider
  from public.entitlements
  where user_id = p_user_id
  for update;

  if v_current_end is not null and v_current_end > now() then
    -- Appended to the running month, whoever is paying for it.
    v_end := v_current_end + interval '30 days';
  else
    v_end := now() + interval '30 days';
    v_provider := 'earned';
  end if;

  insert into public.entitlements (user_id, status, plan, provider, period_end, source_order_id, updated_at)
  values (p_user_id, 'active', 'monthly', coalesce(v_provider, 'earned'), v_end, null, now())
  on conflict (user_id) do update set
    status = 'active',
    plan = 'monthly',
    provider = excluded.provider,
    period_end = v_end,
    updated_at = now();

  insert into public.earned_months (user_id, window_start, window_end, logged_days, granted_until)
  values (
    p_user_id,
    (v_status->>'window_start')::date,
    (v_status->>'window_end')::date,
    (v_status->>'logged_days')::int,
    v_end
  );

  return jsonb_build_object(
    'entitlement', public.qamar_entitlement_snapshot(p_user_id),
    'earned', public.qamar_earned_month_status(p_user_id)
  );
end;
$$;

revoke all on function public.qamar_claim_earned_month(uuid) from public, anon, authenticated;
grant execute on function public.qamar_claim_earned_month(uuid) to service_role;

comment on table public.earned_months is
  'The earned-month promo: the logged days billing_config asks for (20 at launch) in the first 30 of paid membership grant 30 more days of Qamar+, once per account.';
comment on table public.billing_config is
  'Billing rules the operator can tune without a release. earned_month_needed / earned_month_window: the earned month''s threshold, read by qamar_earned_month_status.';
