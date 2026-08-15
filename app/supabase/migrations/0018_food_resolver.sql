-- Food resolution, in SQL.
--
-- The source router the architecture paper asks for: one food query hits the
-- best source first and falls back only on a miss or low confidence, rather
-- than querying USDA, Open Food Facts and everyone else for every item. "Best
-- source first" means this graph, because it is the only one that knows what
-- عيش بلدي is.
--
-- These are SECURITY INVOKER on purpose. They read only reference tables that
-- `authenticated` can already select, so running as the caller keeps RLS in
-- charge and avoids handing out a definer function that does not need to be one.

-- ---------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------

create or replace function public.qamar_resolve_food(
  p_phrase text,
  p_limit int default 3
) returns table (
  qamar_food_id uuid,
  slug text,
  name_en text,
  name_ar text,
  name_eg text,
  is_recipe boolean,
  match_score real,
  matched_alias text,
  match_kind text,
  has_nutrients boolean
)
language sql
stable
as $$
  with norm as (
    -- Strip quantities and units so "100 جرام جبنة قريش" matches the cheese
    -- rather than missing on the number.
    select btrim(lower(regexp_replace(
      p_phrase, '[0-9٠-٩]+\s*(g|kg|ml|جم|جرام|كجم|مل|جرامات)?', ' ', 'gi'))) as q
  ),
  candidates as (
    select a.qamar_food_id,
           a.alias,
           a.priority,
           case when lower(a.alias) = (select q from norm) then 1.0::real
                else similarity(a.alias, (select q from norm)) end as score,
           case when lower(a.alias) = (select q from norm) then 'exact' else 'fuzzy' end as kind
    from public.food_aliases a, norm
    where norm.q <> ''
      and (lower(a.alias) = norm.q or a.alias % norm.q)
  ),
  best as (
    select distinct on (c.qamar_food_id)
           c.qamar_food_id, c.alias, c.score, c.kind, c.priority
    from candidates c
    order by c.qamar_food_id, c.score desc, c.priority desc
  )
  select f.qamar_food_id, f.slug, f.name_en, f.name_ar, f.name_eg, f.is_recipe,
         b.score, b.alias, b.kind,
         exists (select 1 from public.food_nutrients n where n.qamar_food_id = f.qamar_food_id)
           or f.is_recipe
  from best b
  join public.foods f on f.qamar_food_id = b.qamar_food_id
  order by b.score desc, b.priority desc, f.source_rank desc nulls last
  limit greatest(p_limit, 1);
$$;

comment on function public.qamar_resolve_food is
  'Local-first food identity. Exact alias match scores 1.0; anything else is a '
  'trigram score the caller must treat as uncertain. Returns alternatives so an '
  'ambiguous phrase can be confirmed by the user rather than silently picked.';

-- ---------------------------------------------------------------------
-- Portion
-- ---------------------------------------------------------------------

create or replace function public.qamar_resolve_portion(
  p_food_id uuid,
  p_phrase text default null
) returns table (
  label_en text,
  label_ar text,
  grams numeric,
  basis text,
  confidence numeric,
  matched_in_phrase boolean
)
language sql
stable
as $$
  select p.label_en, p.label_ar, p.grams, p.basis, p.confidence,
         (p_phrase is not null and (
            position(lower(p.label_en) in lower(p_phrase)) > 0
            or (p.label_ar is not null and position(p.label_ar in p_phrase) > 0)))
  from public.food_portions p
  where p.qamar_food_id = p_food_id
  order by
    -- A portion the user actually named beats the default.
    (p_phrase is not null and (
       position(lower(p.label_en) in lower(p_phrase)) > 0
       or (p.label_ar is not null and position(p.label_ar in p_phrase) > 0))) desc,
    p.is_default desc,
    p.confidence desc nulls last
  limit 1;
$$;

-- ---------------------------------------------------------------------
-- Nutrition, including dishes computed from their ingredients
-- ---------------------------------------------------------------------
-- No food table contains koshary. A dish is built from what goes into it, the
-- yield factor accounts for what the cooking does, and the result is per 100 g
-- of the finished plate.

create or replace function public.qamar_nutrients_per_100g(p_food_id uuid)
returns table (
  nutrient_code text,
  amount numeric,
  unit text,
  source_id text,
  confidence numeric,
  derived boolean
)
language sql
stable
as $$
  with f as (select is_recipe from public.foods where qamar_food_id = p_food_id),

  direct as (
    select n.nutrient_code, n.amount, nu.unit, n.source_id, n.confidence, false as derived
    from public.food_nutrients n
    join public.nutrients nu on nu.code = n.nutrient_code
    where n.qamar_food_id = p_food_id and n.per_basis = 'per_100g'
  ),

  yield as (
    select sum(ri.grams) as input_g,
           sum(ri.grams) * coalesce(max(r.loss_gain_factor), 1) as output_g
    from public.recipe_ingredients ri
    join public.recipes r on r.qamar_food_id = ri.recipe_id
    where ri.recipe_id = p_food_id
  ),

  computed as (
    select n.nutrient_code,
           -- grams of ingredient / 100 gives the multiplier for a per-100g
           -- figure; dividing by the finished weight puts it back on a
           -- per-100g basis for the dish.
           round((sum(n.amount * ri.grams / 100.0) / nullif((select output_g from yield), 0) * 100)::numeric, 4) as amount,
           max(nu.unit) as unit,
           'derived_recipe'::text as source_id,
           -- A dish is never more certain than its least certain ingredient,
           -- and the yield factor adds its own error on top.
           round((min(coalesce(n.confidence, 0.5)) * 0.9)::numeric, 2) as confidence,
           true as derived
    from public.recipe_ingredients ri
    join public.food_nutrients n on n.qamar_food_id = ri.ingredient_food_id and n.per_basis = 'per_100g'
    join public.nutrients nu on nu.code = n.nutrient_code
    where ri.recipe_id = p_food_id
    group by n.nutrient_code
  )

  select * from direct
  union all
  select c.nutrient_code, c.amount, c.unit, c.source_id, c.confidence, c.derived
  from computed c
  where (select is_recipe from f)
    and not exists (select 1 from direct d where d.nutrient_code = c.nutrient_code);
$$;

comment on function public.qamar_nutrients_per_100g is
  'Per-100g nutrition for a food. A recipe with no direct values is computed '
  'from its ingredients and yield factor, and marked derived with a confidence '
  'no higher than its weakest ingredient. Returns nothing when the graph has no '
  'values yet, which the caller must treat as a miss and fall back on — never '
  'as zero.';

-- ---------------------------------------------------------------------
-- Coverage, so the miss rate is observable
-- ---------------------------------------------------------------------

create or replace view public.food_graph_coverage as
select
  count(*) filter (where not is_recipe) as ingredients,
  count(*) filter (where is_recipe) as dishes,
  count(*) filter (where not is_recipe and exists (
    select 1 from public.food_nutrients n where n.qamar_food_id = f.qamar_food_id)) as ingredients_with_nutrients,
  count(*) filter (where exists (
    select 1 from public.food_portions p where p.qamar_food_id = f.qamar_food_id)) as with_portions,
  (select count(*) from public.food_aliases) as aliases
from public.foods f;
