-- Daily AI allowance for the three model routes (chat, meal photo, plan),
-- and a Su Points scale that can sit on a leaderboard.
--
-- Five uses a day, shared. Talking to Qamar, photographing a plate, and writing
-- the menu all spend the same counter. Typing or speaking a meal does not: that
-- is the food graph, not the model. A body scan does not: that is onboarding,
-- not the nutritionist loop. Extra uses are bought with earned Su, not cash.
--
-- The old 20 / 5 / 3 wallet numbers stay in the historic ledger. New grants
-- use thousands so lifetime earned looks like a score.

-- ---------------------------------------------------------------------
-- Config (one row, so a later Plus bump is an UPDATE, not a release)
-- ---------------------------------------------------------------------

create table if not exists public.ai_quota_config (
  id text primary key default 'default',
  daily_limit int not null default 5 check (daily_limit >= 0),
  extra_daily_cap int not null default 10 check (extra_daily_cap >= 0),
  timezone text not null default 'Africa/Cairo'
);

insert into public.ai_quota_config (id, daily_limit, extra_daily_cap, timezone)
values ('default', 5, 10, 'Africa/Cairo')
on conflict (id) do nothing;

alter table public.ai_quota_config enable row level security;
drop policy if exists ai_quota_config_read on public.ai_quota_config;
create policy ai_quota_config_read on public.ai_quota_config for select using (true);

-- ---------------------------------------------------------------------
-- Per-person, per-Cairo-day counter
-- ---------------------------------------------------------------------

create table if not exists public.ai_usage_days (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  used int not null default 0 check (used >= 0),
  extra int not null default 0 check (extra >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.ai_usage_days enable row level security;
drop policy if exists ai_usage_days_select_own on public.ai_usage_days;
create policy ai_usage_days_select_own on public.ai_usage_days
  for select using (auth.uid() = user_id);

create or replace function public.qamar_cairo_today()
returns date
language sql
stable
set search_path = public
as $$
  select (timezone('Africa/Cairo', now()))::date;
$$;

revoke all on function public.qamar_cairo_today() from public;
grant execute on function public.qamar_cairo_today() to authenticated, service_role;

create or replace function public.qamar_ai_quota_snapshot(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_day date := public.qamar_cairo_today();
  v_limit int;
  v_extra_cap int;
  v_used int := 0;
  v_extra int := 0;
begin
  if auth.role() <> 'service_role' and (auth.uid() is null or auth.uid() <> p_user_id) then
    raise exception 'not authorised to read this quota';
  end if;

  select daily_limit, extra_daily_cap into v_limit, v_extra_cap
  from public.ai_quota_config where id = 'default';
  v_limit := coalesce(v_limit, 5);
  v_extra_cap := coalesce(v_extra_cap, 10);

  select used, extra into v_used, v_extra
  from public.ai_usage_days
  where user_id = p_user_id and day = v_day;

  v_used := coalesce(v_used, 0);
  v_extra := coalesce(v_extra, 0);

  return jsonb_build_object(
    'allowed', v_used < (v_limit + v_extra),
    'used', v_used,
    'limit', v_limit,
    'extra', v_extra,
    'remaining', greatest(v_limit + v_extra - v_used, 0),
    'extra_cap', v_extra_cap,
    'day', v_day
  );
end;
$$;

revoke all on function public.qamar_ai_quota_snapshot(uuid) from public;
grant execute on function public.qamar_ai_quota_snapshot(uuid) to authenticated, service_role;

create or replace function public.qamar_ai_try_consume(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := public.qamar_cairo_today();
  v_limit int;
  v_used int;
  v_extra int;
  v_cap int;
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised to consume AI quota';
  end if;

  select daily_limit into v_limit from public.ai_quota_config where id = 'default';
  v_limit := coalesce(v_limit, 5);

  insert into public.ai_usage_days (user_id, day, used, extra)
  values (p_user_id, v_day, 0, 0)
  on conflict (user_id, day) do nothing;

  select used, extra into v_used, v_extra
  from public.ai_usage_days
  where user_id = p_user_id and day = v_day
  for update;

  v_cap := v_limit + v_extra;
  if v_used >= v_cap then
    return jsonb_build_object(
      'allowed', false,
      'used', v_used,
      'limit', v_limit,
      'extra', v_extra,
      'remaining', 0,
      'day', v_day
    );
  end if;

  update public.ai_usage_days
     set used = used + 1, updated_at = now()
   where user_id = p_user_id and day = v_day
   returning used, extra into v_used, v_extra;

  return jsonb_build_object(
    'allowed', true,
    'used', v_used,
    'limit', v_limit,
    'extra', v_extra,
    'remaining', greatest(v_limit + v_extra - v_used, 0),
    'day', v_day
  );
end;
$$;

revoke all on function public.qamar_ai_try_consume(uuid) from public, anon, authenticated;
grant execute on function public.qamar_ai_try_consume(uuid) to service_role;

create or replace function public.qamar_ai_refund_consume(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := public.qamar_cairo_today();
  v_limit int;
  v_used int;
  v_extra int;
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised to refund AI quota';
  end if;

  select daily_limit into v_limit from public.ai_quota_config where id = 'default';
  v_limit := coalesce(v_limit, 5);

  update public.ai_usage_days
     set used = greatest(used - 1, 0), updated_at = now()
   where user_id = p_user_id and day = v_day
   returning used, extra into v_used, v_extra;

  if v_used is null then
    return public.qamar_ai_quota_snapshot(p_user_id);
  end if;

  return jsonb_build_object(
    'allowed', v_used < (v_limit + coalesce(v_extra, 0)),
    'used', v_used,
    'limit', v_limit,
    'extra', coalesce(v_extra, 0),
    'remaining', greatest(v_limit + coalesce(v_extra, 0) - v_used, 0),
    'day', v_day
  );
end;
$$;

revoke all on function public.qamar_ai_refund_consume(uuid) from public, anon, authenticated;
grant execute on function public.qamar_ai_refund_consume(uuid) to service_role;

create or replace function public.qamar_ai_grant_extra(p_user_id uuid, p_uses int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := public.qamar_cairo_today();
  v_cap int;
  v_extra int;
begin
  -- Called from the wallet redeem path, which has already proved ownership.
  if p_uses is null or p_uses <= 0 then
    raise exception 'extra uses must be positive';
  end if;

  select extra_daily_cap into v_cap from public.ai_quota_config where id = 'default';
  v_cap := coalesce(v_cap, 10);

  insert into public.ai_usage_days (user_id, day, used, extra)
  values (p_user_id, v_day, 0, 0)
  on conflict (user_id, day) do nothing;

  update public.ai_usage_days
     set extra = extra + p_uses, updated_at = now()
   where user_id = p_user_id and day = v_day
     and extra + p_uses <= v_cap
   returning extra into v_extra;

  if v_extra is null then
    raise exception 'daily extra AI cap reached';
  end if;

  return public.qamar_ai_quota_snapshot(p_user_id);
end;
$$;

revoke all on function public.qamar_ai_grant_extra(uuid, int) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Catalog: extra Qamar uses cost Su; cosmetics cost a welcome-stash
-- ---------------------------------------------------------------------

alter table public.wallet_catalog_items
  add column if not exists grants_ai_uses int not null default 0,
  add column if not exists stackable boolean not null default false;

insert into public.wallet_catalog_items (id, price, monthly_limit, grants_ai_uses, stackable, active)
values ('ai_extra', 400, 10, 1, true, true)
on conflict (id) do update set
  price = excluded.price,
  monthly_limit = excluded.monthly_limit,
  grants_ai_uses = excluded.grants_ai_uses,
  stackable = excluded.stackable,
  active = true;

update public.wallet_catalog_items
   set price = 400, grants_ai_uses = 1, stackable = true, monthly_limit = 10, active = false
 where id = 'photo';

update public.wallet_catalog_items
   set active = false
 where id = 'plan';

update public.wallet_catalog_items
   set price = 600, stackable = false, grants_ai_uses = 0, active = true
 where id = 'insight';

update public.wallet_catalog_items
   set price = 2500, stackable = false, grants_ai_uses = 0, active = true
 where id = 'cosmetic';

-- Spending an extra-use item also lengthens today's AI allowance.
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
  v_used_today int;
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
    select count(*) into v_used_today
    from public.wallet_redemptions
    where user_id = p_user_id
      and catalog_item_id = p_catalog_item_id
      and status = 'redeemed'
      and (timezone('Africa/Cairo', created_at))::date = public.qamar_cairo_today();
    -- monthly_limit on ai_extra is the per-day extra cap (10). Older items
    -- used it as a monthly cap; stackable extras are daily by design.
    if coalesce(v_stackable, false) and v_used_today >= v_monthly then
      raise exception 'daily extra AI cap reached';
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

  return v_ledger;
end;
$$;

revoke all on function public.qamar_wallet_redeem(uuid, text, text) from public;
grant execute on function public.qamar_wallet_redeem(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- Signup: 2,500. Existing 100-point bonuses are topped up, not rewritten.
-- ---------------------------------------------------------------------

create or replace function public.qamar_grant_signup_bonus()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.qamar_wallet_credit_internal(
    new.id,
    2500,
    'signup_bonus',
    'signup_bonus_' || new.id::text
  );
  return new;
exception
  when others then
    raise warning 'qamar_grant_signup_bonus failed for %: %', new.id, sqlerrm;
    return new;
end;
$$;

do $$
declare
  r record;
begin
  for r in
    select distinct user_id
    from public.su_point_ledger
    where reason = 'signup_bonus' and delta = 100
  loop
    begin
      perform public.qamar_wallet_credit_internal(
        r.user_id,
        2400,
        'economy_v2_signup_topup',
        'economy_v2_signup_topup_' || r.user_id::text
      );
    exception when others then
      raise warning 'economy_v2 topup failed for %: %', r.user_id, sqlerrm;
    end;
  end loop;
end $$;

alter table public.quests alter column su_points set default 250;
update public.quests set su_points = 250 where su_points = 5;

comment on table public.ai_usage_days is
  'Cairo-day counter for chat + meal photo + plan. Typed/spoken logs do not increment it. Extra is granted by spending Su.';
comment on column public.wallet_catalog_items.grants_ai_uses is
  'How many extra AI uses today this redemption adds. Zero for cosmetics.';
