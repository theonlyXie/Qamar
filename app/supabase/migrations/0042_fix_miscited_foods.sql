-- Thirty-six curated foods carried the nutrition of a different food.
--
-- Every food in the Egyptian catalogue links to a USDA FoodData Central entry,
-- and its per-100g nutrients were taken from whatever that link pointed at.
-- Checked against USDA's own published descriptions — from the SR Legacy and
-- Foundation bulk exports, not by search — roughly half the links point at
-- something else entirely:
--
--   white_rice    -> 168537  Mushrooms, white, cooked            28 kcal
--   soft_drink    -> 172726  Cookies, oatmeal, soft-type        409 kcal
--   sugar         -> 168175  Sugar-apples (sweetsop), raw        94 kcal
--   tahina        -> 173472  Horseradish, prepared               48 kcal
--   banana        -> 169394  Pepper, banana, raw                 27 kcal
--   apple         -> 168171  Rose-apples, raw                    25 kcal
--   honey         -> 167782  Abiyuch, raw                        69 kcal
--   white_cheese  -> 174925  Bread, white, toasted              290 kcal
--   macaroni      -> 168390  Asparagus, cooked, boiled           22 kcal
--   butter        -> 174950  Cookies, butter, commercial        467 kcal
--   orange        -> 169103  Orange peel, raw                    97 kcal
--   potato        -> 168484  Sweet potato, cooked                76 kcal
--
-- One id, 173472 "Horseradish, prepared", was shared by eight foods: basterma,
-- fesikh, halawa, mahalabia, olives, sobia, tahina and yogurt. The pattern is a
-- name match that went wrong at seed time — "sugar" matched "Sugar-apples",
-- "banana" matched "Pepper, banana" — and nothing downstream could catch it,
-- because a citation was present and pointed at a real food with real numbers.
-- Every guard in this project checks that a claim has a source. None of them
-- checked that the source was about the right thing.
--
-- What it cost the person using the app, per portion as the catalogue defines
-- it:
--
--   a plate of rice        180 g      50 kcal  ->    234 kcal
--   a can of soft drink    330 g   1,350 kcal  ->    139 kcal
--   a spoon of tahina       15 g       7 kcal  ->     89 kcal
--   a teaspoon of sugar      5 g       5 kcal  ->     19 kcal
--   a tablespoon of butter  14 g      65 kcal  ->    100 kcal
--   a banana               120 g      32 kcal  ->    107 kcal
--
-- A day built from those numbers is not off by a rounding error, and this is
-- the one thing the app exists to get right.
--
-- The fix copies from a row this database already holds. The USDA bulk import
-- loaded 87,392 foods slugged fdc_<name>_<fdc_id>, so the correct values are
-- already here, loaded by the importer that checked them — there is nothing in
-- this migration for a typo to get into. The corrected ids were each read off
-- USDA's published description first.
--
-- Portions: USDA's measured gram weights are added for the measures that mean
-- the same thing everywhere — a tablespoon, a teaspoon, a cup, an ounce. The
-- Egyptian household portions are deliberately left alone and left marked
-- estimated. A plate of koshary and a rughif of baladi bread are not USDA
-- measures, and a 330 ml can is not USDA's 12 fl oz; overwriting those with
-- American numbers would be the same mistake pointing the other way.
--
-- Applied to the live project on 2026-08-23 as `fix_miscited_curated_foods`.

create temporary table _fix (slug text primary key, fdc_id text, fdc_desc text);
insert into _fix (slug, fdc_id, fdc_desc) values
  ('apple','168202','Apples, raw, golden delicious, with skin'),
  ('areesh_cheese','173417','Cheese, cottage, lowfat, 1% milkfat'),
  ('banana','173944','Bananas, raw'),
  ('beef','171791','Beef, ground, 95% lean meat / 5% fat, patty, cooked, broiled'),
  ('black_eyed_peas','173759','Cowpeas, common, mature seeds, cooked, boiled, without salt'),
  ('brown_rice','169704','Rice, brown, long-grain, cooked'),
  ('butter','173410','Butter, salted'),
  ('cauliflower','169986','Cauliflower, raw'),
  ('coffee','171890','Beverages, coffee, brewed, prepared with tap water'),
  ('dill','172233','Dill weed, fresh'),
  ('grapes','174683','Grapes, red or green (European type), raw'),
  ('herring','175116','Fish, herring, Atlantic, raw'),
  ('honey','169640','Honey'),
  ('istanbouli_cheese','170845','Cheese, mozzarella, whole milk'),
  ('lemon','167746','Lemons, raw, without peel'),
  ('lupini','172424','Lupins, mature seeds, cooked, boiled, without salt'),
  ('macaroni','169737','Pasta, cooked, enriched, without added salt'),
  ('milk','172217','Milk, whole, 3.25% milkfat'),
  ('molokhia_leaves','168420','Jute, potherb, cooked, boiled, drained, without salt'),
  ('oats','173904','Cereals, oats, regular and quick, not fortified, dry'),
  ('olive_oil','171413','Oil, olive, salad or cooking'),
  ('olives','169094','Olives, ripe, canned (small-extra large)'),
  ('orange','169097','Oranges, raw, all commercial varieties'),
  ('potato','170440','Potatoes, boiled, cooked without skin, flesh, without salt'),
  ('radish','169276','Radishes, raw'),
  ('roumy_cheese','171249','Cheese, romano'),
  ('sesame','170150','Seeds, sesame seeds, whole, dried'),
  ('soft_drink','174852','Beverages, carbonated, cola, regular'),
  ('spinach','168462','Spinach, raw'),
  ('strawberry','167762','Strawberries, raw'),
  ('sugar','169655','Sugars, granulated'),
  ('tahina','170189','Seeds, sesame butter, tahini, from roasted and toasted kernels'),
  ('vermicelli','169737','Pasta, cooked, enriched, without added salt'),
  ('white_cheese','173420','Cheese, feta'),
  ('white_rice','168878','Rice, white, long-grain, regular, enriched, cooked'),
  ('yogurt','171284','Yogurt, plain, whole milk');

alter table _fix add column donor uuid;
update _fix x
set donor = f.qamar_food_id
from public.foods f
where f.source_rank = 10 and f.slug like '%\_' || x.fdc_id;

do $$
declare missing text;
begin
  select string_agg(slug || '(' || fdc_id || ')', ', ') into missing
  from _fix where donor is null;
  if missing is not null then
    raise exception 'no bulk row to copy from: %', missing;
  end if;
  select string_agg(x.slug, ', ') into missing
  from _fix x where not exists (select 1 from public.foods f where f.slug = x.slug);
  if missing is not null then
    raise exception 'unknown curated slugs: %', missing;
  end if;
end;
$$;

-- 1. Point each link at the food it is actually describing.
update public.food_source_links l
set external_id = x.fdc_id,
    url = 'https://fdc.nal.usda.gov/food-details/' || x.fdc_id,
    retrieved_at = now()
from _fix x, public.foods f
where f.slug = x.slug and l.qamar_food_id = f.qamar_food_id and l.source_id = 'usda_fdc';

-- 2. Replace the nutrients. Deleted first rather than upserted: the wrong food
--    carried nutrients this one does not have, and leaving those behind would
--    mix two foods in one row set.
delete from public.food_nutrients fn
using public.foods f, _fix x
where f.slug = x.slug and fn.qamar_food_id = f.qamar_food_id and fn.source_id = 'usda_fdc';

insert into public.food_nutrients
  (qamar_food_id, nutrient_code, amount, per_basis, source_id,
   nutrient_definition_version, confidence)
select f.qamar_food_id, d.nutrient_code, d.amount, d.per_basis, 'usda_fdc',
       d.nutrient_definition_version, 0.90
from _fix x
join public.foods f on f.slug = x.slug
join public.food_nutrients d on d.qamar_food_id = x.donor;

-- 3. USDA's measured portions, for the measures that travel.
insert into public.food_portions
  (qamar_food_id, label_en, label_ar, grams, is_household, is_default,
   basis, source_id, confidence)
select f.qamar_food_id, p.label, p.label, p.grams, true, false,
       'measured', 'usda_fdc', 0.90
from (values
  ('areesh_cheese','1 cup (not packed)',226),
  ('black_eyed_peas','1 cup',171),
  ('brown_rice','1 cup',202),
  ('butter','1 tbsp',14.2),
  ('butter','1 cup',227),
  ('coffee','1 cup (8 fl oz)',237),
  ('grapes','1 cup',151),
  ('honey','1 cup',339),
  ('honey','1 tbsp',21),
  ('istanbouli_cheese','1 oz',28.35),
  ('lupini','1 cup',166),
  ('macaroni','1 cup spaghetti not packed',124),
  ('milk','1 cup',244),
  ('milk','1 tbsp',15),
  ('molokhia_leaves','1 cup',87),
  ('oats','1 cup',81),
  ('olive_oil','1 tablespoon',13.5),
  ('olive_oil','1 tsp',4.5),
  ('olives','1 tbsp',8.4),
  ('radish','1 cup slices',116),
  ('roumy_cheese','1 oz',28.35),
  ('sesame','1 cup',144),
  ('sesame','1 tbsp',9),
  ('spinach','1 cup',30),
  ('sugar','1 tsp',4.2),
  ('sugar','1 cup',200),
  ('tahina','1 tbsp',15),
  ('tahina','1 oz',28.35),
  ('vermicelli','1 cup spaghetti not packed',124),
  ('white_cheese','1 oz',28.35),
  ('white_rice','1 cup',158),
  ('yogurt','1 cup (8 fl oz)',245)
) as p(slug, label, grams)
join public.foods f on f.slug = p.slug
where not exists (
  select 1 from public.food_portions e
  where e.qamar_food_id = f.qamar_food_id and e.label_en = p.label
);

-- Assert the correction landed. A migration that silently did nothing is the
-- failure mode this whole file exists because of.
do $$
declare rice numeric; cola numeric; sug numeric; tah numeric; n int;
begin
  select count(*) into n from public.food_nutrients fn
   join public.foods f on f.qamar_food_id = fn.qamar_food_id
   where f.slug in (select slug from _fix) and fn.source_id = 'usda_fdc';
  select amount into rice from public.food_nutrients fn join public.foods f
    on f.qamar_food_id=fn.qamar_food_id where f.slug='white_rice' and nutrient_code='energy_kcal';
  select amount into cola from public.food_nutrients fn join public.foods f
    on f.qamar_food_id=fn.qamar_food_id where f.slug='soft_drink' and nutrient_code='energy_kcal';
  select amount into sug from public.food_nutrients fn join public.foods f
    on f.qamar_food_id=fn.qamar_food_id where f.slug='sugar' and nutrient_code='energy_kcal';
  select amount into tah from public.food_nutrients fn join public.foods f
    on f.qamar_food_id=fn.qamar_food_id where f.slug='tahina' and nutrient_code='energy_kcal';
  raise notice 'corrected % nutrient rows; rice=% cola=% sugar=% tahina=%', n, rice, cola, sug, tah;
  if rice < 120 or cola > 60 or sug < 350 or tah < 500 then
    raise exception 'correction did not take: rice=% cola=% sugar=% tahina=%', rice, cola, sug, tah;
  end if;
end;
$$;

drop table _fix;
