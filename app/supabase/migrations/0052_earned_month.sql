-- The earned month: 28 logged days in the first 30 of membership, and the
-- next 30 days of Qamar+ are on us.
--
-- The blueprint's paywall carries an "earned-month promo (28/30 days)" that
-- starts on day one of a subscription. It is a retention promise made at the
-- moment the habit is most likely to break — the first month — and it is
-- paid in the product, not in points. It is once per account: a promo, not
-- a standing discount for anyone who logs.
--
-- Nothing here is a counter kept in step by the app. The window opens on the
-- Cairo day of the first paid order and closes 30 days later; the logged
-- days are counted from meal_logs when asked; the grant is one row here and
-- 30 days appended to the entitlement, the same way a paid renewal appends
-- (qamar_apply_paid_order). A member who lets the month lapse and then
-- earns it starts a fresh 30 days with provider = 'earned'.

create table if not exists public.earned_months (
  user_id uuid primary key references auth.users (id) on delete cascade,
  window_start date not null,
  window_end date not null,
  logged_days int not null,
  granted_until timestamptz not null,
  created_at timestamptz not null default now()
);

alter table public.earned_months enable row level security;

drop policy if exists earned_months_select_own on public.earned_months;
create policy earned_months_select_own on public.earned_months
  for select using (auth.uid() = user_id);

-- Written by the claim below, through the billing function, only.
revoke insert, update, delete on public.earned_months from anon, authenticated;

-- Where this person stands. Readable by the person and the service role.
--
--   open          the window is running and nothing has been granted yet
--   logged_days   distinct Cairo days with a meal in the window so far
--   days_left     window days still to come, today excluded
--   eligible      28 or more logged days and not yet granted
--   claimed       the month has been granted (granted_until says until when)
create or replace function public.qamar_earned_month_status(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today date := public.qamar_cairo_today();
  v_needed constant int := 28;
  v_window constant int := 30;
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

-- Grants the month. Service role only (the billing function calls it for an
-- authenticated user); the eligibility is re-read here under a lock, so two
-- claims racing cannot grant twice, and the once-per-account rule is the
-- primary key.
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
  'The earned-month promo: 28 logged days in the first 30 of paid membership grant 30 more days of Qamar+, once per account.';
