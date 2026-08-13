-- Atomic wallet operations: every balance change is a ledger insert plus a
-- wallet_accounts update in one transaction, guarded by the ledger's
-- (user_id, idempotency_key) uniqueness so retried client calls can't
-- double-credit or double-spend.

create or replace function public.qamar_wallet_credit(
  p_user_id uuid,
  p_delta int,
  p_reason text,
  p_idempotency_key text
) returns public.su_point_ledger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_available int;
  v_new_lifetime int;
  v_ledger public.su_point_ledger;
begin
  if p_delta = 0 then
    raise exception 'delta must be non-zero';
  end if;

  insert into public.wallet_accounts (user_id, available_points, lifetime_earned)
  values (p_user_id, 0, 0)
  on conflict (user_id) do nothing;

  update public.wallet_accounts
    set available_points = available_points + p_delta,
        lifetime_earned = lifetime_earned + greatest(p_delta, 0),
        updated_at = now()
    where user_id = p_user_id
    returning available_points, lifetime_earned into v_new_available, v_new_lifetime;

  insert into public.su_point_ledger (user_id, delta, reason, idempotency_key, balance_after)
  values (p_user_id, p_delta, p_reason, p_idempotency_key, v_new_available)
  on conflict (user_id, idempotency_key) do nothing
  returning * into v_ledger;

  -- Replay of an already-applied idempotency key: roll the balance update
  -- back and return the original ledger row instead of crediting twice.
  if v_ledger is null then
    update public.wallet_accounts
      set available_points = available_points - p_delta,
          lifetime_earned = lifetime_earned - greatest(p_delta, 0),
          updated_at = now()
      where user_id = p_user_id;
    select * into v_ledger from public.su_point_ledger where user_id = p_user_id and idempotency_key = p_idempotency_key;
  end if;

  return v_ledger;
end;
$$;

create or replace function public.qamar_wallet_redeem(
  p_user_id uuid,
  p_catalog_item_id text,
  p_idempotency_key text
) returns public.su_point_ledger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_price int;
  v_available int;
  v_ledger public.su_point_ledger;
begin
  select price into v_price from public.wallet_catalog_items where id = p_catalog_item_id and active;
  if v_price is null then
    raise exception 'unknown or inactive catalog item %', p_catalog_item_id;
  end if;

  select available_points into v_available from public.wallet_accounts where user_id = p_user_id for update;
  if v_available is null or v_available < v_price then
    raise exception 'insufficient balance';
  end if;

  v_ledger := public.qamar_wallet_credit(p_user_id, -v_price, 'redemption:' || p_catalog_item_id, p_idempotency_key);

  insert into public.wallet_redemptions (user_id, catalog_item_id, ledger_id)
  values (p_user_id, p_catalog_item_id, v_ledger.id)
  on conflict do nothing;

  return v_ledger;
end;
$$;

revoke all on function public.qamar_wallet_credit(uuid, int, text, text) from public;
revoke all on function public.qamar_wallet_redeem(uuid, text, text) from public;
grant execute on function public.qamar_wallet_credit(uuid, int, text, text) to authenticated;
grant execute on function public.qamar_wallet_redeem(uuid, text, text) to authenticated;
