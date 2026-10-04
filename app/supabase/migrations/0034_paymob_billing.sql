-- Qamar+ billed in Egypt through Paymob.
--
-- The phone never decides that someone has paid. Paymob posts a signed
-- callback; this schema records the order and, only then, the entitlement.
-- Su Points stay earned-only. This table is money.

create table if not exists public.billing_orders (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan text not null check (plan in ('monthly', 'annual')),
  amount_cents int not null check (amount_cents > 0),
  currency text not null default 'EGP' check (currency = 'EGP'),
  status text not null default 'pending'
    check (status in ('pending', 'paid', 'failed', 'expired')),
  paymob_intention_id text,
  paymob_order_id text,
  paymob_txn_id text,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  unique (paymob_txn_id)
);

create index if not exists billing_orders_user_idx
  on public.billing_orders (user_id, created_at desc);

create table if not exists public.billing_events (
  provider_event_id text primary key,
  order_id uuid references public.billing_orders (id) on delete set null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  status text not null default 'free' check (status in ('free', 'active', 'expired')),
  plan text check (plan in ('monthly', 'annual')),
  provider text not null default 'paymob',
  period_end timestamptz,
  source_order_id uuid references public.billing_orders (id),
  updated_at timestamptz not null default now()
);

alter table public.billing_orders enable row level security;
alter table public.billing_events enable row level security;
alter table public.entitlements enable row level security;

drop policy if exists billing_orders_select_own on public.billing_orders;
create policy billing_orders_select_own on public.billing_orders
  for select using (auth.uid() = user_id);

drop policy if exists entitlements_select_own on public.entitlements;
create policy entitlements_select_own on public.entitlements
  for select using (auth.uid() = user_id);

-- billing_events is webhook-only. Nobody on a phone reads it.

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

  return jsonb_build_object(
    'status', v_status,
    'plan', v_plan,
    'provider', coalesce(v_provider, 'paymob'),
    'period_end', v_end,
    'active', v_status = 'active' and (v_end is null or v_end >= now())
  );
end;
$$;

revoke all on function public.qamar_entitlement_snapshot(uuid) from public;
grant execute on function public.qamar_entitlement_snapshot(uuid) to authenticated, service_role;

-- Marks an order paid and opens (or extends) Qamar+. Idempotent on txn id.
create or replace function public.qamar_apply_paid_order(
  p_order_id uuid,
  p_txn_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid;
  v_plan text;
  v_status text;
  v_days int;
  v_end timestamptz;
  v_current_end timestamptz;
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised to apply a payment';
  end if;

  select user_id, plan, status into v_user, v_plan, v_status
  from public.billing_orders
  where id = p_order_id
  for update;

  if v_user is null then
    raise exception 'unknown order';
  end if;

  insert into public.billing_events (provider_event_id, order_id, payload)
  values (p_txn_id, p_order_id, jsonb_build_object('applied', true))
  on conflict (provider_event_id) do nothing;

  if exists (
    select 1 from public.billing_events
    where provider_event_id = p_txn_id and order_id is distinct from p_order_id
  ) then
    raise exception 'transaction already applied to another order';
  end if;

  if v_status = 'paid' then
    return public.qamar_entitlement_snapshot(v_user);
  end if;

  v_days := case when v_plan = 'annual' then 365 else 30 end;

  update public.billing_orders
     set status = 'paid',
         paymob_txn_id = p_txn_id,
         paid_at = now()
   where id = p_order_id;

  select period_end into v_current_end
  from public.entitlements
  where user_id = v_user;

  if v_current_end is not null and v_current_end > now() then
    v_end := v_current_end + make_interval(days => v_days);
  else
    v_end := now() + make_interval(days => v_days);
  end if;

  insert into public.entitlements (user_id, status, plan, provider, period_end, source_order_id, updated_at)
  values (v_user, 'active', v_plan, 'paymob', v_end, p_order_id, now())
  on conflict (user_id) do update set
    status = 'active',
    plan = excluded.plan,
    provider = 'paymob',
    period_end = v_end,
    source_order_id = excluded.source_order_id,
    updated_at = now();

  return public.qamar_entitlement_snapshot(v_user);
end;
$$;

revoke all on function public.qamar_apply_paid_order(uuid, text) from public, anon, authenticated;
grant execute on function public.qamar_apply_paid_order(uuid, text) to service_role;

comment on table public.entitlements is
  'Qamar+ access. Written only after a verified Paymob payment.';
comment on table public.billing_orders is
  'One Paymob checkout attempt. Price is stamped from the server catalog.';
