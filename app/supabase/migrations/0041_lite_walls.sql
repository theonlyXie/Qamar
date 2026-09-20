-- The blueprint's walls: three photos and three questions a day on Lite.
--
-- 0031 gave everyone one shared counter of five model calls a day, and the
-- app gated meal photos behind Qamar+ entirely. The blueprint is specific and
-- different: a Lite user photographs three meals a day for free and asks Su
-- three questions a day for free; the fourth question is the paywall, and
-- extra photos are what earned Su Points buy. Typing or speaking a meal is
-- never counted. Writing today's plan is not a wall either — it is the product
-- — so it has its own small daily cap that exists only to stop a loop.
--
-- One counter per bucket, one config row with the limits for each tier, and
-- the entitlement decides which column applies. `used` from 0031 stays as a
-- column nobody reads; dropping it buys nothing.

alter table public.ai_quota_config
  add column if not exists lite_photo_daily int not null default 3 check (lite_photo_daily >= 0),
  add column if not exists lite_chat_daily  int not null default 3 check (lite_chat_daily >= 0),
  add column if not exists plus_photo_daily int not null default 30 check (plus_photo_daily >= 0),
  add column if not exists plus_chat_daily  int not null default 50 check (plus_chat_daily >= 0),
  add column if not exists plan_daily       int not null default 3 check (plan_daily >= 0);

alter table public.ai_usage_days
  add column if not exists photo_used int not null default 0 check (photo_used >= 0),
  add column if not exists chat_used  int not null default 0 check (chat_used >= 0),
  add column if not exists plan_used  int not null default 0 check (plan_used >= 0);

comment on column public.ai_usage_days.extra is
  'Extra photo scans bought with Su Points today. Applies to the photo bucket only; questions have no Su path — the fourth one is Qamar+.';

-- ---------------------------------------------------------------------
-- Which tier
-- ---------------------------------------------------------------------

create or replace function public.qamar_is_plus(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.entitlements
    where user_id = p_user_id
      and status = 'active'
      and (period_end is null or period_end >= now())
  );
$$;

revoke all on function public.qamar_is_plus(uuid) from public, anon;
grant execute on function public.qamar_is_plus(uuid) to authenticated, service_role;

-- The limit for one bucket on one person's tier. Plan is the same for both.
create or replace function public.qamar_ai_bucket_limit(p_user_id uuid, p_bucket text)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c public.ai_quota_config;
  v_plus boolean := public.qamar_is_plus(p_user_id);
begin
  select * into c from public.ai_quota_config where id = 'default';
  if not found then
    return case p_bucket when 'photo' then 3 when 'chat' then 3 else 3 end;
  end if;
  return case p_bucket
    when 'photo' then case when v_plus then c.plus_photo_daily else c.lite_photo_daily end
    when 'chat'  then case when v_plus then c.plus_chat_daily  else c.lite_chat_daily  end
    when 'plan'  then c.plan_daily
    else 0
  end;
end;
$$;

revoke all on function public.qamar_ai_bucket_limit(uuid, text) from public, anon, authenticated;
grant execute on function public.qamar_ai_bucket_limit(uuid, text) to service_role;

-- ---------------------------------------------------------------------
-- Snapshot: every bucket, plus the flat chat fields older clients read
-- ---------------------------------------------------------------------

create or replace function public.qamar_ai_bucket_json(
  p_bucket text, p_used int, p_limit int, p_extra int
) returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'bucket', p_bucket,
    'used', p_used,
    'limit', p_limit,
    'extra', p_extra,
    'remaining', greatest(p_limit + p_extra - p_used, 0),
    'allowed', p_used < (p_limit + p_extra)
  );
$$;

create or replace function public.qamar_ai_quota_snapshot(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_day date := public.qamar_cairo_today();
  v_photo int := 0;
  v_chat int := 0;
  v_plan int := 0;
  v_extra int := 0;
  v_chat_j jsonb;
begin
  if auth.role() <> 'service_role' and (auth.uid() is null or auth.uid() <> p_user_id) then
    raise exception 'not authorised to read this quota';
  end if;

  select photo_used, chat_used, plan_used, extra
    into v_photo, v_chat, v_plan, v_extra
  from public.ai_usage_days
  where user_id = p_user_id and day = v_day;

  v_photo := coalesce(v_photo, 0);
  v_chat := coalesce(v_chat, 0);
  v_plan := coalesce(v_plan, 0);
  v_extra := coalesce(v_extra, 0);

  v_chat_j := public.qamar_ai_bucket_json('chat', v_chat, public.qamar_ai_bucket_limit(p_user_id, 'chat'), 0);

  -- The flat fields are the chat bucket, for anything still reading the 0031 shape.
  return v_chat_j || jsonb_build_object(
    'day', v_day,
    'plus', public.qamar_is_plus(p_user_id),
    'chat', v_chat_j,
    'photo', public.qamar_ai_bucket_json('photo', v_photo, public.qamar_ai_bucket_limit(p_user_id, 'photo'), v_extra),
    'plan', public.qamar_ai_bucket_json('plan', v_plan, public.qamar_ai_bucket_limit(p_user_id, 'plan'), 0)
  );
end;
$$;

revoke all on function public.qamar_ai_quota_snapshot(uuid) from public;
grant execute on function public.qamar_ai_quota_snapshot(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- Consume and refund, per bucket. The one-argument forms from 0031 go, so
-- PostgREST has one function to resolve.
-- ---------------------------------------------------------------------

drop function if exists public.qamar_ai_try_consume(uuid);
drop function if exists public.qamar_ai_refund_consume(uuid);

create or replace function public.qamar_ai_try_consume(p_user_id uuid, p_bucket text default 'chat')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := public.qamar_cairo_today();
  v_limit int;
  v_used int;
  v_extra int := 0;
  v_cap int;
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised to consume AI quota';
  end if;
  if p_bucket not in ('photo', 'chat', 'plan') then
    raise exception 'unknown quota bucket %', p_bucket;
  end if;

  v_limit := public.qamar_ai_bucket_limit(p_user_id, p_bucket);

  insert into public.ai_usage_days (user_id, day)
  values (p_user_id, v_day)
  on conflict (user_id, day) do nothing;

  select
    case p_bucket when 'photo' then photo_used when 'chat' then chat_used else plan_used end,
    case p_bucket when 'photo' then extra else 0 end
  into v_used, v_extra
  from public.ai_usage_days
  where user_id = p_user_id and day = v_day
  for update;

  v_cap := v_limit + v_extra;
  if v_used >= v_cap then
    return public.qamar_ai_bucket_json(p_bucket, v_used, v_limit, v_extra)
      || jsonb_build_object('day', v_day, 'plus', public.qamar_is_plus(p_user_id));
  end if;

  update public.ai_usage_days
     set photo_used = photo_used + case when p_bucket = 'photo' then 1 else 0 end,
         chat_used  = chat_used  + case when p_bucket = 'chat'  then 1 else 0 end,
         plan_used  = plan_used  + case when p_bucket = 'plan'  then 1 else 0 end,
         updated_at = now()
   where user_id = p_user_id and day = v_day;

  return public.qamar_ai_bucket_json(p_bucket, v_used + 1, v_limit, v_extra)
    || jsonb_build_object('day', v_day, 'plus', public.qamar_is_plus(p_user_id));
end;
$$;

revoke all on function public.qamar_ai_try_consume(uuid, text) from public, anon, authenticated;
grant execute on function public.qamar_ai_try_consume(uuid, text) to service_role;

create or replace function public.qamar_ai_refund_consume(p_user_id uuid, p_bucket text default 'chat')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := public.qamar_cairo_today();
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised to refund AI quota';
  end if;
  if p_bucket not in ('photo', 'chat', 'plan') then
    raise exception 'unknown quota bucket %', p_bucket;
  end if;

  update public.ai_usage_days
     set photo_used = greatest(photo_used - case when p_bucket = 'photo' then 1 else 0 end, 0),
         chat_used  = greatest(chat_used  - case when p_bucket = 'chat'  then 1 else 0 end, 0),
         plan_used  = greatest(plan_used  - case when p_bucket = 'plan'  then 1 else 0 end, 0),
         updated_at = now()
   where user_id = p_user_id and day = v_day;

  return public.qamar_ai_quota_snapshot(p_user_id);
end;
$$;

revoke all on function public.qamar_ai_refund_consume(uuid, text) from public, anon, authenticated;
grant execute on function public.qamar_ai_refund_consume(uuid, text) to service_role;

-- The catalog item that used to buy "another use" now buys another photo,
-- which is the one thing Su can buy here. Questions have no Su path.
update public.wallet_catalog_items
   set grants_ai_uses = 1, stackable = true, monthly_limit = 10, active = true
 where id = 'ai_extra';

comment on table public.ai_usage_days is
  'Cairo-day counters per bucket: photo (meal photos and body scans), chat (questions), plan (rebuilds). Typed/spoken logs never count. extra = Su-bought photo scans.';
