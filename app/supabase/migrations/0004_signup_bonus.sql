-- 100 Su Points on sign-up.
--
-- Done as a trigger on auth.users rather than a client call, because the
-- client cannot credit points (migration 0003) and must not be able to: if the
-- app could award the bonus, a user could award it to themselves repeatedly.
-- The trigger runs as the definer, inside the same transaction that creates
-- the user, so the wallet exists before the app's first read.
--
-- The idempotency key is fixed per user, so the ledger's
-- (user_id, idempotency_key) uniqueness makes a replay a no-op.

create or replace function public.qamar_grant_signup_bonus()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.qamar_wallet_credit(
    new.id,
    100,
    'signup_bonus',
    'signup_bonus_' || new.id::text
  );
  return new;
exception
  -- A wallet problem must never stop someone signing up. Log and continue;
  -- the bonus can be reconciled later from the ledger.
  when others then
    raise warning 'qamar_grant_signup_bonus failed for %: %', new.id, sqlerrm;
    return new;
end;
$$;

drop trigger if exists qamar_on_auth_user_created on auth.users;
create trigger qamar_on_auth_user_created
  after insert on auth.users
  for each row execute function public.qamar_grant_signup_bonus();

revoke all on function public.qamar_grant_signup_bonus() from public, anon, authenticated;

-- Backfill anyone who already exists, so the rule is not "100 points if you
-- signed up after this migration".
do $$
declare
  u record;
begin
  for u in select id from auth.users loop
    begin
      perform public.qamar_wallet_credit(u.id, 100, 'signup_bonus', 'signup_bonus_' || u.id::text);
    exception when others then
      raise warning 'backfill failed for %: %', u.id, sqlerrm;
    end;
  end loop;
end $$;
