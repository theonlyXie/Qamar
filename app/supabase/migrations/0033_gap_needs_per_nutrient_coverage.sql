-- A nutrient nobody measured is not a nutrient you are short on.
--
-- 0031 guarded the obvious case: when no logged item resolves to a known food,
-- every status is unknown. It missed the case the nutrient load has just made
-- real. Iodine now has a target of 150 µg and a value for zero of 131 foods —
-- USDA rarely analyses it — so a user who logged a full, perfectly identified
-- day would have been told they were short on iodine on the basis of no
-- measurement whatsoever. The same applies to any nutrient the graph is thin
-- on, and to any single meal made of foods that happen to lack that row.
--
-- The distinction that matters is between a food_nutrients row of 0 and no row
-- at all. Rice recorded at 0.2 mg of iron is a measurement. Rice with no iodine
-- row is silence, and silence must not sum to zero.
--
-- qamar_nutrient_intake already reported foods_counted per nutrient. It just
-- was not being read.
--
-- Verified against a fully identified two-item breakfast: iodine reads unknown
-- with 0% of the plate seen, iron reads short with 100% seen.

drop function if exists public.qamar_nutrient_gaps(uuid, int);

create or replace function public.qamar_nutrient_gaps(
  p_user_id uuid,
  p_days int default 7
)
returns table (
  nutrient_code text,
  name_ar text,
  name_en text,
  category text,
  unit text,
  kind text,
  target numeric,
  mean_daily numeric,
  pct_of_target numeric,
  status text,
  coverage_pct numeric,
  nutrient_coverage_pct numeric,
  items_total int,
  items_resolved int,
  source_edition text,
  note text
)
language sql
stable
set search_path = public
as $$
  with window_bounds as (
    select
      date_trunc('day', now()) - make_interval(days => greatest(p_days, 1)) as from_ts,
      date_trunc('day', now()) + interval '1 day' as to_ts,
      greatest(p_days, 1)::numeric as days
  ),
  intake as (
    select i.*
    from window_bounds w,
         lateral public.qamar_nutrient_intake(p_user_id, w.from_ts, w.to_ts) i
  ),
  coverage as (
    select
      coalesce(max(items_total), 0) as items_total,
      coalesce(max(items_resolved), 0) as items_resolved,
      -- The widest per-nutrient food count in the window is the best available
      -- stand-in for "how many distinct foods were resolved at all", without
      -- resolving the item list a second time.
      coalesce(max(foods_counted), 0) as foods_max
    from intake
  ),
  measured as (
    select
      t.*,
      i.amount,
      coalesce(i.foods_counted, 0) as foods_with_a_value
    from public.qamar_micronutrient_targets(p_user_id) t
    left join intake i on i.nutrient_code = t.nutrient_code
  )
  select
    m.nutrient_code,
    m.name_ar,
    m.name_en,
    m.category,
    m.unit,
    m.kind,
    m.target,
    round(coalesce(m.amount, 0) / w.days, 2),
    case when m.target > 0 and m.foods_with_a_value > 0
         then round(100 * (coalesce(m.amount, 0) / w.days) / m.target, 1)
         else null end,
    case
      when c.items_resolved = 0 then 'unknown'
      -- Not one of the foods eaten carries a value for this nutrient. The sum
      -- is zero because nothing was measured, not because nothing was eaten.
      when m.foods_with_a_value = 0 then 'unknown'
      when m.target is null or m.target = 0 then 'unknown'
      when (coalesce(m.amount, 0) / w.days) / m.target >= 1.0 then 'met'
      when (coalesce(m.amount, 0) / w.days) / m.target >= 0.7 then 'low'
      else 'short'
    end,
    case when c.items_total > 0
         then round(100.0 * c.items_resolved / c.items_total, 1)
         else 0 end,
    -- How much of what they ate this figure actually saw. A shortfall computed
    -- from a third of the plate is a different claim from one computed from all
    -- of it, and a caller showing the first as the second is misreporting.
    case when c.foods_max > 0
         then round(100.0 * m.foods_with_a_value / c.foods_max, 1)
         else 0 end,
    c.items_total,
    c.items_resolved,
    m.source_edition,
    m.note
  from window_bounds w
  cross join coverage c
  cross join measured m
  order by
    case
      when c.items_resolved = 0 then 3
      when m.foods_with_a_value = 0 then 3
      when m.target is null or m.target = 0 then 3
      when (coalesce(m.amount, 0) / w.days) / m.target >= 1.0 then 2
      else 1
    end,
    coalesce((coalesce(m.amount, 0) / w.days) / nullif(m.target, 0), 9),
    m.nutrient_code;
$$;

comment on function public.qamar_nutrient_gaps is
  'Mean daily intake against the DRI over a trailing window, worst shortfall '
  'first. status is unknown in three cases, and they are the whole point of '
  'this function: nothing logged resolved to a food, no food eaten carries a '
  'value for that nutrient, or no target applies. Iodine is the standing '
  'example — it has a target and a value for none of the food graph, so it '
  'must read as unmeasured rather than as a deficiency. nutrient_coverage_pct '
  'says how much of what they ate the figure actually saw.';

revoke all on function public.qamar_nutrient_gaps(uuid, int) from public, anon;
grant execute on function public.qamar_nutrient_gaps(uuid, int) to authenticated, service_role;
