-- `revoke ... from public` is not sufficient on Supabase: anon and
-- authenticated carry their own EXECUTE grants, so they must be revoked by
-- name. Without this, minting Su Points was reachable straight from the REST
-- API by anyone holding the publishable key.

revoke execute on function public.qamar_assert_wallet_owner(uuid) from anon, authenticated;
revoke execute on function public.qamar_wallet_credit(uuid, int, text, text) from anon, authenticated;

-- Spending stays a client action, but never anonymously.
revoke execute on function public.qamar_wallet_redeem(uuid, text, text) from anon;
grant execute on function public.qamar_wallet_redeem(uuid, text, text) to authenticated;
