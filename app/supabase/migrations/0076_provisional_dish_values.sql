-- Fourteen Egyptian dishes cite a USDA food they are not, and there is no
-- USDA food they are.
--
-- 0074 fixed the foods that had a right answer available: rice is rice, sugar
-- is sugar, and USDA publishes both. These fourteen are different. Basterma,
-- fesikh, mahalabia, sobia, konafa, om ali, basbousa, zalabia, karkade, tamr
-- hindi, erksous, mango juice, eshta and freekeh are Egyptian, and FoodData
-- Central has no entry for any of them. The seed matched each to the nearest
-- unrelated thing:
--
--   basterma, fesikh, mahalabia, sobia  ->  Horseradish, prepared
--   konafa, om ali, basbousa            ->  Puff pastry, frozen, baked
--   karkade, tamr hindi, erksous        ->  Lemonade-flavor drink, powder
--   zalabia                             ->  Tofu, fried
--   mango juice                         ->  Cranberry juice cocktail
--   eshta                               ->  Cake, boston cream pie
--   freekeh                             ->  Asparagus, cooked
--
-- There is nothing to correct these to, so this migration does not pretend
-- otherwise. It removes the citation, because the citation is false — USDA
-- never said anything about basterma — and re-files the numbers under an
-- internal estimate source at confidence 0.25.
--
-- The numbers are deliberately NOT rewritten. Replacing a borrowed number with
-- one I invented would launder it: it would look considered, carry no source
-- either, and be no more true. Left where they are and labelled provisional,
-- they stay visible in food_values_provisional until somebody puts real values
-- behind them.
--
-- Where the real values should come from: FAO/INFOODS Egypt Food Composition
-- Tables, already in source_registry. Its storage_rights are 'unknown', and
-- the importer refuses to store from a source that has not granted them. That
-- flag is a licensing question and is not mine to flip.
--
-- Applied live on 2026-08-23 as `strip_false_citations_from_dishes`.

-- kind 'other' and license_class 'public_domain': the check constraints
-- enumerate external source types and external licences, and this is neither.
-- It is our own admission that a value has no source.
insert into public.source_registry
  (source_id, name, kind, license_class, storage_rights, ai_advice_rights,
   status, notes)
values
  ('qamar_estimate', 'Qamar internal estimate', 'other',
   'public_domain', 'indefinite', true, 'active',
   'Values Qamar carries without an external source. Low confidence by '
   'definition. Never a substitute for a composition table — a row here is an '
   'admission that the right value is not known yet.')
on conflict (source_id) do nothing;

create temporary table _dish (slug text primary key, borrowed_from text);
insert into _dish values
  ('basterma',   'Horseradish, prepared (173472)'),
  ('fesikh',     'Horseradish, prepared (173472)'),
  ('mahalabia',  'Horseradish, prepared (173472)'),
  ('sobia',      'Horseradish, prepared (173472)'),
  ('konafa',     'Puff pastry, frozen, ready-to-bake, baked (172738)'),
  ('om_ali',     'Puff pastry, frozen, ready-to-bake, baked (172738)'),
  ('basbousa',   'Puff pastry, frozen, ready-to-bake, baked (172738)'),
  ('zalabia',    'Tofu, fried (172451)'),
  ('karkade',    'Lemonade-flavor drink, powder (174861)'),
  ('tamr_hindi', 'Lemonade-flavor drink, powder (174861)'),
  ('erksous',    'Lemonade-flavor drink, powder (174861)'),
  ('mango_juice','Cranberry juice cocktail, frozen concentrate (173654)'),
  ('eshta',      'Cake, boston cream pie, commercially prepared (172696)'),
  ('freekeh',    'Asparagus, cooked, boiled, drained (168390)');

delete from public.food_source_links l
using public.foods f, _dish d
where f.slug = d.slug and l.qamar_food_id = f.qamar_food_id and l.source_id = 'usda_fdc';

update public.food_nutrients fn
set source_id = 'qamar_estimate', confidence = 0.25
from public.foods f, _dish d
where f.slug = d.slug and fn.qamar_food_id = f.qamar_food_id and fn.source_id = 'usda_fdc';

update public.foods f
set confidence = least(coalesce(f.confidence, 1), 0.30),
    has_conflicting_values = true
from _dish d
where f.slug = d.slug;

create or replace view public.food_values_provisional
with (security_invoker = true) as
select f.slug, f.name_en, f.name_ar,
       (select fn.amount from public.food_nutrients fn
         where fn.qamar_food_id = f.qamar_food_id
           and fn.nutrient_code = 'energy_kcal') as kcal_per_100g,
       (select count(*) from public.food_nutrients fn
         where fn.qamar_food_id = f.qamar_food_id
           and fn.source_id = 'qamar_estimate') as provisional_rows,
       not exists (
         select 1 from public.food_source_links l
         where l.qamar_food_id = f.qamar_food_id
       ) as uncited
from public.foods f
where f.source_rank > 10
  and exists (
    select 1 from public.food_nutrients fn
    where fn.qamar_food_id = f.qamar_food_id and fn.source_id = 'qamar_estimate'
  )
order by f.slug;

comment on view public.food_values_provisional is
  'Foods whose numbers Qamar carries without a source. Each one is a promise '
  'to find a real composition table, not a value to trust.';

revoke all on public.food_values_provisional from public, anon, authenticated;
grant select on public.food_values_provisional to service_role;

do $$
declare n_links int; n_prov int;
begin
  select count(*) into n_links from public.food_source_links l
   join public.foods f on f.qamar_food_id = l.qamar_food_id
   join _dish d on d.slug = f.slug;
  select count(*) into n_prov from public.food_values_provisional;
  if n_links > 0 then
    raise exception '% false citations survived', n_links;
  end if;
  raise notice 'citations stripped; % foods now provisional', n_prov;
end;
$$;

drop table _dish;
notify pgrst, 'reload schema';
