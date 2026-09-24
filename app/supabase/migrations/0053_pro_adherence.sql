-- The professional programme's second half: the dashboard, with consent.
--
-- 0037 and 0039 pay the professional; nothing let them see what happened
-- between visits. The blueprint's pitch is exactly that — "shows you what
-- happened before they walk in" — and its condition is exactly one: the
-- client said yes. So:
--
--   * a third consent type, adherence_share, in the same append-only table
--     the consultation's consents use (latest row wins, withdrawable);
--   * one function the professional calls, listing their referred clients
--     who currently consent, with the last seven days as numbers — days
--     logged, days near the target, the average, the target. No meals, no
--     photos, no weight: adherence, which is what the pitch promised and
--     what the client agreed to.
--
-- The relationship itself comes from pro_referrals (0039), which starts on
-- the client's first paid order carrying the code and ends twelve months
-- later; a client outside that window is not listed even if they still say
-- yes.

alter table public.consents drop constraint if exists consents_type_check;
alter table public.consents add constraint consents_type_check
  check (type in ('processing_required', 'improve_optional', 'adherence_share'));

-- The latest answer on record for one consent, or false when there is none.
create or replace function public.qamar_consent_granted(p_user_id uuid, p_type text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select granted_at is not null and withdrawn_at is null
    from public.consents
    where user_id = p_user_id and type = p_type
    order by created_at desc
    limit 1
  ), false);
$$;

revoke all on function public.qamar_consent_granted(uuid, text) from public, anon, authenticated;
grant execute on function public.qamar_consent_granted(uuid, text) to service_role;

-- The professional's clients, this week. Caller must be that professional
-- (or the billing function acting for them).
create or replace function public.qamar_pro_clients(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today date := public.qamar_cairo_today();
  v_from date := public.qamar_cairo_today() - 6;
  v_rows jsonb;
begin
  if auth.role() <> 'service_role' and (auth.uid() is null or auth.uid() <> p_user_id) then
    raise exception 'not authorised to read these clients';
  end if;

  select coalesce(jsonb_agg(row_to_json(c)::jsonb order by c.name), '[]'::jsonb)
    into v_rows
  from (
    select
      coalesce(nullif(trim(p.name), ''), '—') as name,
      r.started_at as since,
      r.ends_at as until,
      t.kcal as target_kcal,
      coalesce(w.days_logged, 0) as days_logged,
      coalesce(w.on_target_days, 0) as on_target_days,
      coalesce(w.avg_kcal, 0) as avg_kcal,
      w.last_logged_at
    from public.pro_referrals r
    left join public.profiles p on p.user_id = r.user_id
    left join lateral (
      select kcal from public.targets
      where user_id = r.user_id
      order by valid_from desc
      limit 1
    ) t on true
    left join lateral (
      select
        count(*)::int as days_logged,
        count(*) filter (
          where t.kcal is not null and abs(d.kcal - t.kcal) <= t.kcal * 0.10
        )::int as on_target_days,
        round(avg(d.kcal))::int as avg_kcal,
        max(d.last_at) as last_logged_at
      from (
        select
          (timezone('Africa/Cairo', logged_at))::date as day,
          sum(kcal)::int as kcal,
          max(logged_at) as last_at
        from public.meal_logs
        where user_id = r.user_id
          and (timezone('Africa/Cairo', logged_at))::date between v_from and v_today
        group by 1
      ) d
    ) w on true
    where r.affiliate_user_id = p_user_id
      and r.ends_at > now()
      and public.qamar_consent_granted(r.user_id, 'adherence_share')
  ) c;

  return jsonb_build_object(
    'from', v_from,
    'to', v_today,
    'clients', v_rows,
    'count', jsonb_array_length(v_rows)
  );
end;
$$;

revoke all on function public.qamar_pro_clients(uuid) from public, anon;
grant execute on function public.qamar_pro_clients(uuid) to authenticated, service_role;

comment on function public.qamar_pro_clients(uuid) is
  'A professional''s referred clients who consent to adherence_share, with the last seven Cairo days as numbers. Never meals, photos or weight.';
