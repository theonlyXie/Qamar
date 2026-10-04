-- Pressing Start, recorded on the account.
--
-- Intake completion is "users who reach the plan reveal / users who press
-- Start" in the blueprint. 0047 could not count the second half: nothing on
-- the server knew who pressed Start, so it used the first saved answer (the
-- profiles row, written when the first question is answered). That was
-- already after the step people leave at. Now the app writes one row here
-- at the tap — the chat or the report, before any answer — and the first
-- row on the account is the one kept.
--
-- The metric that reads it is in the kill-metrics migration that replaces
-- qamar_kill_metrics as a whole (0059). The table stands on its own, so the
-- app can begin writing before that lands.
--
-- Idempotent against the live database: if not exists, drop policy if
-- exists.

create table if not exists public.intake_starts (
  user_id uuid primary key references auth.users (id) on delete cascade,
  started_at timestamptz not null default now(),
  via text not null default 'chat' check (via in ('chat', 'scan'))
);

alter table public.intake_starts enable row level security;
drop policy if exists intake_starts_select_own on public.intake_starts;
create policy intake_starts_select_own on public.intake_starts for select using (auth.uid() = user_id);
drop policy if exists intake_starts_insert_own on public.intake_starts;
create policy intake_starts_insert_own on public.intake_starts for insert with check (auth.uid() = user_id);
-- The first Start is the one kept. The app inserts with "ignore duplicates",
-- and nobody moves or removes the row afterwards.
revoke update, delete on public.intake_starts from anon, authenticated;
