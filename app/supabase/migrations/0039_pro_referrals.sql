-- The professional programme's memory: who referred this client, and until when.
--
-- 0037 attached a professional's code to one order at a time, so the share it
-- carried was paid once, on the order the client typed the code into. The
-- blueprint's offer is recurring — "EGP 100 a month for every patient on it,
-- for a year" — and a client is not going to re-enter a code twelve times.
--
-- So the first paid order carrying a professional's code writes one row here,
-- and for twelve months checkout attaches the same professional to every
-- renewal without asking. The share itself is still stamped per order at
-- checkout and credited per order on the webhook; this table only remembers
-- the relationship.
--
-- One referral per client, first professional wins. A client switching
-- nutritionists is a support conversation, not a race between codes.

create table if not exists public.pro_referrals (
  user_id uuid primary key references auth.users (id) on delete cascade,
  promo_code_id uuid not null references public.promo_codes (id) on delete cascade,
  affiliate_user_id uuid not null references auth.users (id) on delete cascade,
  first_order_id uuid references public.billing_orders (id) on delete set null,
  started_at timestamptz not null default now(),
  ends_at timestamptz not null default now() + interval '12 months',
  constraint pro_referrals_not_self check (user_id <> affiliate_user_id)
);

create index if not exists pro_referrals_affiliate_idx
  on public.pro_referrals (affiliate_user_id, ends_at desc);

alter table public.pro_referrals enable row level security;

drop policy if exists pro_referrals_select_own on public.pro_referrals;
create policy pro_referrals_select_own on public.pro_referrals
  for select using (auth.uid() = user_id or auth.uid() = affiliate_user_id);

-- Written by the webhook path only.
revoke insert, update, delete on public.pro_referrals from anon, authenticated;

-- Paid webhook: open Plus for the period, remember the referral if this is the
-- first paid order that carried one, then credit the professional's share once
-- per order. Replays must not pay twice — the unique commission index from
-- 0037 still enforces that.
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
  v_affiliate uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised to apply a payment';
  end if;

  select user_id, plan, status, promo_code_id, affiliate_user_id
    into v_user, v_plan, v_status, v_promo, v_affiliate
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
    -- Only the monthly plan is sold; the older values stay readable for
    -- orders written before 0039.
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

    -- First paid order with a professional attached starts the twelve months.
    if v_promo is not null and v_affiliate is not null and v_affiliate <> v_user then
      insert into public.pro_referrals (user_id, promo_code_id, affiliate_user_id, first_order_id)
      values (v_user, v_promo, v_affiliate, p_order_id)
      on conflict (user_id) do nothing;
    end if;
  end if;

  perform public.qamar_credit_affiliate_commission(p_order_id);

  return public.qamar_entitlement_snapshot(v_user);
end;
$$;

revoke all on function public.qamar_apply_paid_order(uuid, text) from public, anon, authenticated;
grant execute on function public.qamar_apply_paid_order(uuid, text) to service_role;

comment on table public.pro_referrals is
  'Which professional referred this client, for twelve months from the first paid order. Checkout attaches their 20% share to every renewal in that window.';
