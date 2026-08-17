-- Views over the verifier.
--
-- verifier_results has been a table with a shape and no rows since 0015. The
-- gateway now writes one row per verification pass, and these answer the two
-- questions that make it worth having.
--
-- The first is whether the checks are calibrated. A verifier that passes
-- everything is decoration, and one that revises constantly is a tolerance set
-- wrong rather than a model behaving badly — and from inside the application
-- those look identical, exactly like a red-flag rule stuck at zero.
--
-- The second is what is actually failing. The failure type is the useful field
-- and it lives inside a jsonb array, which means nobody unnests it at the
-- moment they need it.

create or replace view public.verifier_activity
with (security_invoker = true) as
select
  v.created_at::date as day,
  p.kind,
  v.verdict,
  v.revision_number,
  count(*) as passes,
  count(*) filter (where jsonb_array_length(v.failures) > 0) as with_findings
from public.verifier_results v
join public.evidence_packets p on p.task_id = v.task_id
group by v.created_at::date, p.kind, v.verdict, v.revision_number
order by day desc, p.kind, v.revision_number;

comment on view public.verifier_activity is
  'A verifier that never fails anything is decoration; one that fails '
  'everything is a tolerance set wrong. Read this before trusting a PASS rate.';

-- What is going wrong, most common first. severity is the column that says
-- whether a finding was acted on: escalate blocked an answer, revise bought a
-- correction round, advisory was recorded and nothing more.
create or replace view public.verifier_failures
with (security_invoker = true) as
select
  f.value ->> 'failure_type' as failure_type,
  f.value ->> 'severity' as severity,
  p.kind,
  count(*) as times,
  count(*) filter (where v.created_at > now() - interval '7 days') as last_7d,
  max(v.created_at) as last_seen
from public.verifier_results v
join public.evidence_packets p on p.task_id = v.task_id
cross join lateral jsonb_array_elements(v.failures) as f(value)
group by 1, 2, 3
order by times desc, failure_type;

-- How often a correction round actually corrected anything. The revision cap
-- is only defensible if the one round it allows is worth its cost; this is the
-- number that says whether it is.
create or replace view public.verifier_revisions
with (security_invoker = true) as
with first_pass as (
  select task_id, verdict from public.verifier_results where revision_number = 0
),
second_pass as (
  select task_id, verdict from public.verifier_results where revision_number = 1
)
select
  p.kind,
  count(*) filter (where f.verdict = 'REVISE') as revisions_earned,
  count(s.task_id) as revisions_attempted,
  count(*) filter (where s.verdict = 'PASS') as revisions_that_fixed_it,
  count(*) filter (where s.verdict = 'ESCALATE') as revisions_that_did_not
from first_pass f
join public.evidence_packets p on p.task_id = f.task_id
left join second_pass s on s.task_id = f.task_id
group by p.kind
order by p.kind;

-- Operational, like every other staff view here.
revoke all on public.verifier_activity  from anon, authenticated;
revoke all on public.verifier_failures  from anon, authenticated;
revoke all on public.verifier_revisions from anon, authenticated;
