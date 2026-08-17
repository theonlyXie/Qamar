-- Micronutrients: the reference values, and the gap between them and what was
-- eaten.
--
-- 0010 created dri_reference and deliberately left it empty, with a comment
-- saying a value without a citable edition does not belong in it. This fills it
-- from the source tables, and every row carries the edition and the table it
-- came from.
--
-- Two things this migration is careful about.
--
-- First, the age range. The values below are the adult 19-50 band. They are not
-- extrapolated past 50, because four of them change there (calcium and vitamin D
-- rise, vitamin B6 rises, female iron falls at menopause), and a target that is
-- quietly wrong for a 60-year-old is worse than no target at all. A user outside
-- the band gets no row, and the gap report says so.
--
-- Second, the intake side. A micronutrient gap is a subtraction, and the
-- subtrahend has to come from somewhere. meal_logs.items has stored a name and
-- four macros since 0001 — enough to draw a calorie ring, not enough to say
-- anything about iron. The functions here read two optional keys per item,
-- qamar_food_id and grams, and count how many items carried them. A day where
-- nothing resolved reports zero coverage rather than zero iron.

-- ---------------------------------------------------------------------
-- The vocabulary
-- ---------------------------------------------------------------------

-- Seven nutrients that have DRI values and had no code. Magnesium and the four
-- B vitamins matter for an Egyptian diet specifically: a bread-and-legume
-- staple pattern is usually adequate in thiamin and folate and short on
-- riboflavin and B12, and that is a distinction the app cannot draw without
-- somewhere to put the numbers.
insert into public.nutrients (code, name_en, name_ar, unit, category, display_order)
values
  ('magnesium_mg',  'Magnesium',  'ماغنسيوم',      'mg', 'mineral', 20),
  ('selenium_ug',   'Selenium',   'سيلينيوم',      'µg', 'mineral', 21),
  ('vitamin_e_mg',  'Vitamin E',  'فيتامين هـ',    'mg', 'vitamin', 22),
  ('thiamin_mg',    'Thiamin',    'ثيامين',        'mg', 'vitamin', 23),
  ('riboflavin_mg', 'Riboflavin', 'ريبوفلافين',    'mg', 'vitamin', 24),
  ('niacin_mg',     'Niacin',     'نياسين',        'mg', 'vitamin', 25),
  ('vitamin_b6_mg', 'Vitamin B6', 'فيتامين ب٦',   'mg', 'vitamin', 26)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------
-- The reference values
-- ---------------------------------------------------------------------
--
-- Source: National Academies (NASEM) Dietary Reference Intakes, summary tables.
-- RDA where one was set, AI where the evidence did not support an RDA — the
-- distinction is kept because it changes what an unmet target means. Falling
-- short of an RDA is a shortfall against a value set to cover 97.5% of the
-- population. Falling short of an AI is falling short of an observed intake,
-- which is a weaker claim, and the gap report says which one it is making.
--
-- No Tolerable Upper Intake Levels are seeded here. They exist, and they matter
-- for a supplement conversation, but they live in a different table in the
-- source and were not read; inventing them from memory is exactly the failure
-- this schema was built to prevent.

insert into public.dri_reference
  (nutrient_code, kind, sex, life_stage, min_age_years, max_age_years,
   value_low, unit, source_id, source_edition, source_locator, notes)
values
  -- Elements. Appendix J, Table 3 of the 2019 sodium and potassium report,
  -- which reprints the element values from the earlier reports unchanged.
  ('calcium_mg',   'RDA', 'any',    'adult', 19, 50, 1000, 'mg', 'nasem_dri',
   'DRI Tables, Elements (reprinted in the 2019 Sodium and Potassium report, Appendix J Table 3)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/', null),
  ('iron_mg',      'RDA', 'male',   'adult', 19, 50, 8,    'mg', 'nasem_dri',
   'DRI Tables, Elements (reprinted in the 2019 Sodium and Potassium report, Appendix J Table 3)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/', null),
  ('iron_mg',      'RDA', 'female', 'adult', 19, 50, 18,   'mg', 'nasem_dri',
   'DRI Tables, Elements (reprinted in the 2019 Sodium and Potassium report, Appendix J Table 3)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/',
   'Higher than the male value because of menstrual losses; it falls to 8 mg after menopause, which is outside this age band.'),
  -- Magnesium is the one nutrient in this set whose adult value changes inside
  -- 19-50, so it gets two bands rather than one averaged row.
  ('magnesium_mg', 'RDA', 'male',   'adult', 19, 30, 400,  'mg', 'nasem_dri',
   'DRI Tables, Elements (reprinted in the 2019 Sodium and Potassium report, Appendix J Table 3)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/', null),
  ('magnesium_mg', 'RDA', 'male',   'adult', 31, 50, 420,  'mg', 'nasem_dri',
   'DRI Tables, Elements (reprinted in the 2019 Sodium and Potassium report, Appendix J Table 3)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/', null),
  ('magnesium_mg', 'RDA', 'female', 'adult', 19, 30, 310,  'mg', 'nasem_dri',
   'DRI Tables, Elements (reprinted in the 2019 Sodium and Potassium report, Appendix J Table 3)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/', null),
  ('magnesium_mg', 'RDA', 'female', 'adult', 31, 50, 320,  'mg', 'nasem_dri',
   'DRI Tables, Elements (reprinted in the 2019 Sodium and Potassium report, Appendix J Table 3)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/', null),
  ('zinc_mg',      'RDA', 'male',   'adult', 19, 50, 11,   'mg', 'nasem_dri',
   'DRI Tables, Elements (reprinted in the 2019 Sodium and Potassium report, Appendix J Table 3)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/', null),
  ('zinc_mg',      'RDA', 'female', 'adult', 19, 50, 8,    'mg', 'nasem_dri',
   'DRI Tables, Elements (reprinted in the 2019 Sodium and Potassium report, Appendix J Table 3)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/', null),
  ('iodine_ug',    'RDA', 'any',    'adult', 19, 50, 150,  'µg', 'nasem_dri',
   'DRI Tables, Elements (reprinted in the 2019 Sodium and Potassium report, Appendix J Table 3)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/', null),
  ('selenium_ug',  'RDA', 'any',    'adult', 19, 50, 55,   'µg', 'nasem_dri',
   'DRI Tables, Elements (reprinted in the 2019 Sodium and Potassium report, Appendix J Table 3)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/', null),
  ('potassium_mg', 'AI',  'male',   'adult', 19, 50, 3400, 'mg', 'nasem_dri',
   'Dietary Reference Intakes for Sodium and Potassium (2019)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/',
   'An AI, not an RDA: the 2019 review found the evidence insufficient to set an EAR.'),
  ('potassium_mg', 'AI',  'female', 'adult', 19, 50, 2600, 'mg', 'nasem_dri',
   'Dietary Reference Intakes for Sodium and Potassium (2019)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/',
   'An AI, not an RDA: the 2019 review found the evidence insufficient to set an EAR.'),
  ('sodium_mg',    'AI',  'any',    'adult', 19, 50, 1500, 'mg', 'nasem_dri',
   'Dietary Reference Intakes for Sodium and Potassium (2019)',
   'https://www.ncbi.nlm.nih.gov/books/NBK545442/table/appJ_tab3/',
   'Sodium is the one nutrient here where the usual problem is excess, not shortfall. The 2019 report also sets a Chronic Disease Risk Reduction intake, which is not seeded — treat this row as a floor and not as a licence to reach it.'),

  -- Vitamins. Summary Table 2 of the DRI tables.
  ('vitamin_a_ug',   'RDA', 'male',   'adult', 19, 50, 900, 'µg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/', 'µg RAE.'),
  ('vitamin_a_ug',   'RDA', 'female', 'adult', 19, 50, 700, 'µg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/', 'µg RAE.'),
  ('vitamin_c_mg',   'RDA', 'male',   'adult', 19, 50, 90,  'mg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/', null),
  ('vitamin_c_mg',   'RDA', 'female', 'adult', 19, 50, 75,  'mg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/', null),
  ('vitamin_d_ug',   'RDA', 'any',    'adult', 19, 50, 15,  'µg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/',
   'Set assuming minimal sun exposure. Egypt has plenty of sun and a high measured deficiency rate anyway — covered clothing and indoor work both matter more than latitude, so do not discount this target on the grounds of climate.'),
  ('vitamin_e_mg',   'RDA', 'any',    'adult', 19, 50, 15,  'mg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/', 'As alpha-tocopherol.'),
  ('thiamin_mg',     'RDA', 'male',   'adult', 19, 50, 1.2, 'mg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/', null),
  ('thiamin_mg',     'RDA', 'female', 'adult', 19, 50, 1.1, 'mg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/', null),
  ('riboflavin_mg',  'RDA', 'male',   'adult', 19, 50, 1.3, 'mg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/', null),
  ('riboflavin_mg',  'RDA', 'female', 'adult', 19, 50, 1.1, 'mg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/', null),
  ('niacin_mg',      'RDA', 'male',   'adult', 19, 50, 16,  'mg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/', 'mg niacin equivalents.'),
  ('niacin_mg',      'RDA', 'female', 'adult', 19, 50, 14,  'mg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/', 'mg niacin equivalents.'),
  ('vitamin_b6_mg',  'RDA', 'any',    'adult', 19, 50, 1.3, 'mg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/',
   'Rises after 50 in both sexes, which is why this band stops there.'),
  ('folate_ug',      'RDA', 'any',    'adult', 19, 50, 400, 'µg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/', 'µg dietary folate equivalents.'),
  ('vitamin_b12_ug', 'RDA', 'any',    'adult', 19, 50, 2.4, 'µg', 'nasem_dri',
   'DRI Tables, Vitamins (Summary Table 2)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t2/',
   'Found only in animal foods, so a vegetarian or a mostly-legume diet needs a fortified source or a supplement.'),

  -- Water and the two macronutrients that have a DRI rather than a computed
  -- target. Protein has one here as a floor; the energy engine in 0025 sets a
  -- higher gram-per-kilo figure, and the higher of the two wins.
  ('water_g',   'AI',  'male',   'adult', 19, 50, 3700, 'g', 'nasem_dri',
   'DRI Tables, Macronutrients and Water (Summary Table 4)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t4/',
   'Total water from all sources, food included — roughly a fifth of it usually arrives as food, so this is not a target for glasses of water.'),
  ('water_g',   'AI',  'female', 'adult', 19, 50, 2700, 'g', 'nasem_dri',
   'DRI Tables, Macronutrients and Water (Summary Table 4)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t4/',
   'Total water from all sources, food included.'),
  ('fiber_g',   'AI',  'male',   'adult', 19, 50, 38,   'g', 'nasem_dri',
   'DRI Tables, Macronutrients and Water (Summary Table 4)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t4/', null),
  ('fiber_g',   'AI',  'female', 'adult', 19, 50, 25,   'g', 'nasem_dri',
   'DRI Tables, Macronutrients and Water (Summary Table 4)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t4/', null),
  ('protein_g', 'RDA', 'male',   'adult', 19, 50, 56,   'g', 'nasem_dri',
   'DRI Tables, Macronutrients and Water (Summary Table 4)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t4/',
   'A floor for a 70 kg adult, not a goal. qamar_compute_targets sets the working protein target from body weight and it is normally higher.'),
  ('protein_g', 'RDA', 'female', 'adult', 19, 50, 46,   'g', 'nasem_dri',
   'DRI Tables, Macronutrients and Water (Summary Table 4)',
   'https://www.ncbi.nlm.nih.gov/books/NBK56068/table/summarytables.t4/',
   'A floor for a 57 kg adult, not a goal.')
on conflict (nutrient_code, kind, sex, life_stage, min_age_years) do nothing;

-- ---------------------------------------------------------------------
-- Targets for one person
-- ---------------------------------------------------------------------

-- The row that applies to a given person, one per nutrient. A sex-specific row
-- beats an 'any' row, and among equally specific rows the one whose age band
-- contains them wins. RDA beats AI when a nutrient somehow has both, because an
-- RDA is the stronger statement.
create or replace function public.qamar_micronutrient_targets(p_user_id uuid)
returns table (
  nutrient_code text,
  name_ar text,
  name_en text,
  category text,
  unit text,
  kind text,
  target numeric,
  source_edition text,
  source_locator text,
  note text
)
language plpgsql
stable
set search_path = public
as $$
declare
  p record;
  age numeric;
begin
  select * into p from public.profiles where user_id = p_user_id;
  if not found then
    return;
  end if;

  age := case when p.birth_date is null then null
              else extract(year from age(current_date, p.birth_date)) end;
  if age is null then
    return;
  end if;

  return query
  select distinct on (d.nutrient_code)
    d.nutrient_code,
    n.name_ar,
    n.name_en,
    n.category,
    d.unit,
    d.kind,
    d.value_low,
    d.source_edition,
    d.source_locator,
    d.notes
  from public.dri_reference d
  join public.nutrients n on n.code = d.nutrient_code
  where d.min_age_years <= age
    and (d.max_age_years is null or age <= d.max_age_years)
    and (d.sex = 'any' or d.sex = p.gender)
    and d.kind in ('RDA','AI')
    and d.life_stage = case
          when p.life_stage in ('pregnancy','lactation') then p.life_stage
          else 'adult'
        end
  order by d.nutrient_code,
           (d.sex <> 'any') desc,   -- a sex-specific row is the better match
           (d.kind = 'RDA') desc,
           d.min_age_years desc;
end;
$$;

comment on function public.qamar_micronutrient_targets is
  'The DRI row that applies to one person, per nutrient. Returns nothing when '
  'the profile has no birth date, and nothing for a nutrient whose seeded age '
  'bands do not contain them — 19-50 is all that is loaded, so a 60-year-old '
  'currently gets an empty set rather than a wrong number.';

-- ---------------------------------------------------------------------
-- What was actually eaten
-- ---------------------------------------------------------------------

-- meal_logs.items is an array of objects. Since 0001 the shape has been
-- {name, portion, confidence, kcal, protein_g, carbs_g, fat_g, qty} and none of
-- that identifies a food, so nothing downstream could ever say how much iron a
-- meal held. Two optional keys close that:
--
--   qamar_food_id  the resolved food, as foods.qamar_food_id
--   grams          the eaten weight in grams
--
-- Both are optional on purpose. Old rows do not have them, a photo estimate may
-- never have them, and an item without them is not an error — it is an item
-- this function cannot speak for, and it is counted so the caller knows.
create or replace function public.qamar_logged_items(
  p_user_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns table (
  log_id uuid,
  logged_at timestamptz,
  item_name text,
  qamar_food_id uuid,
  grams numeric
)
language sql
stable
set search_path = public
as $$
  select
    m.id,
    m.logged_at,
    nullif(i->>'name', ''),
    case
      when (i->>'qamar_food_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then (i->>'qamar_food_id')::uuid
      else null
    end,
    case
      when (i->>'grams') ~ '^[0-9]+(\.[0-9]+)?$' then (i->>'grams')::numeric
      else null
    end
  from public.meal_logs m
  cross join lateral jsonb_array_elements(m.items) as i
  where m.user_id = p_user_id
    and m.logged_at >= p_from
    and m.logged_at < p_to
    and jsonb_typeof(m.items) = 'array';
$$;

-- Nutrient totals over a window, with the coverage that produced them.
--
-- items_total and items_resolved are returned beside every number because they
-- are the difference between "you ate 4 mg of iron" and "of the eleven things
-- you logged, the three I could identify came to 4 mg of iron". Only the second
-- of those is true, and only the second is worth saying.
create or replace function public.qamar_nutrient_intake(
  p_user_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns table (
  nutrient_code text,
  unit text,
  amount numeric,
  foods_counted int,
  items_total int,
  items_resolved int
)
language sql
stable
set search_path = public
as $$
  with logged as (
    select * from public.qamar_logged_items(p_user_id, p_from, p_to)
  ),
  counts as (
    select
      count(*)::int as items_total,
      count(*) filter (where qamar_food_id is not null and grams is not null)::int as items_resolved
    from logged
  ),
  resolved as (
    select l.qamar_food_id, l.grams
    from logged l
    where l.qamar_food_id is not null and l.grams is not null
  )
  select
    fn.nutrient_code,
    n.unit,
    round(sum(fn.amount * r.grams / 100.0), 4),
    count(distinct r.qamar_food_id)::int,
    c.items_total,
    c.items_resolved
  from resolved r
  join public.food_nutrients fn on fn.qamar_food_id = r.qamar_food_id
  join public.nutrients n on n.code = fn.nutrient_code
  cross join counts c
  where fn.per_basis = 'per_100g'
  group by fn.nutrient_code, n.unit, c.items_total, c.items_resolved;
$$;

comment on function public.qamar_nutrient_intake is
  'Nutrient totals from logged meals over a window, scaled from per_100g values '
  'by the grams recorded on each item. items_total vs items_resolved is the '
  'honesty column: an unresolved item contributes nothing and the difference '
  'says how much of the meal the total is silent about.';

-- ---------------------------------------------------------------------
-- The gap
-- ---------------------------------------------------------------------

-- Mean daily intake against the target, over a trailing window.
--
-- The mean is over calendar days in the window rather than over days that have
-- a log, which makes an unlogged day count as a zero. That is the conservative
-- direction for a shortfall — it will call a poorly-logged week a deficiency —
-- so coverage_pct travels with the answer and a caller that shows a gap without
-- showing coverage is misreading this function.
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
      coalesce(max(items_resolved), 0) as items_resolved
    from intake
  )
  select
    t.nutrient_code,
    t.name_ar,
    t.name_en,
    t.category,
    t.unit,
    t.kind,
    t.target,
    round(coalesce(i.amount, 0) / w.days, 2),
    case when t.target > 0
         then round(100 * (coalesce(i.amount, 0) / w.days) / t.target, 1)
         else null end,
    case
      when c.items_resolved = 0 then 'unknown'
      when t.target is null or t.target = 0 then 'unknown'
      when (coalesce(i.amount, 0) / w.days) / t.target >= 1.0 then 'met'
      when (coalesce(i.amount, 0) / w.days) / t.target >= 0.7 then 'low'
      else 'short'
    end,
    case when c.items_total > 0
         then round(100.0 * c.items_resolved / c.items_total, 1)
         else 0 end,
    c.items_total,
    c.items_resolved,
    t.source_edition,
    t.note
  from window_bounds w
  cross join coverage c
  cross join public.qamar_micronutrient_targets(p_user_id) t
  left join intake i on i.nutrient_code = t.nutrient_code
  order by
    case
      when c.items_resolved = 0 then 3
      when t.target is null or t.target = 0 then 3
      when (coalesce(i.amount, 0) / w.days) / t.target >= 1.0 then 2
      else 1
    end,
    coalesce((coalesce(i.amount, 0) / w.days) / nullif(t.target, 0), 9),
    t.nutrient_code;
$$;

comment on function public.qamar_nutrient_gaps is
  'Mean daily intake against the DRI over a trailing window, worst shortfall '
  'first. status is unknown whenever no logged item resolved to a food, which '
  'is the normal state until the gateway starts writing qamar_food_id and grams '
  'onto logged items — a zero intake and an unmeasured one are not the same '
  'claim and this never conflates them.';

revoke all on function public.qamar_micronutrient_targets(uuid) from public, anon;
revoke all on function public.qamar_nutrient_intake(uuid, timestamptz, timestamptz) from public, anon;
revoke all on function public.qamar_logged_items(uuid, timestamptz, timestamptz) from public, anon;
revoke all on function public.qamar_nutrient_gaps(uuid, int) from public, anon;
grant execute on function public.qamar_micronutrient_targets(uuid) to authenticated, service_role;
grant execute on function public.qamar_nutrient_intake(uuid, timestamptz, timestamptz) to authenticated, service_role;
grant execute on function public.qamar_logged_items(uuid, timestamptz, timestamptz) to authenticated, service_role;
grant execute on function public.qamar_nutrient_gaps(uuid, int) to authenticated, service_role;

-- RLS does the access control here: all four are SECURITY INVOKER over
-- meal_logs and profiles, so a signed-in caller passing somebody else's user id
-- reads nothing rather than being trusted not to try.

-- ---------------------------------------------------------------------
-- What the food graph can actually answer
-- ---------------------------------------------------------------------

-- A target is only useful if the foods have the nutrient. This says, per
-- nutrient, how much of the food graph carries a value — the gap between the
-- DRI table and the data, which is the real limit on what the app can say.
create or replace view public.micronutrient_coverage
with (security_invoker = true) as
select
  n.code as nutrient_code,
  n.name_en,
  n.category,
  n.unit,
  count(distinct fn.qamar_food_id)::int as foods_with_a_value,
  (select count(*) from public.foods)::int as foods_total,
  round(100.0 * count(distinct fn.qamar_food_id) /
        nullif((select count(*) from public.foods), 0), 1) as coverage_pct,
  exists (select 1 from public.dri_reference d where d.nutrient_code = n.code) as has_a_target
from public.nutrients n
left join public.food_nutrients fn on fn.nutrient_code = n.code
group by n.code, n.name_en, n.category, n.unit, n.display_order
order by n.display_order;

comment on view public.micronutrient_coverage is
  'Per nutrient: how many foods carry a value, and whether a DRI target exists '
  'for it. A nutrient with a target and no coverage is one the app must stay '
  'quiet about.';

revoke all on public.micronutrient_coverage from anon;
grant select on public.micronutrient_coverage to authenticated, service_role;
