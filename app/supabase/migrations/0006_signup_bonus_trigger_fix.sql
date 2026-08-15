-- The signup bonus never paid out.
--
-- 0004 hangs the bonus off a trigger on auth.users and credits it through
-- public.qamar_wallet_credit, which opens by calling qamar_assert_wallet_owner.
-- That guard permits exactly two callers: the service role, and a signed-in
-- user acting on their own wallet. A trigger firing inside GoTrue's INSERT is
-- neither. There is no request context at that moment — auth.role() and
-- auth.uid() are both null, because the row being inserted *is* the user and
-- no session for them exists yet — so the guard raises 'not authorised to
-- modify this wallet' on every single signup.
--
-- 0004's handler then catches the exception and returns new, by design: a
-- wallet problem must never stop someone signing up. The cost is that the
-- failure is invisible. The migration reports success, the trigger exists, the
-- backfill loop completes, and not one point is ever credited. Verified
-- against the live project: a fresh signup produced no wallet row, no ledger
-- row and a null balance.
--
-- The guard is right and stays. What was wrong is routing a trusted
-- server-side credit through the entry point built to be reachable by clients.
-- So the crediting body moves into an internal function with no ownership
-- check, and the two callers are separated by trust rather than sharing one
-- door:
--
--   qamar_wallet_credit           -- public entry point; asserts, then delegates
--   qamar_wallet_credit_internal  -- trusted; no assert; execute revoked from all
--
-- The internal function is not a new privilege. It is the code that already
-- ran as SECURITY DEFINER, with the check that could never pass removed and
-- EXECUTE revoked from public, anon and authenticated so no client can reach
-- it. Idempotency is unchanged and still carries the whole safety argument:
-- (user_id, idempotency_key) is unique, and the bonus key is fixed per user,
-- so a replay is a no-op no matter who triggers it.

create or replace function public.qamar_wallet_credit_internal(
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
    select * into v_ledger from public.su_point_ledger
      where user_id = p_user_id and idempotency_key = p_idempotency_key;
  end if;

  return v_ledger;
end;
$$;

-- Unreachable from the REST API. anon and authenticated carry their own
-- EXECUTE grants on Supabase and must be revoked by name, per 0003.
revoke all on function public.qamar_wallet_credit_internal(uuid, int, text, text) from public;
revoke execute on function public.qamar_wallet_credit_internal(uuid, int, text, text) from anon, authenticated;

-- The public entry point keeps its guard and delegates the work. Behaviour
-- for every existing caller is unchanged.
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
begin
  perform public.qamar_assert_wallet_owner(p_user_id);
  return public.qamar_wallet_credit_internal(
    p_user_id, p_delta, p_reason, p_idempotency_key);
end;
$$;

-- 0003's revocations are preserved by `create or replace`, but are restated
-- here so this file does not depend on that to stay true.
revoke execute on function public.qamar_wallet_credit(uuid, int, text, text) from anon, authenticated;

-- The trigger now credits through the internal function.
create or replace function public.qamar_grant_signup_bonus()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.qamar_wallet_credit_internal(
    new.id,
    100,
    'signup_bonus',
    'signup_bonus_' || new.id::text
  );
  return new;
exception
  -- Still swallowed: a wallet problem must never stop someone signing up.
  -- The warning is the only trace, so if the bonus goes missing again, look
  -- for it in the Postgres logs rather than in the API response.
  when others then
    raise warning 'qamar_grant_signup_bonus failed for %: %', new.id, sqlerrm;
    return new;
end;
$$;

revoke all on function public.qamar_grant_signup_bonus() from public, anon, authenticated;

-- Backfill everyone 0004 was supposed to have covered and silently did not.
-- The fixed idempotency key means anyone who somehow already has the bonus is
-- skipped rather than paid twice.
do $$
declare
  u record;
begin
  for u in select id from auth.users loop
    perform public.qamar_wallet_credit_internal(
      u.id, 100, 'signup_bonus', 'signup_bonus_' || u.id::text);
  end loop;
end $$;
