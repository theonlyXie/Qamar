-- Two things the linter was right about.
--
-- 1. Four views from 0018 and 0019 were created without security_invoker, which
--    in Postgres means they run as their owner and the row level security on
--    the tables underneath does not apply to whoever queries them. Three of
--    those views aggregate across every user. safety_daily and
--    safety_rule_activity are counts, but clinician_queue carries the actual
--    escalation queue — the trigger rule, the questions asked about a person —
--    and PostgREST exposes a view in public to any signed-in caller. That is
--    other people's health escalations, readable by anyone with an account.
--
--    Both halves of the fix are here, because either alone is thin. Invoker
--    rights make RLS apply; the revoke means a staff view is not reachable from
--    the app's API at all, so it does not depend on a policy staying correct.
--
-- 2. The three resolver functions in 0018 never had search_path pinned. They
--    are SECURITY INVOKER, so this is not the privilege-escalation case the
--    lint is usually about, but an unqualified name inside them still resolves
--    against the caller's search_path, and everything else in this schema pins
--    it. A rule with one unexplained exception is a rule nobody trusts.

-- ---------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------

alter view public.safety_rule_activity set (security_invoker = true);
alter view public.safety_daily        set (security_invoker = true);
alter view public.clinician_queue     set (security_invoker = true);
alter view public.food_graph_coverage set (security_invoker = true);

-- Staff and founder console only. These answer questions about the whole user
-- base, which is not a question the app is ever entitled to ask.
revoke all on public.safety_rule_activity from anon, authenticated;
revoke all on public.safety_daily        from anon, authenticated;
revoke all on public.clinician_queue     from anon, authenticated;
revoke all on public.ai_cost_daily       from anon, authenticated;
revoke all on public.stage_budget_pressure from anon, authenticated;

-- food_graph_coverage stays readable: it reports how much of the food graph has
-- nutrient values, over tables the app may already read, and about no one.

comment on view public.clinician_queue is
  'The review queue. An urgent row ageing here is the failure the escalation '
  'design exists to prevent, so `waiting` is the column to alert on. Not '
  'reachable from the app API — see 0023.';

-- ---------------------------------------------------------------------
-- Resolver functions
-- ---------------------------------------------------------------------
-- Same bodies as 0018, re-declared only to pin search_path. Kept as ALTER
-- rather than a copy of each body, so the two files cannot drift.

alter function public.qamar_resolve_food(text, integer) set search_path = public;
alter function public.qamar_resolve_portion(uuid, text) set search_path = public;
alter function public.qamar_nutrients_per_100g(uuid) set search_path = public;
