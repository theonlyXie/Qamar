-- Views over the safety log.
--
-- The tables record what happened; these answer the questions somebody
-- actually asks. Without them, "has the eating-disorder rule ever fired" is a
-- join nobody writes at the moment they need it.
--
-- Server-side only, like the tables they read. RLS on a view follows the
-- underlying tables, and safety_events is already own-row for clients — but
-- these aggregate across users, so they belong to staff and the founder
-- console, not to the app.

-- How often each rule fires, and whether it is escalating as designed.
create or replace view public.safety_rule_activity as
select
  r.slug,
  r.escalate_to,
  r.min_risk_tier,
  r.is_active,
  count(e.id) as times_fired,
  count(e.id) filter (where e.created_at > now() - interval '7 days') as fired_last_7d,
  max(e.created_at) as last_fired_at
from public.red_flag_rules r
left join public.safety_events e on e.rule_slug = r.slug
group by r.slug, r.escalate_to, r.min_risk_tier, r.is_active
order by times_fired desc, r.slug;

comment on view public.safety_rule_activity is
  'A rule with times_fired = 0 is either never triggered or quietly broken, and '
  'the two look identical from inside the application. This is where that gets '
  'noticed.';

-- Tier mix per day. The denominator matters: a refusal count without the
-- traffic it came from says nothing about whether the guardrails are calibrated.
create or replace view public.safety_daily as
select
  created_at::date as day,
  risk_tier,
  count(*) as requests,
  count(*) filter (where cardinality(flags) > 0) as flagged
from public.risk_assessments
group by created_at::date, risk_tier
order by day desc, risk_tier;

-- What is waiting on a human, oldest first, urgent above routine.
create or replace view public.clinician_queue as
select
  cr.id,
  cr.priority,
  cr.status,
  cr.trigger_rule,
  r.escalate_to,
  cr.queued_at,
  now() - cr.queued_at as waiting,
  cr.explicit_questions
from public.clinician_reviews cr
left join public.red_flag_rules r on r.slug = cr.trigger_rule
where cr.status in ('queued', 'in_review')
order by (cr.priority = 'urgent') desc, cr.queued_at;

comment on view public.clinician_queue is
  'The review queue. An urgent row ageing here is the failure the escalation '
  'design exists to prevent, so `waiting` is the column to alert on.';
