-- Qamar+ trial: seven days, once per account, before the first payment.
--
-- A trial is an entitlement row with provider = 'trial', so every check that
-- already asks qamar_is_plus (quota buckets, the plan bucket, the night job)
-- honours it without change. The once-only rule lives in plus_trials: one
-- row per user, ever. A paid order after the trial overwrites the row with
-- provider = 'paymob' (see qamar_apply_paid_order), so the trial cannot be
-- restarted by expiring and paying, and paying does not "use up" a trial
-- that was never taken — a trial is simply not offered after a payment.

create table if not exists public.plus_trials (
  user_id uuid primary key references auth.users (id) on delete cascade,
  started_at timestamptz not null default now(),
  ends_at timestamptz not null
);

alter table public.plus_trials enable row level security;
drop policy if exists plus_trials_select_own on public.plus_trials;
create policy plus_trials_select_own on public.plus_trials
  for select using (auth.uid() = user_id);
revoke insert, update, delete on public.plus_trials from anon, authenticated;

-- Eligible: never had a trial, never paid, not currently Qamar+.
create or replace function public.qamar_trial_eligible(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (select 1 from public.plus_trials where user_id = p_user_id)
     and not public.qamar_has_paid_plus(p_user_id)
     and not public.qamar_is_plus(p_user_id);
$$;

revoke all on function public.qamar_trial_eligible(uuid) from public, anon;
grant execute on function public.qamar_trial_eligible(uuid) to authenticated, service_role;

-- The snapshot the app reads, now with the trial fields.
create or replace function public.qamar_entitlement_snapshot(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_status text := 'free';
  v_plan text;
  v_end timestamptz;
  v_provider text := 'paymob';
  v_trial_end timestamptz;
begin
  if auth.role() <> 'service_role' and (auth.uid() is null or auth.uid() <> p_user_id) then
    raise exception 'not authorised to read this entitlement';
  end if;

  select status, plan, period_end, provider
    into v_status, v_plan, v_end, v_provider
  from public.entitlements
  where user_id = p_user_id;

  if v_status is null then
    v_status := 'free';
  elsif v_status = 'active' and v_end is not null and v_end < now() then
    v_status := 'expired';
  end if;

  select ends_at into v_trial_end from public.plus_trials where user_id = p_user_id;

  return jsonb_build_object(
    'status', v_status,
    'plan', v_plan,
    'provider', coalesce(v_provider, 'paymob'),
    'period_end', v_end,
    'active', v_status = 'active' and (v_end is null or v_end >= now()),
    'trial_eligible', public.qamar_trial_eligible(p_user_id),
    'trial_ends_at', v_trial_end
  );
end;
$$;

revoke all on function public.qamar_entitlement_snapshot(uuid) from public;
grant execute on function public.qamar_entitlement_snapshot(uuid) to authenticated, service_role;

-- Starts the trial. Called by the billing function with the service role on
-- behalf of an authenticated user; refuses with a legible reason otherwise.
create or replace function public.qamar_start_trial(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_end timestamptz := now() + interval '7 days';
begin
  if auth.role() <> 'service_role' and (auth.uid() is null or auth.uid() <> p_user_id) then
    raise exception 'not authorised to start this trial';
  end if;
  if exists (select 1 from public.plus_trials where user_id = p_user_id) then
    raise exception 'trial already used';
  end if;
  if public.qamar_has_paid_plus(p_user_id) then
    raise exception 'trial is for first-time members';
  end if;
  if public.qamar_is_plus(p_user_id) then
    raise exception 'already Qamar+';
  end if;

  insert into public.plus_trials (user_id, ends_at) values (p_user_id, v_end);

  insert into public.entitlements (user_id, status, plan, provider, period_end, source_order_id, updated_at)
  values (p_user_id, 'active', 'monthly', 'trial', v_end, null, now())
  on conflict (user_id) do update set
    status = 'active',
    plan = 'monthly',
    provider = 'trial',
    period_end = v_end,
    source_order_id = null,
    updated_at = now();

  return public.qamar_entitlement_snapshot(p_user_id);
end;
$$;

revoke all on function public.qamar_start_trial(uuid) from public, anon;
grant execute on function public.qamar_start_trial(uuid) to authenticated, service_role;
