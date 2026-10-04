-- Activity, logged by hand: football, a walk, the gym, a run.
--
-- The blueprint's Log node has four branches — photo, voice, repeat a meal,
-- activity — and "passive steps; manual activity quick-log (football, walk,
-- gym)" is on the must list. This is the manual half: the phone writes what
-- the person did and for how long, with an estimate of what it cost, and
-- the server pays a small earn for the row like it does for water. Steps
-- from the phone's health store come later and land in the same table.

create table if not exists public.activity_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('football', 'walk', 'gym', 'run', 'other')),
  minutes int not null check (minutes between 1 and 600),
  -- MET × kg × hours, computed on the phone from the profile's weight. An
  -- estimate, shown as one; never added to the food budget.
  kcal_est int not null check (kcal_est >= 0),
  logged_at timestamptz not null default now()
);
create index if not exists activity_logs_user_day_idx on public.activity_logs (user_id, logged_at desc);

alter table public.activity_logs enable row level security;
drop policy if exists activity_logs_select_own on public.activity_logs;
create policy activity_logs_select_own on public.activity_logs for select using (auth.uid() = user_id);
drop policy if exists activity_logs_insert_own on public.activity_logs;
create policy activity_logs_insert_own on public.activity_logs for insert with check (auth.uid() = user_id);
revoke update, delete on public.activity_logs from anon, authenticated;

-- The operator's number, under the daily cap like every other earn.
insert into public.su_economy_config (key, value) values ('activity_logged', 50)
on conflict (key) do update set value = excluded.value;

create or replace function public.qamar_earn_on_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.qamar_su_earn(
    new.user_id,
    coalesce(public.qamar_su_value('activity_logged'), 50),
    'activity_logged',
    'activity:' || new.id::text
  );
  return new;
exception
  when others then
    raise warning 'qamar_earn_on_activity failed for %: %', new.user_id, sqlerrm;
    return new;
end;
$$;
revoke all on function public.qamar_earn_on_activity() from public, anon, authenticated;

drop trigger if exists qamar_on_activity_logged on public.activity_logs;
create trigger qamar_on_activity_logged
  after insert on public.activity_logs
  for each row execute function public.qamar_earn_on_activity();
