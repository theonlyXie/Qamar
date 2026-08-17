-- The other half of the ملوخية finding: priority, not ordering.
--
-- 0027 gave the resolver a rule for the exact tie between a dish and its own
-- ingredient. "كبدة" still resolved to raw liver, because it was never a tie —
-- the seed gave `liver` that word as its Egyptian name at priority 130 and gave
-- kebda_eskandarani the same word as a mere alias at 100, so priority decided
-- before the new rule could.
--
-- The priorities are the claim being disputed, so the priorities are what has to
-- change. A bare colloquial word claimed by both a dish and one of its
-- ingredients does not belong to either of them: in a meal-logging app someone
-- typing "كبدة" or "ملوخية" has eaten the cooked thing, but someone buying
-- ingredients has not, and no priority ordering makes both true. Levelling them
-- is what says "contested" in the only vocabulary the schema has — and then
-- 0027's rule offers the dish first while graph.ts still reports the ingredient
-- as "could also be", because an exact tie is a gap of zero and that is inside
-- the 0.1 band that triggers a confirmation.
--
-- Written as a set operation over whatever collides rather than as two UPDATEs
-- naming these two words, so a later alias import that introduces "بامية" or
-- "فتة" as both a dish and an ingredient is levelled by re-running this rather
-- than by somebody noticing.

-- Level to the maximum in each contested group, never the minimum: dropping the
-- priority would demote these names against *other* foods' aliases, which is a
-- different competition and not the one in dispute.
with contested as (
  select a.alias, max(a.priority) as top
  from public.food_aliases a
  join public.foods f on f.qamar_food_id = a.qamar_food_id
  group by a.alias
  having count(distinct f.is_recipe) > 1
)
update public.food_aliases a
   set priority = c.top
  from contested c
 where a.alias = c.alias
   and a.priority <> c.top;

comment on column public.food_aliases.priority is
  'Which food a name most refers to when several answer to it. Equal priority '
  'means contested: the resolver then prefers the dish over its own ingredient '
  'and reports the other as an alternative, rather than either one winning '
  'silently. See 0027 and 0028.';

-- A guard for the next import. Nothing enforces this — it is a check somebody
-- runs, and the eval suite is what actually fails when it is violated — but
-- having it as a view means the answer is one query rather than a join nobody
-- writes at the moment they need it.
create or replace view public.contested_food_aliases
with (security_invoker = true) as
select
  a.alias,
  count(*) filter (where f.is_recipe) as dishes,
  count(*) filter (where not f.is_recipe) as ingredients,
  count(distinct a.priority) as distinct_priorities,
  string_agg(distinct f.slug, ', ' order by f.slug) as claimants
from public.food_aliases a
join public.foods f on f.qamar_food_id = a.qamar_food_id
group by a.alias
having count(distinct f.is_recipe) > 1
order by a.alias;

comment on view public.contested_food_aliases is
  'A row with distinct_priorities > 1 is a name where one food quietly beats '
  'another. Levelling it is 0028; leaving it is a decision somebody should make '
  'on purpose.';

revoke all on public.contested_food_aliases from anon, authenticated;
