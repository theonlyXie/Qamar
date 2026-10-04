-- One onboarding bonus, whichever path pays it (found while merging
-- claude/connector-status-check-xsmlnq into PR #18).
--
-- Two paths pay the 1,000 Su for finishing onboarding, one from each line of
-- work, and both are live: 0072's trigger on the first targets row, keyed
-- onboarding:<user>, and 0046's qamar_grant_onboarding, which the app calls at
-- the reveal, keyed onboarding_<user>. The ledger refuses a key it already
-- holds, but these are two keys, so someone who finished onboarding in this
-- app would have been paid twice. Nobody has been: on 24 September the live
-- ledger held five onboarding:<user> rows and no onboarding_<user> row.
--
-- qamar_grant_onboarding now pays under the trigger's key, so the ledger stops
-- the second payment whichever path comes first, and it still answers
-- credited 0 to anyone already paid under the old key. The trigger is
-- unchanged: the builds already on phones earn through it.
--
-- Idempotent: create or replace, and the grants are re-stated.

create or replace function public.qamar_grant_onboarding(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := 'onboarding:' || p_user_id::text;
  v_amount int := coalesce(public.qamar_su_value('onboarding'), 1000);
begin
  perform public.qamar_assert_wallet_owner(p_user_id);
  if exists (
    select 1 from public.su_point_ledger
    where user_id = p_user_id
      and idempotency_key in (v_key, 'onboarding_' || p_user_id::text)
  ) then
    return jsonb_build_object('credited', 0);
  end if;
  perform public.qamar_wallet_credit_internal(p_user_id, v_amount, 'onboarding', v_key);
  return jsonb_build_object('credited', v_amount);
end;
$$;

revoke all on function public.qamar_grant_onboarding(uuid) from public, anon;
grant execute on function public.qamar_grant_onboarding(uuid) to authenticated, service_role;
