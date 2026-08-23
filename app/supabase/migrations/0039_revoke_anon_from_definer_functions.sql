-- Close the SECURITY DEFINER functions to the anon role.
--
-- Found by running the security advisor after applying the four migrations
-- that had been sitting in the repository unapplied. No ERRORs, but five
-- SECURITY DEFINER functions were reachable by an unauthenticated request
-- through /rest/v1/rpc.
--
-- All five already fail closed — each checks auth.uid() and raises when it is
-- null, which is exactly what anon is — so this is defence in depth rather
-- than a hole being plugged. But a guard inside a function body is a thing
-- someone can edit away by accident; a missing grant is not.
--
-- Revoking from anon does NOT affect this app's anonymous sign-in. A Supabase
-- anonymous session carries the `authenticated` role with is_anonymous = true;
-- `anon` is the role for requests carrying no session at all. Those two are
-- easy to confuse, and confusing them here would have looked like locking out
-- every user of the app.

revoke execute on function public.qamar_ai_quota_snapshot(uuid) from anon;
revoke execute on function public.qamar_entitlement_snapshot(uuid) from anon;
revoke execute on function public.qamar_policy(text) from anon;
revoke execute on function public.qamar_set_target(uuid) from anon;

-- Not part of the app's surface at all: an internal helper that should never
-- have been reachable over the wire.
revoke execute on function public.rls_auto_enable() from anon, authenticated;

notify pgrst, 'reload schema';
