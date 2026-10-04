-- Daily drinking-water log. Separate from meals: water has no kcal, is not
-- analysed, and is not confirmed through the assistant. One row per glass
-- or bottle so Undo is a delete, not a rewrite.

create table if not exists public.water_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  amount_ml int not null check (amount_ml > 0),
  unit text not null check (unit in ('glass', 'bottle')),
  logged_at timestamptz not null default now()
);

create index if not exists water_logs_user_day_idx
  on public.water_logs (user_id, logged_at desc);

alter table public.water_logs enable row level security;

drop policy if exists water_logs_select_own on public.water_logs;
create policy water_logs_select_own on public.water_logs
  for select using (auth.uid() = user_id);

drop policy if exists water_logs_insert_own on public.water_logs;
create policy water_logs_insert_own on public.water_logs
  for insert with check (auth.uid() = user_id);

drop policy if exists water_logs_delete_own on public.water_logs;
create policy water_logs_delete_own on public.water_logs
  for delete using (auth.uid() = user_id);

comment on table public.water_logs is
  'Drinking water for a day. Glasses (250 ml) and bottles (500 ml). Not Su, not food.';
