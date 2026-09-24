-- Su Points are earned on the server, or they are not earned at all.
--
-- Until now exactly one thing credited a wallet: the signup bonus trigger.
-- Everything else — finishing onboarding, the first meal, every meal after it,
-- the daily quest — was `_credit()` in app_state.dart, which adds to two
-- integers in Dart memory and inserts a row into a local list. The next
-- hydrate reads the real balance from the database and the points vanish. The
-- ledger proves it: six `signup_bonus` rows, five `economy_v2_signup_topup`
-- rows, and nothing else, against a database that already holds meal logs and
-- five confirmed target rows.
--
-- So the client is not the place to decide what was earned. A client can be
-- replayed, restarted, patched or lied to; the four awards below are triggers
-- and one RPC, each keyed by an idempotency string that
-- `qamar_wallet_credit_internal` enforces with a unique constraint. Awarding
-- twice is not prevented by remembering — it is prevented by the database
-- refusing the second row and rolling the balance back.
--
-- Amounts match SuEconomy in app/lib/models/su_economy.dart:
--   onboarding 1000, first meal 500, each later meal 100, daily quest 250.
--
-- The award section is adapted from `0038_mvp_closeout.sql` on
-- cursor/finish-mvp-d6e0, which had the right shape; the changes here are the
-- quest returning a reason instead of raising, and the backfill at the end.

-- ---------------------------------------------------------------------------
-- Meals: the first one is worth more than the ones after it
-- ---------------------------------------------------------------------------
create or replace function public.qamar_on_meal_log_award()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meal_count int;
begin
  -- AFTER INSERT, so the row just written is included: 1 means this is it.
  select count(*) into meal_count
  from public.meal_logs
  where user_id = new.user_id;

  if meal_count = 1 then
    perform public.qamar_wallet_credit_internal(
      new.user_id, 500, 'first_meal', 'first_meal:' || new.user_id::text);
  else
    perform public.qamar_wallet_credit_internal(
      new.user_id, 100, 'meal_log', 'meal:' || new.id::text);
  end if;
  return new;
exception
  -- Losing 100 points is a smaller failure than refusing to record what
  -- someone ate. The warning is the trail: grep the Postgres log for
  -- 'qamar_award' if a balance looks wrong.
  when others then
    raise warning 'qamar_award meal_log failed for %: %', new.user_id, sqlerrm;
    return new;
end;
$$;

drop trigger if exists trg_meal_log_award on public.meal_logs;
create trigger trg_meal_log_award
  after insert on public.meal_logs
  for each row execute function public.qamar_on_meal_log_award();

-- ---------------------------------------------------------------------------
-- Onboarding: the first confirmed target row is the finish line
-- ---------------------------------------------------------------------------
create or replace function public.qamar_on_first_target_award()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_count int;
begin
  select count(*) into target_count
  from public.targets
  where user_id = new.user_id;

  if target_count = 1 then
    perform public.qamar_wallet_credit_internal(
      new.user_id, 1000, 'onboarding', 'onboarding:' || new.user_id::text);
  end if;
  return new;
exception
  when others then
    raise warning 'qamar_award onboarding failed for %: %', new.user_id, sqlerrm;
    return new;
end;
$$;

drop trigger if exists trg_first_target_award on public.targets;
create trigger trg_first_target_award
  after insert on public.targets
  for each row execute function public.qamar_on_first_target_award();

-- ---------------------------------------------------------------------------
-- Daily quest: 250 Su, once per Cairo day, and only if a meal was logged
-- ---------------------------------------------------------------------------
-- This returns a reason rather than raising. "You have not logged a meal yet
-- today" is a normal state of the app on any morning, not an error, and the
-- client needs to say so in Arabic rather than surface a Postgres exception.
create or replace function public.qamar_complete_daily_quest()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  day date;
  idem text;
  meal_count int;
  bal int;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  day := public.qamar_cairo_today();
  idem := 'quest:' || uid::text || ':' || day::text;

  if exists (select 1 from public.su_point_ledger
             where user_id = uid and idempotency_key = idem) then
    select available_points into bal from public.wallet_accounts where user_id = uid;
    return jsonb_build_object(
      'credited', false, 'reason', 'already_claimed',
      'cairo_day', day, 'amount', 250, 'available', coalesce(bal, 0));
  end if;

  -- The quest is "log a meal today", not a button that mints points.
  select count(*) into meal_count
  from public.meal_logs
  where user_id = uid
    and (timezone('Africa/Cairo', logged_at))::date = day;

  if meal_count < 1 then
    select available_points into bal from public.wallet_accounts where user_id = uid;
    return jsonb_build_object(
      'credited', false, 'reason', 'no_meal_today',
      'cairo_day', day, 'amount', 250, 'available', coalesce(bal, 0));
  end if;

  perform public.qamar_wallet_credit_internal(uid, 250, 'daily_quest', idem);
  select available_points into bal from public.wallet_accounts where user_id = uid;
  return jsonb_build_object(
    'credited', true, 'reason', 'ok',
    'cairo_day', day, 'amount', 250, 'available', coalesce(bal, 0));
end;
$$;

revoke all on function public.qamar_complete_daily_quest() from public;
grant execute on function public.qamar_complete_daily_quest() to authenticated;
-- Anonymous sign-in carries the `authenticated` role with is_anonymous = true,
-- so guests are covered by the grant above. `anon` is the pre-sign-in role and
-- has no wallet to credit.
revoke execute on function public.qamar_complete_daily_quest() from anon;

-- ---------------------------------------------------------------------------
-- Backfill: pay the testers what the app already told them they had earned
-- ---------------------------------------------------------------------------
-- Triggers do not fire retroactively, and the six people who have used this
-- app watched their points appear and then disappear. The same idempotency
-- keys the triggers use make this safe to run and safe to re-run — a second
-- pass inserts nothing.
do $$
declare
  n_meal int := 0;
  n_onb int := 0;
  r record;
begin
  for r in
    select id, user_id,
           row_number() over (partition by user_id order by logged_at, id) as seq
    from public.meal_logs
  loop
    if r.seq = 1 then
      perform public.qamar_wallet_credit_internal(
        r.user_id, 500, 'first_meal', 'first_meal:' || r.user_id::text);
    else
      perform public.qamar_wallet_credit_internal(
        r.user_id, 100, 'meal_log', 'meal:' || r.id::text);
    end if;
    n_meal := n_meal + 1;
  end loop;

  for r in select distinct user_id from public.targets loop
    perform public.qamar_wallet_credit_internal(
      r.user_id, 1000, 'onboarding', 'onboarding:' || r.user_id::text);
    n_onb := n_onb + 1;
  end loop;

  raise notice 'qamar_award backfill: % meal rows, % onboarding users', n_meal, n_onb;
end;
$$;
