-- The morning line for someone who has gone quiet (seat 3's finding).
--
-- The night job wrote tomorrow's sentence only for Qamar+ members and for
-- whoever logged today (qamar_active_today, 0048). So the person who missed
-- a day, the one a reason to open the app matters most to, woke to nothing.
-- Now anyone who logged in the last seven days but not today gets a line too:
-- their own most-logged meal and where to log it again. No plan
-- is written for them, so there is no model call, and members keep the run's
-- budget. Nothing in the line is about the days that were not logged.
--
-- night_notes.plan_kcal is 0 on these rows: there is no plan behind the
-- sentence, and the app shows no plan link under it.

create or replace function public.qamar_returning(p_days int default 7)
returns table (user_id uuid, meal_name text)
language sql
stable
security definer
set search_path = public
as $$
  with recent as (
    select m.user_id, trim(m.name) as name
    from public.meal_logs m
    where (timezone('Africa/Cairo', m.logged_at))::date
          between public.qamar_cairo_today() - p_days and public.qamar_cairo_today() - 1
      and length(trim(m.name)) > 0
  )
  select distinct on (r.user_id) r.user_id, r.name as meal_name
  from recent r
  where not exists (
    select 1 from public.meal_logs t
    where t.user_id = r.user_id
      and (timezone('Africa/Cairo', t.logged_at))::date = public.qamar_cairo_today()
  )
  group by r.user_id, r.name
  order by r.user_id, count(*) desc, r.name;
$$;
revoke all on function public.qamar_returning(int) from public, anon, authenticated;
grant execute on function public.qamar_returning(int) to service_role;

comment on column public.night_notes.plan_kcal is
  'The plan behind the sentence, in kcal. 0: a returning line with no plan behind it (0062); the app shows no plan link.';
