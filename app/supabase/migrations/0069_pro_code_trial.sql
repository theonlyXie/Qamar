-- A nutritionist's code starts the free fortnight (O12, seat 5).
--
-- The blueprint gives two trial lengths: seven days for someone who found
-- Qamar alone, fourteen for someone a nutritionist or an invitation sent
-- ("Pro code → client installs, 14-day trial"). Until now only an invitation
-- gave fourteen (0049). A professional's code was typed only at checkout, so
-- it moved the professional's 20% share and nothing else, and a referred
-- client got the same seven days as anyone.
--
-- What this adds:
--   1. billing_config 'pro_trial_days' = 14, tunable without a release.
--   2. promo_codes.professional: the operator's confirmation that an
--      affiliate code belongs to a nutritionist, coach or clinic. Every
--      account gets an affiliate code the first time Me loads (0037,
--      qamar_ensure_affiliate_code), so "any affiliate code" would let anyone
--      hand out fourteen days and the seven-day trial would mean nothing.
--      Only a confirmed code starts the fortnight. It is false until the
--      operator sets it, and no client can.
--   3. pro_code_claims: the professional a person named before paying. The
--      billing function reads it when no code is typed at checkout, so the
--      professional's share attaches to the first payment without the client
--      typing the code again. pro_referrals is still written only at that
--      first payment (0039), so the twelve months of share still start there.
--   4. qamar_redeem_pro_code(code): claims the code and, when the account's
--      one trial is still unused, starts the fortnight through 0049's
--      two-argument qamar_start_trial, recording source = 'pro'.
--   5. The one-argument qamar_start_trial (the free week, 0043/0049), which
--      the paywall, the lock card and onboarding's offer all reach through
--      /billing/trial/start, now records source = 'organic' itself instead
--      of leaving it to qamar_kill_metrics to infer (0059).
--   6. qamar_affiliate_snapshot also says whether this person's code is a
--      confirmed professional's, and how many days its clients get, so Me
--      promises clients the trial only when it is true, in the server's days.
--
-- Every refusal in qamar_redeem_pro_code is final for that code (it is not
-- there, is one's own, is not a professional's, or another professional's
-- code is already on the account), so each is a plain raise (P0001) and the
-- phone clears a waiting code on it. "not signed in" is about the session
-- and the phone keeps the code. A refusal that could pass later must use
-- another SQLSTATE (see the README's kill-metrics section).
--
-- Idempotent: if not exists, on conflict do nothing (a tuned value is kept),
-- create or replace.

-- 1. The fortnight's length -------------------------------------------------
insert into public.billing_config (key, value) values ('pro_trial_days', 14)
on conflict (key) do nothing;

-- 2. The operator's confirmation --------------------------------------------
alter table public.promo_codes
  add column if not exists professional boolean not null default false;

comment on column public.promo_codes.professional is
  'The operator has confirmed this affiliate code belongs to a nutritionist, coach or clinic (0069). Only then does a client who enters it get the fourteen-day trial. Set by the operator; never by a client.';

-- 3. The claim ----------------------------------------------------------------
create table if not exists public.pro_code_claims (
  user_id uuid primary key references auth.users (id) on delete cascade,
  promo_code_id uuid not null references public.promo_codes (id) on delete cascade,
  affiliate_user_id uuid not null references auth.users (id) on delete cascade,
  claimed_at timestamptz not null default now(),
  constraint pro_code_claims_not_self check (user_id <> affiliate_user_id)
);

alter table public.pro_code_claims enable row level security;
drop policy if exists pro_code_claims_select_own on public.pro_code_claims;
create policy pro_code_claims_select_own on public.pro_code_claims
  for select using (auth.uid() = user_id);
revoke insert, update, delete on public.pro_code_claims from anon, authenticated;

comment on table public.pro_code_claims is
  'The professional a person named in Me or through a /p/ link, before paying (0069). Written by qamar_redeem_pro_code only; read by the billing function when checkout carries no typed code.';

-- 5. The free week records where it came from -------------------------------
create or replace function public.qamar_start_trial(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_snap jsonb;
begin
  v_snap := public.qamar_start_trial(p_user_id, 7);
  update public.plus_trials set source = 'organic'
   where user_id = p_user_id and source is null;
  return v_snap;
end;
$$;
revoke all on function public.qamar_start_trial(uuid) from public, anon;
grant execute on function public.qamar_start_trial(uuid) to authenticated, service_role;

-- 4. The code, redeemed -------------------------------------------------------
create or replace function public.qamar_redeem_pro_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_norm text := upper(regexp_replace(coalesce(p_code, ''), '\s+', '', 'g'));
  v_promo public.promo_codes;
  v_claim public.pro_code_claims;
  v_days int := greatest(coalesce((select value from public.billing_config where key = 'pro_trial_days'), 14), 1);
  v_name text;
  v_trial boolean := false;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select * into v_promo
  from public.promo_codes
  where code = v_norm and kind = 'affiliate' and active and owner_user_id is not null;
  if not found then
    raise exception 'no nutritionist with that code';
  end if;
  if v_promo.owner_user_id = v_uid then
    raise exception 'that is your own code';
  end if;
  if not v_promo.professional then
    raise exception 'that code is not a nutritionist''s';
  end if;

  -- One professional per account, as at checkout (0039): a second code is a
  -- support conversation, not a race between codes. The same code again is
  -- simply the same claim.
  perform pg_advisory_xact_lock(hashtext('pro_code:' || v_uid::text));
  select * into v_claim from public.pro_code_claims where user_id = v_uid;
  if found and v_claim.promo_code_id <> v_promo.id then
    raise exception 'another nutritionist''s code is already on this account';
  end if;
  if not found then
    insert into public.pro_code_claims (user_id, promo_code_id, affiliate_user_id)
    values (v_uid, v_promo.id, v_promo.owner_user_id);
  end if;

  -- The fortnight, when the account's one trial is still unused. Someone who
  -- already had a trial, or paid, still has the professional on the account;
  -- the name and the share are the code's value, not the free days.
  if not exists (select 1 from public.plus_trials where user_id = v_uid)
     and not public.qamar_has_paid_plus(v_uid)
     and not public.qamar_is_plus(v_uid) then
    perform public.qamar_start_trial(v_uid, v_days);
    update public.plus_trials set source = 'pro' where user_id = v_uid;
    v_trial := true;
  end if;

  select coalesce(nullif(trim(name), ''), '') into v_name
  from public.profiles where user_id = v_promo.owner_user_id;

  return jsonb_build_object(
    'professional_name', coalesce(v_name, ''),
    'trial_days', case when v_trial then v_days else 0 end
  );
end;
$$;
revoke all on function public.qamar_redeem_pro_code(text) from public, anon;
grant execute on function public.qamar_redeem_pro_code(text) to authenticated, service_role;

-- 6. The professional's own view ------------------------------------------------
create or replace function public.qamar_affiliate_snapshot(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code text;
  v_professional boolean := false;
  v_days int := greatest(coalesce((select value from public.billing_config where key = 'pro_trial_days'), 14), 1);
  v_balance int := 0;
  v_earned int := 0;
  v_pending int := 0;
begin
  if auth.role() <> 'service_role' and (auth.uid() is null or auth.uid() <> p_user_id) then
    raise exception 'not authorised to read this affiliate wallet';
  end if;

  select code, professional into v_code, v_professional
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
    'professional', coalesce(v_professional, false),
    'client_trial_days', v_days,
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
