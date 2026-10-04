-- Buying with Su: a retry is the purchase that already happened, and a
-- question is bought only at the free tier's wall (O13, seat 5's review of
-- 0066; seat 4).
--
-- A new migration rather than an edit to 0066 (unapplied, like everything
-- after 0056), so this review reads as its own diff. It re-states 0066's
-- qamar_wallet_redeem with three changes and nothing else:
--
-- 1. The account row is locked before anything else, so two calls for one
--    person run one after the other.
-- 2. A replay (a key already in the ledger for this person) returns that
--    ledger row and stops: no debit, no grant, no second redemption row.
--    Before, qamar_wallet_credit replayed without a second debit, but the
--    grant ran again. For a photo that was a free second photo; for the
--    day's question the grant hit the day's allowance and raised, so the
--    phone was told the purchase failed after 800 Su had been taken, and
--    the paid question was never asked. A key reused for a different item
--    is refused.
-- 3. The chat grant is only for a free-tier account that has met the day's
--    question limit (a chat_wall_days row for today, written when a question
--    is refused, 0066). A direct call could otherwise buy the question
--    before the fourth, lifting the day's limit so the fourth never met the
--    Qamar+ wall, and a member could buy a question they did not need.
--
-- Idempotent: create or replace, and the grants are re-stated.

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
  v_price_key text;
  v_available int;
  v_grants int;
  v_bucket text;
  v_stackable boolean;
  v_monthly int;
  v_used int;
  v_ledger public.su_point_ledger;
  v_replay public.su_point_ledger;
begin
  perform public.qamar_assert_wallet_owner(p_user_id);

  -- One redemption at a time for a person: the account row is locked
  -- first, so a retry and the call it retries cannot interleave.
  perform 1 from public.wallet_accounts where user_id = p_user_id for update;

  -- A key already in the ledger is the purchase that already happened (a
  -- retry after an answer lost on the way back): its ledger row, with no
  -- second debit, no second grant and no second redemption row (0067).
  select * into v_replay
  from public.su_point_ledger
  where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_replay.reason is distinct from 'redemption:' || p_catalog_item_id then
      raise exception 'this key was already used for something else';
    end if;
    return v_replay;
  end if;

  select price, price_key, grants_ai_uses, grants_bucket, stackable, monthly_limit
    into v_price, v_price_key, v_grants, v_bucket, v_stackable, v_monthly
  from public.wallet_catalog_items
  where id = p_catalog_item_id and active;
  if v_price is null then
    raise exception 'unknown or inactive catalog item %', p_catalog_item_id;
  end if;
  -- A price kept in config (0066): tuned there, without a release.
  if v_price_key is not null then
    v_price := coalesce(public.qamar_su_value(v_price_key), v_price);
  end if;

  -- A question is bought only at the free tier's wall (O13, 0067): the
  -- person is not a member, and a question of theirs was refused for the
  -- day's limit today. Bought earlier, it would lift the limit so the fourth
  -- question never met the Qamar+ wall; a member has no wall to meet.
  if v_bucket = 'chat' and coalesce(v_grants, 0) > 0 then
    if public.qamar_is_plus(p_user_id) then
      raise exception 'a member''s questions are not bought with Su';
    end if;
    if not exists (
      select 1 from public.chat_wall_days
      where user_id = p_user_id and day = public.qamar_cairo_today()
    ) then
      raise exception 'a question is bought only at the day''s question limit';
    end if;
  end if;

  if v_monthly is not null then
    if coalesce(v_stackable, false) then
      -- Stackable extras: monthly_limit is the per-day cap (ai_extra = 10).
      select count(*) into v_used
      from public.wallet_redemptions
      where user_id = p_user_id
        and catalog_item_id = p_catalog_item_id
        and status = 'redeemed'
        and (timezone('Africa/Cairo', created_at))::date = public.qamar_cairo_today();
      if v_used >= v_monthly then
        raise exception 'daily extra AI cap reached';
      end if;
    else
      -- Everything else: monthly_limit is monthly, Cairo calendar month.
      select count(*) into v_used
      from public.wallet_redemptions
      where user_id = p_user_id
        and catalog_item_id = p_catalog_item_id
        and status = 'redeemed'
        and date_trunc('month', timezone('Africa/Cairo', created_at))
          = date_trunc('month', public.qamar_cairo_today()::timestamp);
      if v_used >= v_monthly then
        raise exception 'monthly limit reached for %', p_catalog_item_id;
      end if;
    end if;
  end if;

  select available_points into v_available from public.wallet_accounts where user_id = p_user_id for update;
  if v_available is null or v_available < v_price then
    raise exception 'insufficient balance';
  end if;

  v_ledger := public.qamar_wallet_credit(p_user_id, -v_price, 'redemption:' || p_catalog_item_id, p_idempotency_key);

  insert into public.wallet_redemptions (user_id, catalog_item_id, ledger_id)
  values (p_user_id, p_catalog_item_id, v_ledger.id)
  on conflict do nothing;

  -- A grant that is refused (the day's allowance is used) raises, and the
  -- whole redemption, debit included, is rolled back.
  if coalesce(v_grants, 0) > 0 then
    if v_bucket = 'chat' then
      perform public.qamar_ai_grant_chat_extra(p_user_id, v_grants);
    else
      perform public.qamar_ai_grant_extra(p_user_id, v_grants);
    end if;
  end if;

  if p_catalog_item_id = 'streak_freeze' then
    insert into public.streak_freezes (user_id) values (p_user_id);
  end if;

  return v_ledger;
end;
$$;

revoke all on function public.qamar_wallet_redeem(uuid, text, text) from public, anon;
grant execute on function public.qamar_wallet_redeem(uuid, text, text) to authenticated;
