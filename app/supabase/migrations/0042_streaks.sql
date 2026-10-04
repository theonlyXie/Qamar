-- Streaks and streak freezes.
--
-- A streak is days in a row (Cairo calendar) with at least one meal_logs row.
-- Nothing is stored for the streak itself: it is computed from meal_logs, so
-- it can never disagree with the Progress chart. What is stored is the
-- freeze: a wallet item that covers one empty day. One a month, bought with
-- Su Points, never with money.

-- ---------------------------------------------------------------------
-- Catalog item. monthly_limit is enforced below for non-stackable items over
-- the Cairo calendar month (0031 only enforced it as a daily cap for stackable
-- extras).
insert into public.wallet_catalog_items (id, price, monthly_limit, grants_ai_uses, stackable, active)
values ('streak_freeze', 600, 1, 0, false, true)
on conflict (id) do update set
  price = excluded.price,
  monthly_limit = excluded.monthly_limit,
  grants_ai_uses = excluded.grants_ai_uses,
  stackable = excluded.stackable,
  active = excluded.active;

create table if not exists public.streak_freezes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  redeemed_on date not null default public.qamar_cairo_today(),
  -- The empty day this token covered. Null while unused.
  used_on date,
  created_at timestamptz not null default now(),
  unique (user_id, used_on)
);
create index if not exists streak_freezes_user_idx on public.streak_freezes (user_id, used_on);

alter table public.streak_freezes enable row level security;
drop policy if exists streak_freezes_select_own on public.streak_freezes;
create policy streak_freezes_select_own on public.streak_freezes
  for select using (auth.uid() = user_id);
-- Written only by the functions below.
revoke insert, update, delete on public.streak_freezes from anon, authenticated;

-- ---------------------------------------------------------------------
-- Redeem: same as 0031, plus a monthly cap for non-stackable limited items
-- and the freeze token itself.
create or replace function public.qamar_wallet_redeem(
  p_user_id uuid,
  p_catalog_item_id text,
  p_idempotency_key text
) returns public.su_point_ledger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_price int;
  v_available int;
  v_grants int;
  v_stackable boolean;
  v_monthly int;
  v_used int;
  v_ledger public.su_point_ledger;
begin
  perform public.qamar_assert_wallet_owner(p_user_id);

  select price, grants_ai_uses, stackable, monthly_limit
    into v_price, v_grants, v_stackable, v_monthly
  from public.wallet_catalog_items
  where id = p_catalog_item_id and active;
  if v_price is null then
    raise exception 'unknown or inactive catalog item %', p_catalog_item_id;
  end if;

  if v_monthly is not null then
    if coalesce(v_stackable, false) then
      -- Stackable extras: monthly_limit is the per-day cap (ai_extra = 10).
      select count(*) into v_used
      from public.wallet_redemptions
      where user_id = p_user_id
        and catalog_item_id = p_catalog_item_id
        and status = 'redeemed'
        and (timezone('Africa/Cairo', created_at))::date = public.qamar_cairo_today();
      if v_used >= v_monthly then
        raise exception 'daily extra AI cap reached';
      end if;
    else
      -- Everything else: monthly_limit is monthly, Cairo calendar month.
      select count(*) into v_used
      from public.wallet_redemptions
      where user_id = p_user_id
        and catalog_item_id = p_catalog_item_id
        and status = 'redeemed'
        and date_trunc('month', timezone('Africa/Cairo', created_at))
          = date_trunc('month', public.qamar_cairo_today()::timestamp);
      if v_used >= v_monthly then
        raise exception 'monthly limit reached for %', p_catalog_item_id;
      end if;
    end if;
  end if;

  select available_points into v_available from public.wallet_accounts where user_id = p_user_id for update;
  if v_available is null or v_available < v_price then
    raise exception 'insufficient balance';
  end if;

  v_ledger := public.qamar_wallet_credit(p_user_id, -v_price, 'redemption:' || p_catalog_item_id, p_idempotency_key);

  insert into public.wallet_redemptions (user_id, catalog_item_id, ledger_id)
  values (p_user_id, p_catalog_item_id, v_ledger.id)
  on conflict do nothing;

  if coalesce(v_grants, 0) > 0 then
    perform public.qamar_ai_grant_extra(p_user_id, v_grants);
  end if;

  if p_catalog_item_id = 'streak_freeze' then
    insert into public.streak_freezes (user_id) values (p_user_id);
  end if;

  return v_ledger;
end;
$$;

revoke all on function public.qamar_wallet_redeem(uuid, text, text) from public;
grant execute on function public.qamar_wallet_redeem(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- The streak, computed. Walks back from today; today itself never breaks a
-- streak (it is not over). An empty day inside the run is covered by an
-- unused freeze if one exists — a token bought today can rescue yesterday,
-- never a day before it was bought minus one — and the token is marked used
-- so the same day is never covered twice and the token never covers two.
create or replace function public.qamar_streak_snapshot(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := public.qamar_cairo_today();
  v_cursor date;
  v_current int := 0;
  v_best int := 0;
  v_run int := 0;
  v_prev date;
  v_day date;
  v_today_counted boolean;
  v_freeze uuid;
  v_frozen date[] := '{}';
  v_available int;
begin
  perform public.qamar_assert_wallet_owner(p_user_id);

  create temp table if not exists _qamar_days (d date primary key) on commit drop;
  delete from _qamar_days;
  insert into _qamar_days
  select distinct (timezone('Africa/Cairo', logged_at))::date
  from public.meal_logs
  where user_id = p_user_id
  on conflict do nothing;
  insert into _qamar_days
  select used_on from public.streak_freezes
  where user_id = p_user_id and used_on is not null
  on conflict do nothing;

  v_today_counted := exists (select 1 from _qamar_days where d = v_today);
  v_cursor := case when v_today_counted then v_today else v_today - 1 end;

  loop
    if exists (select 1 from _qamar_days where d = v_cursor) then
      v_current := v_current + 1;
      v_cursor := v_cursor - 1;
      continue;
    end if;
    -- An empty day: only a gap between logged days is worth a freeze, and
    -- only while the run is alive (v_current > 0 or it is yesterday).
    exit when v_cursor < v_today - 1 and v_current = 0;
    select id into v_freeze
    from public.streak_freezes
    where user_id = p_user_id
      and used_on is null
      and redeemed_on - 1 <= v_cursor
    order by redeemed_on
    limit 1;
    exit when v_freeze is null;
    -- A freeze only bridges to a logged day; it never pads a run that has
    -- already ended.
    exit when not exists (select 1 from _qamar_days where d = v_cursor - 1);
    update public.streak_freezes set used_on = v_cursor where id = v_freeze;
    insert into _qamar_days values (v_cursor) on conflict do nothing;
    v_frozen := array_append(v_frozen, v_cursor);
    v_current := v_current + 1;
    v_cursor := v_cursor - 1;
  end loop;

  -- Best run over all data.
  for v_day in select d from _qamar_days order by d loop
    if v_prev is not null and v_day = v_prev + 1 then
      v_run := v_run + 1;
    else
      v_run := 1;
    end if;
    v_prev := v_day;
    if v_run > v_best then v_best := v_run; end if;
  end loop;
  if v_current > v_best then v_best := v_current; end if;

  select count(*) into v_available from public.streak_freezes
  where user_id = p_user_id and used_on is null;

  select coalesce(array_agg(used_on order by used_on), '{}') into v_frozen
  from public.streak_freezes
  where user_id = p_user_id and used_on is not null and used_on >= v_today - 60;

  return jsonb_build_object(
    'current', v_current,
    'best', v_best,
    'today_counted', v_today_counted,
    'freezes_available', v_available,
    'frozen_days', to_jsonb(v_frozen)
  );
end;
$$;

revoke all on function public.qamar_streak_snapshot(uuid) from public;
grant execute on function public.qamar_streak_snapshot(uuid) to authenticated;
