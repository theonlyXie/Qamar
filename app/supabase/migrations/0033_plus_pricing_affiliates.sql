-- Qamar+ catalog, promo codes (affiliate now, campaigns later), and an
-- Egyptian-pound affiliate wallet. This wallet is cash we send the marketer.
-- It is not Su Points. Su stay earned-only.

-- Plans: monthly (500 list / 350 first-user / 299 affiliate), quarterly (249),
-- annual (249). Amounts live in the billing function; this schema stores what
-- was actually charged.

alter table public.billing_orders drop constraint if exists billing_orders_plan_check;
alter table public.billing_orders
  add constraint billing_orders_plan_check
  check (plan in ('monthly', 'quarterly', 'annual'));

alter table public.entitlements drop constraint if exists entitlements_plan_check;
alter table public.entitlements
  add constraint entitlements_plan_check
  check (plan is null or plan in ('monthly', 'quarterly', 'annual'));

alter table public.billing_orders
  add column if not exists pricing_reason text not null default 'list'
    check (pricing_reason in (
      'list', 'first_user', 'affiliate', 'campaign', 'annual_half', 'quarterly_pack'
    )),
  add column if not exists promo_code_id uuid,
  add column if not exists affiliate_user_id uuid references auth.users (id) on delete set null,
  add column if not exists affiliate_commission_cents int not null default 0
    check (affiliate_commission_cents >= 0);

create table if not exists public.promo_codes (
  id uuid primary key default uuid_generate_v4(),
  code text not null,
  kind text not null check (kind in ('affiliate', 'campaign')),
  owner_user_id uuid references auth.users (id) on delete cascade,
  percent_off int check (percent_off is null or (percent_off > 0 and percent_off <= 90)),
  amount_cents int check (amount_cents is null or amount_cents > 0),
  applies_to_plans text[] check (
    applies_to_plans is null
    or applies_to_plans <@ array['monthly', 'quarterly', 'annual']::text[]
  ),
  max_redemptions int check (max_redemptions is null or max_redemptions > 0),
  redemption_count int not null default 0 check (redemption_count >= 0),
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint promo_codes_code_nonempty check (length(code) >= 3),
  constraint promo_codes_affiliate_has_owner check (
    kind <> 'affiliate' or owner_user_id is not null
  )
);

create unique index if not exists promo_codes_code_uidx
  on public.promo_codes (code);

create unique index if not exists promo_codes_one_affiliate_per_user
  on public.promo_codes (owner_user_id)
  where kind = 'affiliate' and owner_user_id is not null;

alter table public.billing_orders drop constraint if exists billing_orders_promo_code_id_fkey;
alter table public.billing_orders
  add constraint billing_orders_promo_code_id_fkey
  foreign key (promo_code_id) references public.promo_codes (id) on delete set null;

create table if not exists public.affiliate_ledger (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  amount_cents int not null check (amount_cents <> 0),
  currency text not null default 'EGP' check (currency = 'EGP'),
  kind text not null check (kind in ('commission', 'payout', 'adjustment')),
  order_id uuid references public.billing_orders (id) on delete set null,
  payout_id uuid,
  note text,
  created_at timestamptz not null default now()
);

create unique index if not exists affiliate_ledger_one_commission_per_order
  on public.affiliate_ledger (order_id)
  where kind = 'commission';

create index if not exists affiliate_ledger_user_idx
  on public.affiliate_ledger (user_id, created_at desc);

create table if not exists public.affiliate_payouts (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  amount_cents int not null check (amount_cents > 0),
  currency text not null default 'EGP' check (currency = 'EGP'),
  status text not null default 'requested'
    check (status in ('requested', 'sent', 'rejected')),
  note text,
  requested_at timestamptz not null default now(),
  processed_at timestamptz
);

alter table public.affiliate_ledger drop constraint if exists affiliate_ledger_payout_id_fkey;
alter table public.affiliate_ledger
  add constraint affiliate_ledger_payout_id_fkey
  foreign key (payout_id) references public.affiliate_payouts (id) on delete set null;

alter table public.promo_codes enable row level security;
alter table public.affiliate_ledger enable row level security;
alter table public.affiliate_payouts enable row level security;

drop policy if exists promo_codes_select_own_affiliate on public.promo_codes;
create policy promo_codes_select_own_affiliate on public.promo_codes
  for select using (auth.uid() = owner_user_id);

drop policy if exists affiliate_ledger_select_own on public.affiliate_ledger;
create policy affiliate_ledger_select_own on public.affiliate_ledger
  for select using (auth.uid() = user_id);

drop policy if exists affiliate_payouts_select_own on public.affiliate_payouts;
create policy affiliate_payouts_select_own on public.affiliate_payouts
  for select using (auth.uid() = user_id);

create or replace function public.qamar_has_paid_plus(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.billing_orders
    where user_id = p_user_id and status = 'paid'
  );
$$;

revoke all on function public.qamar_has_paid_plus(uuid) from public, anon, authenticated;
grant execute on function public.qamar_has_paid_plus(uuid) to service_role;

create or replace function public.qamar_ensure_affiliate_code(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_try int := 0;
begin
  if auth.role() <> 'service_role' and (auth.uid() is null or auth.uid() <> p_user_id) then
    raise exception 'not authorised to create an affiliate code';
  end if;

  select code into v_code
  from public.promo_codes
  where owner_user_id = p_user_id and kind = 'affiliate'
  limit 1;

  if v_code is not null then
    return v_code;
  end if;

  loop
    v_try := v_try + 1;
    v_code := 'QMR' || upper(substr(md5(p_user_id::text || clock_timestamp()::text || v_try::text), 1, 6));
    begin
      insert into public.promo_codes (code, kind, owner_user_id, active)
      values (v_code, 'affiliate', p_user_id, true);
      return v_code;
    exception when unique_violation then
      if v_try > 8 then
        raise;
      end if;
    end;
  end loop;
end;
$$;

revoke all on function public.qamar_ensure_affiliate_code(uuid) from public, anon;
grant execute on function public.qamar_ensure_affiliate_code(uuid) to authenticated, service_role;

create or replace function public.qamar_affiliate_snapshot(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code text;
  v_balance int := 0;
  v_earned int := 0;
  v_pending int := 0;
begin
  if auth.role() <> 'service_role' and (auth.uid() is null or auth.uid() <> p_user_id) then
    raise exception 'not authorised to read this affiliate wallet';
  end if;

  select code into v_code
  from public.promo_codes
  where owner_user_id = p_user_id and kind = 'affiliate'
  limit 1;

  select coalesce(sum(amount_cents), 0) into v_balance
  from public.affiliate_ledger
  where user_id = p_user_id;

  select coalesce(sum(amount_cents), 0) into v_earned
  from public.affiliate_ledger
  where user_id = p_user_id and kind = 'commission';

  select coalesce(sum(amount_cents), 0) into v_pending
  from public.affiliate_payouts
  where user_id = p_user_id and status = 'requested';

  return jsonb_build_object(
    'code', v_code,
    'balance_cents', v_balance,
    'lifetime_earned_cents', v_earned,
    'pending_payout_cents', v_pending,
    'currency', 'EGP',
    'min_payout_cents', 5000
  );
end;
$$;

revoke all on function public.qamar_affiliate_snapshot(uuid) from public, anon;
grant execute on function public.qamar_affiliate_snapshot(uuid) to authenticated, service_role;

create or replace function public.qamar_request_affiliate_payout(
  p_user_id uuid,
  p_amount_cents int default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance int := 0;
  v_amount int;
  v_payout uuid;
begin
  if auth.role() <> 'service_role' and (auth.uid() is null or auth.uid() <> p_user_id) then
    raise exception 'not authorised to request this payout';
  end if;

  select coalesce(sum(amount_cents), 0) into v_balance
  from public.affiliate_ledger
  where user_id = p_user_id;

  v_amount := coalesce(p_amount_cents, v_balance);

  if v_amount < 5000 then
    raise exception 'minimum payout is 50 EGP';
  end if;
  if v_amount > v_balance then
    raise exception 'not enough affiliate balance';
  end if;

  insert into public.affiliate_payouts (user_id, amount_cents, status)
  values (p_user_id, v_amount, 'requested')
  returning id into v_payout;

  insert into public.affiliate_ledger (user_id, amount_cents, currency, kind, payout_id, note)
  values (p_user_id, -v_amount, 'EGP', 'payout', v_payout, 'Payout requested');

  return public.qamar_affiliate_snapshot(p_user_id);
end;
$$;

revoke all on function public.qamar_request_affiliate_payout(uuid, int) from public, anon;
grant execute on function public.qamar_request_affiliate_payout(uuid, int) to authenticated, service_role;

create or replace function public.qamar_credit_affiliate_commission(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_affiliate uuid;
  v_buyer uuid;
  v_cents int;
begin
  select affiliate_user_id, user_id, affiliate_commission_cents
    into v_affiliate, v_buyer, v_cents
  from public.billing_orders
  where id = p_order_id;

  if v_affiliate is null or v_cents is null or v_cents <= 0 then
    return;
  end if;
  if v_affiliate = v_buyer then
    return;
  end if;

  insert into public.affiliate_ledger (
    user_id, amount_cents, currency, kind, order_id, note
  )
  values (
    v_affiliate, v_cents, 'EGP', 'commission', p_order_id,
    'Affiliate commission — EGP cash, not Su Points'
  )
  on conflict (order_id) where kind = 'commission' do nothing;
end;
$$;

revoke all on function public.qamar_credit_affiliate_commission(uuid) from public, anon, authenticated;
grant execute on function public.qamar_credit_affiliate_commission(uuid) to service_role;

-- Paid webhook: open Plus for the period stamped on the plan, then credit
-- the affiliate once. Replays must not pay twice.
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
  v_promo uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised to apply a payment';
  end if;

  select user_id, plan, status, promo_code_id into v_user, v_plan, v_status, v_promo
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

  if v_status <> 'paid' then
    v_days := case v_plan
      when 'annual' then 365
      when 'quarterly' then 90
      else 30
    end;

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

    if v_promo is not null then
      update public.promo_codes
         set redemption_count = redemption_count + 1
       where id = v_promo;
    end if;
  end if;

  perform public.qamar_credit_affiliate_commission(p_order_id);

  return public.qamar_entitlement_snapshot(v_user);
end;
$$;

revoke all on function public.qamar_apply_paid_order(uuid, text) from public, anon, authenticated;
grant execute on function public.qamar_apply_paid_order(uuid, text) to service_role;

comment on table public.promo_codes is
  'Affiliate codes and later campaign codes. The server stamps the price; the phone only sends the code.';
comment on table public.affiliate_ledger is
  'EGP cash owed to affiliate marketers. Not Su Points. Credited only after a verified Paymob payment.';
comment on table public.affiliate_payouts is
  'A marketer asked us to send their EGP balance. Founders mark it sent from our end.';
comment on column public.billing_orders.amount_cents is
  'What Paymob was asked to collect. Stamped from the server catalog, never from the phone.';
