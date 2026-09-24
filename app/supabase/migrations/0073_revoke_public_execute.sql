-- Finish the job 0071 started, and fix the way it was written.
--
-- 0071 said it closed five SECURITY DEFINER functions to `anon`. It closed
-- three. The security advisor still reports `qamar_policy` and
-- `rls_auto_enable` as anon-executable, and the ACLs say why:
--
--   qamar_policy      =X/postgres postgres=X/postgres authenticated=X/postgres
--   rls_auto_enable   =X/postgres postgres=X/postgres service_role=X/postgres
--
-- The leading `=X/postgres` is the grant to PUBLIC. Postgres gives every
-- function EXECUTE to PUBLIC on creation, and `anon` is a member of PUBLIC, so
-- `revoke execute ... from anon` removes a grant that was never the one doing
-- the work. The three functions 0071 did close were closed by a
-- `revoke all ... from public` in the migration that created them — not by
-- 0071 at all.
--
-- Revoking from a role that is inheriting the privilege is silent: no error,
-- no warning, and a migration that reads as though it worked. The only way to
-- know is to ask has_function_privilege afterwards, which is what the block at
-- the bottom of this file does.
--
-- Also closes the two trigger functions added in 0072. A trigger function
-- returns `trigger` and Postgres refuses to call one outside a trigger, so
-- nothing could have been done with them — but they were reachable, and the
-- rule here is that reachability is what gets fixed, not exploitability.
-- Triggers do not check EXECUTE on the function they fire, so revoking costs
-- nothing.

revoke execute on function public.qamar_policy(text) from public;
revoke execute on function public.rls_auto_enable() from public;

revoke execute on function public.qamar_on_meal_log_award() from public, anon, authenticated;
revoke execute on function public.qamar_on_first_target_award() from public, anon, authenticated;

notify pgrst, 'reload schema';

-- Assert rather than assume, because the failure mode being fixed here is a
-- revoke that does nothing and says nothing.
do $check$
declare
  bad text;
begin
  select string_agg(p.proname, ', ')
    into bad
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('qamar_policy', 'rls_auto_enable',
                      'qamar_on_meal_log_award', 'qamar_on_first_target_award')
    and has_function_privilege('anon', p.oid, 'execute');

  if bad is not null then
    raise exception 'still executable by anon: %', bad;
  end if;
end;
$check$;
