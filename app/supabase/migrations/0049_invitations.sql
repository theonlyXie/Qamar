-- The referral loop: three named invitations a quarter, from a member.
--
-- Blueprint: "Subscriber earns 3 invitations / quarter → sends a named
-- invitation from Me → friend gets a 14-day trial + the sender's name at
-- 0:00 → friend pays month 1 → sender 1,000 points, friend 2,000 points."
-- And: "Invitations are scarce and numbered so the loop is driven by the
-- sender's status, not by a discount. Invitation count is the referral
-- metric that matters; conversion of invitations above 30% is the target."
--
-- So: an invitation is a row with a number (1–3 in its quarter), a name and
-- a code. A member issues one; the friend redeems it once, on one account,
-- never their own; the fortnight is the ordinary trial with a longer clock,
-- and never a second trial. The friend's first paid order converts the
-- invitation and pays both sides, once. Nothing here is a discount.

create table if not exists public.invitations (
  id uuid primary key default uuid_generate_v4(),
  inviter_user_id uuid not null references auth.users (id) on delete cascade,
  -- Cairo quarter, e.g. 2026Q3. The allotment renews with it.
  quarter text not null,
  number int not null check (number between 1 and 3),
  invitee_name text not null check (length(trim(invitee_name)) between 1 and 60),
  code text not null unique,
  created_at timestamptz not null default now(),
  -- One invitation per friend, ever: the first one redeemed is the one that counts.
  redeemed_by uuid unique references auth.users (id) on delete set null,
  redeemed_at timestamptz,
  -- The friend's first paid month.
  converted_at timestamptz,
  unique (inviter_user_id, quarter, number),
  constraint invitations_not_self check (redeemed_by is null or redeemed_by <> inviter_user_id)
);
create index if not exists invitations_inviter_idx on public.invitations (inviter_user_id, created_at desc);
alter table public.invitations enable row level security;
drop policy if exists invitations_select_own on public.invitations;
create policy invitations_select_own on public.invitations
  for select using (auth.uid() = inviter_user_id or auth.uid() = redeemed_by);
-- Written through the functions below only.
revoke insert, update, delete on public.invitations from anon, authenticated;

insert into public.su_economy_config (key, value) values
  ('invitations_per_quarter', 3),
  ('invitation_trial_days', 14),
  ('invitation_sender_reward', 1000),
  ('invitation_friend_reward', 2000)
on conflict (key) do update set value = excluded.value;

-- The Cairo quarter a moment falls in.
create or replace function public.qamar_quarter(p_at timestamptz default now())
returns text
language sql
stable
as $$
  select to_char(timezone('Africa/Cairo', p_at), 'YYYY"Q"Q');
$$;

create or replace function public.qamar_invitation_json(i public.invitations)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', i.id,
    'number', i.number,
    'quarter', i.quarter,
    'name', i.invitee_name,
    'code', i.code,
    'created_at', i.created_at,
    'redeemed_at', i.redeemed_at,
    'converted_at', i.converted_at
  );
$$;

-- ---------------------------------------------------------------------
-- A member issues a named invitation. Three a quarter; the fourth is refused
-- with a reason the app can show.
create or replace function public.qamar_issue_invitation(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_quarter text := public.qamar_quarter();
  v_limit int := coalesce(public.qamar_su_value('invitations_per_quarter'), 3);
  v_used int;
  v_code text;
  v_row public.invitations;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  if not public.qamar_is_plus(v_uid) then
    raise exception 'invitations are for Qamar+ members';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'an invitation carries a name';
  end if;
  -- Two taps at once must not both be number three.
  perform pg_advisory_xact_lock(hashtext('qamar_invitations:' || v_uid::text));
  select count(*) into v_used from public.invitations where inviter_user_id = v_uid and quarter = v_quarter;
  if v_used >= v_limit then
    raise exception 'no invitations left this quarter';
  end if;
  loop
    v_code := 'QMR-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 5));
    exit when not exists (select 1 from public.invitations where code = v_code);
  end loop;
  insert into public.invitations (inviter_user_id, quarter, number, invitee_name, code)
  values (v_uid, v_quarter, v_used + 1, left(trim(p_name), 60), v_code)
  returning * into v_row;
  return public.qamar_invitation_json(v_row);
end;
$$;
revoke all on function public.qamar_issue_invitation(text) from public, anon;
grant execute on function public.qamar_issue_invitation(text) to authenticated, service_role;

-- The member's book: this quarter, the allotment, every invitation they sent.
create or replace function public.qamar_my_invitations()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'quarter', public.qamar_quarter(),
    'limit', coalesce(public.qamar_su_value('invitations_per_quarter'), 3),
    'invitations', coalesce(
      (select jsonb_agg(public.qamar_invitation_json(i) order by i.created_at)
       from public.invitations i
       where i.inviter_user_id = auth.uid()),
      '[]'::jsonb)
  );
$$;
revoke all on function public.qamar_my_invitations() from public, anon;
grant execute on function public.qamar_my_invitations() to authenticated, service_role;

-- ---------------------------------------------------------------------
-- The trial with a chosen length. Only the redeem path below may set the
-- length; the one-argument form everyone else calls stays at seven days.
create or replace function public.qamar_start_trial(p_user_id uuid, p_days int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_end timestamptz := now() + make_interval(days => greatest(coalesce(p_days, 7), 1));
begin
  if auth.role() <> 'service_role' and (auth.uid() is null or auth.uid() <> p_user_id) then
    raise exception 'not authorised to start this trial';
  end if;
  if exists (select 1 from public.plus_trials where user_id = p_user_id) then
    raise exception 'trial already used';
  end if;
  if public.qamar_has_paid_plus(p_user_id) then
    raise exception 'trial is for first-time members';
  end if;
  if public.qamar_is_plus(p_user_id) then
    raise exception 'already Qamar+';
  end if;

  insert into public.plus_trials (user_id, ends_at) values (p_user_id, v_end);

  insert into public.entitlements (user_id, status, plan, provider, period_end, source_order_id, updated_at)
  values (p_user_id, 'active', 'monthly', 'trial', v_end, null, now())
  on conflict (user_id) do update set
    status = 'active',
    plan = 'monthly',
    provider = 'trial',
    period_end = v_end,
    source_order_id = null,
    updated_at = now();

  return public.qamar_entitlement_snapshot(p_user_id);
end;
$$;
revoke all on function public.qamar_start_trial(uuid, int) from public, anon, authenticated;
grant execute on function public.qamar_start_trial(uuid, int) to service_role;

create or replace function public.qamar_start_trial(p_user_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.qamar_start_trial(p_user_id, 7);
$$;
revoke all on function public.qamar_start_trial(uuid) from public, anon;
grant execute on function public.qamar_start_trial(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- The friend redeems. Once per account, never one's own, never a used one.
-- The fortnight is granted when a trial is still open to them; someone who
-- already had a trial, or paid, is still counted as invited — the sender's
-- name is the invitation's value, not the free days.
create or replace function public.qamar_redeem_invitation(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_norm text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_inv public.invitations;
  v_name text;
  v_days int := coalesce(public.qamar_su_value('invitation_trial_days'), 14);
  v_trial boolean := false;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  if length(v_norm) = 0 then
    raise exception 'no invitation with that code';
  end if;
  if exists (select 1 from public.invitations where redeemed_by = v_uid) then
    raise exception 'this account already used an invitation';
  end if;
  select * into v_inv from public.invitations where replace(code, '-', '') = v_norm for update;
  if not found then
    raise exception 'no invitation with that code';
  end if;
  if v_inv.inviter_user_id = v_uid then
    raise exception 'that is your own invitation';
  end if;
  if v_inv.redeemed_by is not null then
    raise exception 'this invitation was already used';
  end if;

  update public.invitations set redeemed_by = v_uid, redeemed_at = now() where id = v_inv.id;

  select coalesce(nullif(trim(name), ''), '') into v_name
  from public.profiles where user_id = v_inv.inviter_user_id;

  if not exists (select 1 from public.plus_trials where user_id = v_uid)
     and not public.qamar_has_paid_plus(v_uid)
     and not public.qamar_is_plus(v_uid) then
    perform public.qamar_start_trial(v_uid, v_days);
    v_trial := true;
  end if;

  return jsonb_build_object(
    'inviter_name', coalesce(v_name, ''),
    'invitee_name', v_inv.invitee_name,
    'trial_days', case when v_trial then v_days else 0 end
  );
end;
$$;
revoke all on function public.qamar_redeem_invitation(text) from public, anon;
grant execute on function public.qamar_redeem_invitation(text) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- Conversion: the friend's first paid order pays both sides, once. A
-- trigger rather than an edit to qamar_apply_paid_order, so a webhook
-- problem here can never stop a payment being applied.
create or replace function public.qamar_on_order_paid_invitation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.invitations;
begin
  if new.status <> 'paid' or (tg_op = 'UPDATE' and old.status = 'paid') then
    return new;
  end if;
  select * into v_inv
  from public.invitations
  where redeemed_by = new.user_id and converted_at is null
  for update;
  if not found then
    return new;
  end if;
  update public.invitations set converted_at = now() where id = v_inv.id;
  perform public.qamar_wallet_credit_internal(
    v_inv.inviter_user_id,
    coalesce(public.qamar_su_value('invitation_sender_reward'), 1000),
    'invitation_converted',
    'invitation:' || v_inv.id::text || ':sender'
  );
  perform public.qamar_wallet_credit_internal(
    new.user_id,
    coalesce(public.qamar_su_value('invitation_friend_reward'), 2000),
    'invitation_paid',
    'invitation:' || v_inv.id::text || ':friend'
  );
  return new;
exception
  when others then
    raise warning 'qamar_on_order_paid_invitation failed for %: %', new.user_id, sqlerrm;
    return new;
end;
$$;
revoke all on function public.qamar_on_order_paid_invitation() from public, anon, authenticated;

drop trigger if exists qamar_invitation_conversion on public.billing_orders;
create trigger qamar_invitation_conversion
  after insert or update of status on public.billing_orders
  for each row execute function public.qamar_on_order_paid_invitation();

-- The two rewards are one-offs, like signup and onboarding: they do not eat
-- the day's earning cap.
create or replace function public.qamar_su_earned_today(p_user_id uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(delta), 0)::int
  from public.su_point_ledger
  where user_id = p_user_id
    and delta > 0
    and reason not in ('signup_bonus', 'onboarding', 'invitation_converted', 'invitation_paid')
    and (timezone('Africa/Cairo', created_at))::date = public.qamar_cairo_today();
$$;
revoke all on function public.qamar_su_earned_today(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- The referral metric, in the nightly report: invitations that converted
-- within their first thirty days / invitations issued. Target above 30%;
-- the blueprint sets no kill line for it.
create or replace function public.qamar_kill_metrics(p_from date, p_to date)
returns table (
  metric text,
  numerator bigint,
  denominator bigint,
  value numeric,
  target numeric,
  kill numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with cohort as (
    select user_id, (timezone('Africa/Cairo', created_at))::date as day0
    from public.profiles
    where (timezone('Africa/Cairo', created_at))::date between p_from and p_to
  ),
  today as (select public.qamar_cairo_today() as d),
  logged_on as (
    select distinct m.user_id, (timezone('Africa/Cairo', m.logged_at))::date as day
    from public.meal_logs m
    join cohort c on c.user_id = m.user_id
  ),
  intake as (
    select count(*) as den,
           count(*) filter (where exists (select 1 from public.targets t where t.user_id = c.user_id)) as num
    from cohort c
  ),
  day7 as (
    select count(*) as den,
           count(*) filter (where exists (select 1 from logged_on l where l.user_id = c.user_id and l.day = c.day0 + 7)) as num
    from cohort c, today
    where c.day0 + 7 < today.d
  ),
  day30 as (
    select count(*) as den,
           count(*) filter (where exists (select 1 from logged_on l where l.user_id = c.user_id and l.day = c.day0 + 30)) as num
    from cohort c, today
    where c.day0 + 30 < today.d
  ),
  trials as (
    select count(*) as den,
           count(*) filter (where exists (
             select 1 from public.billing_orders o
             where o.user_id = t.user_id
               and o.status = 'paid'
               and o.paid_at is not null
               and o.paid_at <= t.started_at + interval '14 days'
           )) as num
    from public.plus_trials t
    where (timezone('Africa/Cairo', t.started_at))::date between p_from and p_to
      and t.started_at + interval '14 days' < now()
  ),
  invites as (
    select count(*) as den,
           count(*) filter (where i.converted_at is not null and i.converted_at <= i.created_at + interval '30 days') as num
    from public.invitations i
    where (timezone('Africa/Cairo', i.created_at))::date between p_from and p_to
      and i.created_at + interval '30 days' < now()
  ),
  rows_ as (
    select 'intake_completion' as metric, num, den, 0.70::numeric as target, 0.50::numeric as kill from intake
    union all
    select 'day7_logging', num, den, 0.40, 0.25 from day7
    union all
    select 'day30_unprompted', num, den, 0.05, 0.02 from day30
    union all
    select 'trial_to_paid', num, den, 0.25, 0.15 from trials
    union all
    select 'invitation_conversion', num, den, 0.30, null::numeric from invites
  )
  select metric,
         num::bigint,
         den::bigint,
         case when den = 0 then null else round(num::numeric / den, 4) end,
         target,
         kill
  from rows_;
$$;
revoke all on function public.qamar_kill_metrics(date, date) from public, anon, authenticated;
grant execute on function public.qamar_kill_metrics(date, date) to service_role;
