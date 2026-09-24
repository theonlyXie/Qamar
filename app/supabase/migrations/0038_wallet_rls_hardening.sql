-- Close the client-side path to minting Su Points.
--
-- 0001 created the row-level policies in a loop over ten tables, and gave every
-- one of them the same three: select, insert and update, each on
-- auth.uid() = user_id. That is right for profiles, targets, meals and weight —
-- the app writes those rows itself through PostgREST, and a user editing their
-- own data is the whole point of RLS.
--
-- It is wrong for the wallet. 0002 and 0003 built the wallet as RPC-only:
-- qamar_wallet_credit is EXECUTE-revoked from anon and authenticated, every
-- balance change goes through a SECURITY DEFINER function that inserts the
-- ledger row and updates the balance in one transaction, and the client-side
-- repository throws rather than pretend it can credit. None of that mattered,
-- because the same authenticated user could skip the RPC entirely and
-- `insert into su_point_ledger` or `update wallet_accounts set
-- available_points = 999999` straight through the REST API, and the policy
-- from 0001 said yes.
--
-- The three wallet tables keep select — the app reads its own balance and
-- ledger — and lose insert and update. Writes now reach them only through the
-- definer functions, which is what 0002 always assumed.

drop policy if exists wallet_accounts_insert_own on public.wallet_accounts;
drop policy if exists wallet_accounts_update_own on public.wallet_accounts;

drop policy if exists su_point_ledger_insert_own on public.su_point_ledger;
drop policy if exists su_point_ledger_update_own on public.su_point_ledger;

drop policy if exists wallet_redemptions_insert_own on public.wallet_redemptions;
drop policy if exists wallet_redemptions_update_own on public.wallet_redemptions;

-- Belt and braces: even with no policy, a table-level grant is what PostgREST
-- checks first. Supabase grants all on public tables to authenticated by
-- default; take the write half back on these three.
revoke insert, update, delete on public.wallet_accounts from anon, authenticated;
revoke insert, update, delete on public.su_point_ledger from anon, authenticated;
revoke insert, update, delete on public.wallet_redemptions from anon, authenticated;

comment on table public.su_point_ledger is
  'Append-only, server-written. Clients read; only qamar_wallet_credit / qamar_wallet_redeem (SECURITY DEFINER) write.';
comment on table public.wallet_accounts is
  'Balance projection of su_point_ledger. Clients read; only the wallet functions write.';
