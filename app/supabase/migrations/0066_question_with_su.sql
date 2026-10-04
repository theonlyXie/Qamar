-- The fourth question, bought with Su (O13, seat 4). Builds on 0065, which
-- made the day's last allowed use answered rather than taken and refused.
--
-- Until now Su bought extra meal photos and never a question: "questions have
-- no Su path — the fourth is Qamar+" (0041). So the economy paid only for
-- the routine act (logging) and never for the valuable one (asking), and the
-- free tier's third question was a dead end for anyone who would not pay.
-- The council agreed a way through that keeps the conversion trigger:
--   - the fourth question still meets the Qamar+ wall first, every time;
--   - under it, once a Cairo day, this one question can be bought with Su;
--   - it costs 800 Su, twice a photo, and the price is a su_economy_config
--     row so it can be tuned without a release.
--
-- What this adds:
--   1. The price and the day's allowance, as config rows.
--   2. ai_usage_days.chat_extra (questions bought today) and chat_extra_used
--      (of today's questions, how many were asked on a bought one: the tag).
--   3. chat_wall_days: the free tier's question wall, once a day per person,
--      so conversion after it can be read.
--   4. The chat_extra catalog item, whose price is read from config
--      (price_key) and which grants to the chat bucket (grants_bucket).
--   5. qamar_wallet_redeem (0042's, re-stated): the price from config when
--      the item names one, and a chat grant for the chat bucket.
--   6. qamar_ai_try_consume (0065's), refund and snapshot (0041's), re-stated: the chat
--      bucket reads chat_extra instead of a hardcoded 0, a question asked on
--      a bought one is tagged, a refund untags it, and a refused free-tier
--      question records the wall.
--   7. A diagnostic view, qamar_su_question_conversion: later conversion for
--      people who bought a question at the wall against people who only saw
--      the wall. Service role only.
-- Idempotent: every statement can run twice. A tuned price is never reset.

-- 1. The price and the allowance --------------------------------------------
insert into public.su_economy_config (key, value) values
  ('question_extra', 800),       -- one question past the free three, bought at the wall
  ('question_extra_daily', 1)    -- at most this many a Cairo day
on conflict (key) do nothing;

-- 2. The counters -------------------------------------------------------------
alter table public.ai_usage_days
  add column if not exists chat_extra int not null default 0 check (chat_extra >= 0),
  add column if not exists chat_extra_used int not null default 0 check (chat_extra_used >= 0);

comment on column public.ai_usage_days.chat_extra is
  'Questions bought with Su today (O13, 0066): at most su_economy_config.question_extra_daily.';
comment on column public.ai_usage_days.chat_extra_used is
  'Of today''s questions, how many were asked on a bought one: the tag on a question bought with Su.';
comment on column public.ai_usage_days.extra is
  'Extra photo scans bought with Su Points today. Questions bought with Su are chat_extra (0066).';

-- 3. The wall, as seen -------------------------------------------------------
create table if not exists public.chat_wall_days (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  first_at timestamptz not null default now(),
  hits int not null default 1 check (hits >= 1),
  primary key (user_id, day)
);
alter table public.chat_wall_days enable row level security;
revoke all on public.chat_wall_days from anon, authenticated;
comment on table public.chat_wall_days is
  'The free tier''s question wall, as met: one row per person per Cairo day a question was refused for the limit (0066). Written by qamar_ai_try_consume only.';

-- 4. The catalog item ----------------------------------------------------------
alter table public.wallet_catalog_items
  add column if not exists grants_bucket text not null default 'photo',
  add column if not exists price_key text;
alter table public.wallet_catalog_items drop constraint if exists wallet_catalog_items_grants_bucket_check;
alter table public.wallet_catalog_items add constraint wallet_catalog_items_grants_bucket_check check (grants_bucket in ('photo', 'chat'));

-- No monthly_limit: the day's allowance is question_extra_daily, held by the
-- grant below, so there is one number to tune.
insert into public.wallet_catalog_items (id, price, monthly_limit, grants_ai_uses, stackable, active, grants_bucket, price_key)
values ('chat_extra', 800, null, 1, true, true, 'chat', 'question_extra')
on conflict (id) do update set
  monthly_limit = excluded.monthly_limit,
  grants_ai_uses = excluded.grants_ai_uses,
  stackable = excluded.stackable,
  active = excluded.active,
  grants_bucket = excluded.grants_bucket,
  price_key = excluded.price_key;

-- The chat grant: one more question today, within the day's allowance.
create or replace function public.qamar_ai_grant_chat_extra(p_user_id uuid, p_uses int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := public.qamar_cairo_today();
  v_cap int := coalesce(public.qamar_su_value('question_extra_daily'), 1);
  v_extra int;
begin
  -- Called from the wallet redeem path, which has already proved ownership.
  if p_uses is null or p_uses <= 0 then
    raise exception 'extra questions must be positive';
  end if;

  insert into public.ai_usage_days (user_id, day)
  values (p_user_id, v_day)
  on conflict (user_id, day) do nothing;

  update public.ai_usage_days
     set chat_extra = chat_extra + p_uses, updated_at = now()
   where user_id = p_user_id and day = v_day
     and chat_extra + p_uses <= v_cap
   returning chat_extra into v_extra;

  if v_extra is null then
    raise exception 'daily question cap reached';
  end if;
  return v_extra;
end;
$$;
revoke all on function public.qamar_ai_grant_chat_extra(uuid, int) from public, anon, authenticated;

-- 5. Redeem (0042's, re-stated) ------------------------------------------------
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
  v_price_key text;
  v_available int;
  v_grants int;
  v_bucket text;
  v_stackable boolean;
  v_monthly int;
  v_used int;
  v_ledger public.su_point_ledger;
begin
  perform public.qamar_assert_wallet_owner(p_user_id);

  select price, price_key, grants_ai_uses, grants_bucket, stackable, monthly_limit
    into v_price, v_price_key, v_grants, v_bucket, v_stackable, v_monthly
  from public.wallet_catalog_items
  where id = p_catalog_item_id and active;
  if v_price is null then
    raise exception 'unknown or inactive catalog item %', p_catalog_item_id;
  end if;
  -- A price kept in config (0066): tuned there, without a release.
  if v_price_key is not null then
    v_price := coalesce(public.qamar_su_value(v_price_key), v_price);
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

  -- A grant that is refused (the day's allowance is used) raises, and the
  -- whole redemption, debit included, is rolled back.
  if coalesce(v_grants, 0) > 0 then
    if v_bucket = 'chat' then
      perform public.qamar_ai_grant_chat_extra(p_user_id, v_grants);
    else
      perform public.qamar_ai_grant_extra(p_user_id, v_grants);
    end if;
  end if;

  if p_catalog_item_id = 'streak_freeze' then
    insert into public.streak_freezes (user_id) values (p_user_id);
  end if;

  return v_ledger;
end;
$$;

revoke all on function public.qamar_wallet_redeem(uuid, text, text) from public, anon;
grant execute on function public.qamar_wallet_redeem(uuid, text, text) to authenticated;

-- 6. The chat bucket reads what was bought (0065's and 0041's, re-stated) --------
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
  v_chat_extra int := 0;
  v_chat_j jsonb;
begin
  if auth.role() <> 'service_role' and (auth.uid() is null or auth.uid() <> p_user_id) then
    raise exception 'not authorised to read this quota';
  end if;

  select photo_used, chat_used, plan_used, extra, chat_extra
    into v_photo, v_chat, v_plan, v_extra, v_chat_extra
  from public.ai_usage_days
  where user_id = p_user_id and day = v_day;

  v_photo := coalesce(v_photo, 0);
  v_chat := coalesce(v_chat, 0);
  v_plan := coalesce(v_plan, 0);
  v_extra := coalesce(v_extra, 0);
  v_chat_extra := coalesce(v_chat_extra, 0);

  v_chat_j := public.qamar_ai_bucket_json('chat', v_chat, public.qamar_ai_bucket_limit(p_user_id, 'chat'), v_chat_extra);

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

revoke all on function public.qamar_ai_quota_snapshot(uuid) from public, anon;
grant execute on function public.qamar_ai_quota_snapshot(uuid) to authenticated, service_role;

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
    case p_bucket when 'photo' then extra when 'chat' then chat_extra else 0 end
  into v_used, v_extra
  from public.ai_usage_days
  where user_id = p_user_id and day = v_day
  for update;

  v_cap := v_limit + v_extra;
  if v_used >= v_cap then
    -- The free tier's question wall, as met: once a day per person.
    if p_bucket = 'chat' and not public.qamar_is_plus(p_user_id) then
      insert into public.chat_wall_days (user_id, day) values (p_user_id, v_day)
      on conflict (user_id, day) do update set hits = public.chat_wall_days.hits + 1;
    end if;
    return public.qamar_ai_bucket_json(p_bucket, v_used, v_limit, v_extra)
      || jsonb_build_object('day', v_day, 'plus', public.qamar_is_plus(p_user_id));
  end if;

  update public.ai_usage_days
     set photo_used = photo_used + case when p_bucket = 'photo' then 1 else 0 end,
         chat_used  = chat_used  + case when p_bucket = 'chat'  then 1 else 0 end,
         plan_used  = plan_used  + case when p_bucket = 'plan'  then 1 else 0 end,
         -- Past the day's own questions, this one is a bought one: tag it.
         chat_extra_used = chat_extra_used + case when p_bucket = 'chat' and v_used >= v_limit then 1 else 0 end,
         updated_at = now()
   where user_id = p_user_id and day = v_day;

  -- Taken, so allowed: this call is answered (0065).
  return public.qamar_ai_bucket_json(p_bucket, v_used + 1, v_limit, v_extra)
    || jsonb_build_object('day', v_day, 'plus', public.qamar_is_plus(p_user_id), 'allowed', true);
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
  v_chat_limit int := 0;
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised to refund AI quota';
  end if;
  if p_bucket not in ('photo', 'chat', 'plan') then
    raise exception 'unknown quota bucket %', p_bucket;
  end if;
  if p_bucket = 'chat' then
    v_chat_limit := public.qamar_ai_bucket_limit(p_user_id, 'chat');
  end if;

  -- A refunded question that was a bought one gives the bought one back: it
  -- is untagged, and chat_extra still holds it for the next try.
  update public.ai_usage_days
     set chat_extra_used = greatest(chat_extra_used - case when p_bucket = 'chat' and chat_used - 1 >= v_chat_limit then 1 else 0 end, 0),
         photo_used = greatest(photo_used - case when p_bucket = 'photo' then 1 else 0 end, 0),
         chat_used  = greatest(chat_used  - case when p_bucket = 'chat'  then 1 else 0 end, 0),
         plan_used  = greatest(plan_used  - case when p_bucket = 'plan'  then 1 else 0 end, 0),
         updated_at = now()
   where user_id = p_user_id and day = v_day;

  return public.qamar_ai_quota_snapshot(p_user_id);
end;
$$;

revoke all on function public.qamar_ai_refund_consume(uuid, text) from public, anon, authenticated;
grant execute on function public.qamar_ai_refund_consume(uuid, text) to service_role;

comment on table public.ai_usage_days is
  'Cairo-day counters per bucket: photo (meal photos and body scans), chat (questions), plan (rebuilds). Typed/spoken logs never count. extra = Su-bought photo scans; chat_extra = Su-bought questions, chat_extra_used = questions asked on them.';

-- 7. The diagnostic: does a question bought at the wall lead to Qamar+? --------
--
-- Two groups of people who met the free tier's question wall (chat_wall_days):
-- su_buyer, who bought a question with Su at least once, and wall_only, who
-- never did. For each: how many there are, how many paid a Qamar+ order after
-- their first wall, and the same within 30 days, counted only over people
-- whose first wall is at least 30 days old so a young cohort does not read as
-- a low rate. Plus the questions bought and the questions asked on them.
-- Read with the service role; it aggregates across everyone.
create or replace view public.qamar_su_question_conversion as
with wall as (
  select user_id, min(first_at) as first_wall_at
  from public.chat_wall_days
  group by user_id
), bought as (
  select user_id, count(*)::int as questions_bought
  from public.wallet_redemptions
  where catalog_item_id = 'chat_extra' and status = 'redeemed'
  group by user_id
), asked as (
  select user_id, sum(chat_extra_used)::int as bought_questions_asked
  from public.ai_usage_days
  group by user_id
), people as (
  select
    w.user_id,
    w.first_wall_at,
    case when b.user_id is null then 'wall_only' else 'su_buyer' end as cohort,
    coalesce(b.questions_bought, 0) as questions_bought,
    coalesce(a.bought_questions_asked, 0) as bought_questions_asked,
    (select min(o.paid_at) from public.billing_orders o
      where o.user_id = w.user_id and o.status = 'paid' and o.paid_at > w.first_wall_at) as first_paid_after_wall
  from wall w
  left join bought b on b.user_id = w.user_id
  left join asked a on a.user_id = w.user_id
)
select
  cohort,
  count(*)::int as people,
  count(first_paid_after_wall)::int as paid_after_wall,
  round(100.0 * count(first_paid_after_wall) / nullif(count(*), 0), 1) as paid_after_wall_pct,
  count(*) filter (where first_wall_at <= now() - interval '30 days')::int as people_30_days_on,
  count(*) filter (where first_wall_at <= now() - interval '30 days'
                     and first_paid_after_wall <= first_wall_at + interval '30 days')::int as paid_within_30_days,
  round(100.0 * count(*) filter (where first_wall_at <= now() - interval '30 days'
                                   and first_paid_after_wall <= first_wall_at + interval '30 days')
        / nullif(count(*) filter (where first_wall_at <= now() - interval '30 days'), 0), 1) as paid_within_30_days_pct,
  sum(questions_bought)::int as questions_bought,
  sum(bought_questions_asked)::int as bought_questions_asked
from people
group by cohort;

revoke all on public.qamar_su_question_conversion from public, anon, authenticated;
grant select on public.qamar_su_question_conversion to service_role;

comment on view public.qamar_su_question_conversion is
  'O13 diagnostic (0066): later Qamar+ conversion for people who bought a question with Su at the wall (su_buyer) against people who only met the wall (wall_only). Service role only.';
