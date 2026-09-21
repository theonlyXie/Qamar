-- USDA FoodData Central ids for the ingredients the search cannot be trusted
-- to find on its own.
--
-- ingest_usda.ts matches a food by token overlap on name_en + food_state and
-- leaves anything under the floor alone. For the ingredients 0051 added, and
-- for the 0017 ingredients that never received a value, the right USDA row was
-- decided by reading the candidates rather than trusting the score:
--
--   - SR Legacy entries over Foundation Foods. Foundation rows for water, corn
--     oil, almonds and raisins carry no energy value at all, which is what left
--     those 0017 ingredients empty after the first ingest.
--   - Cooked over raw where the recipe weighs the ingredient cooked (chicken,
--     tripe, shank, green beans, chard), raw where it weighs it raw.
--   - Unenriched flour and semolina, because Egyptian flour is not fortified.
--   - The closest relative where USDA has no Egyptian food: whole-wheat pita
--     for baladi bread, white pita for shami bread and roqaq, white loaf for
--     fino, whole-milk yogurt for laban rayeb.
--
-- Each mapping is a food_source_links row. The importer sees the row and
-- fetches that id directly, never searching for these foods again, and the row
-- is the record of who decided what. Nothing here is a nutrient value; the rows
-- say where the values come from.

with m(slug, fdc_id, usda_description) as (values
  -- 0051 ingredients
  ('wheat_flour',    '169761', 'Wheat flour, white, all-purpose, unenriched'),
  ('semolina',       '168933', 'Semolina, unenriched'),
  ('phyllo_dough',   '172791', 'Phyllo dough'),
  ('puff_pastry',    '172738', 'Puff pastry, frozen, ready-to-bake, baked'),
  ('breadcrumbs',    '174928', 'Bread, crumbs, dry, grated, plain'),
  ('cornstarch',     '169698', 'Cornstarch'),
  ('rice_flour',     '169714', 'Rice flour, white, unenriched'),
  ('couscous',       '169700', 'Couscous, cooked'),
  ('toast_white',    '325871', 'Bread, white, commercially prepared'),
  ('toast_brown',    '172688', 'Bread, whole-wheat, commercially prepared'),
  ('cream',          '170859', 'Cream, fluid, heavy whipping'),
  ('milk_powder',    '173454', 'Milk, dry, whole, without added vitamin D'),
  ('condensed_milk', '171275', 'Milk, canned, condensed, sweetened'),
  ('mozzarella',     '170845', 'Cheese, mozzarella, whole milk'),
  ('cheddar',        '328637', 'Cheese, cheddar'),
  ('cream_cheese',   '173418', 'Cheese, cream'),
  ('ground_beef',    '174036', 'Beef, ground, 80% lean meat / 20% fat, raw'),
  ('ground_lamb',    '174370', 'Lamb, ground, raw'),
  ('chicken_liver',  '171061', 'Chicken, liver, all classes, cooked, simmered'),
  ('chicken_roasted','171450', 'Chicken, broilers or fryers, meat and skin, cooked, roasted'),
  ('chicken_stewed', '171051', 'Chicken, broilers or fryers, meat and skin, cooked, stewed'),
  ('duck',           '172409', 'Duck, domesticated, meat and skin, cooked, roasted'),
  ('pigeon',         '174475', 'Squab, (pigeon), meat and skin, raw'),
  ('quail',          '172418', 'Quail, meat and skin, raw'),
  ('rabbit',         '172522', 'Game meat, rabbit, domesticated, composite of cuts, cooked, roasted'),
  ('beef_tripe',     '174769', 'Beef, variety meats and by-products, tripe, cooked, simmered'),
  ('beef_brain',     '168623', 'Beef, variety meats and by-products, brain, cooked, pan-fried'),
  ('beef_shank',     '169442', 'Beef, shank crosscuts, separable lean only, trimmed to 1/4" fat, choice, cooked, simmered'),
  ('bologna',        '172012', 'Bologna, beef'),
  ('squid',          '171982', 'Mollusks, squid, mixed species, cooked, fried'),
  ('crab',           '174205', 'Crustaceans, crab, blue, cooked, moist heat'),
  ('sea_bass',       '173694', 'Fish, sea bass, mixed species, cooked, dry heat'),
  ('mackerel',       '175120', 'Fish, mackerel, Atlantic, cooked, dry heat'),
  ('tomato_paste',   '170459', 'Tomato products, canned, paste, without salt added'),
  ('green_beans',    '169141', 'Beans, snap, green, cooked, boiled, drained, without salt'),
  ('artichoke',      '168386', 'Artichokes, (globe or french), cooked, boiled, drained, without salt'),
  ('corn',           '169999', 'Corn, sweet, yellow, cooked, boiled, drained, without salt'),
  ('pumpkin',        '168449', 'Pumpkin, cooked, boiled, drained, without salt'),
  ('mushrooms',      '169251', 'Mushrooms, white, raw'),
  ('celery',         '169988', 'Celery, raw'),
  ('mint',           '173474', 'Peppermint, fresh'),
  ('green_onion',    '170005', 'Onions, spring or scallions (includes tops and bulb), raw'),
  ('beets',          '169146', 'Beets, cooked, boiled, drained'),
  ('turnip',         '170465', 'Turnips, raw'),
  ('pickles',        '168558', 'Pickles, cucumber, dill or kosher dill'),
  ('chard',          '170401', 'Chard, swiss, cooked, boiled, drained, without salt'),
  ('french_fries',   '170698', 'Fast foods, potato, french fried in vegetable oil'),
  ('dried_apricots', '173941', 'Apricots, dried, sulfured, uncooked'),
  ('dried_figs',     '174665', 'Figs, dried, uncooked'),
  ('prunes',         '168162', 'Plums, dried (prunes), uncooked'),
  ('raisins',        '168165', 'Raisins, dark, seedless'),
  ('tamarind',       '167763', 'Tamarinds, raw'),
  ('hibiscus_tea',   '171946', 'Beverages, tea, hibiscus, brewed'),
  ('orange_juice',   '169098', 'Orange juice, raw'),
  ('water',          '173647', 'Beverages, water, tap, drinking'),
  ('salt',           '173468', 'Salt, table'),
  ('cumin',          '170923', 'Spices, cumin seed'),
  ('coriander_seed', '170922', 'Spices, coriander seed'),
  ('anise',          '171316', 'Spices, anise seed'),
  ('fenugreek',      '171324', 'Spices, fenugreek seed'),
  ('cinnamon',       '171320', 'Spices, cinnamon, ground'),
  ('ginger',         '169231', 'Ginger root, raw'),
  ('vinegar',        '172237', 'Vinegar, distilled'),
  ('mayonnaise',     '171009', 'Salad dressing, mayonnaise, regular'),
  ('pistachios',     '170184', 'Nuts, pistachio nuts, raw'),
  ('coconut',        '170170', 'Nuts, coconut meat, dried (desiccated), not sweetened'),
  ('jam',            '169641', 'Jams and preserves'),
  ('ice_cream',      '167575', 'Ice creams, vanilla'),
  -- 0017 ingredients the first ingest left without an energy value
  ('almonds',        '170567', 'Nuts, almonds'),
  ('apricot',        '171697', 'Apricots, raw'),
  ('baladi_bread',   '174916', 'Bread, pita, whole-wheat'),
  ('chicken_thigh',  '173625', 'Chicken, broilers or fryers, thigh, meat and skin, cooked, roasted'),
  ('corn_oil',       '171029', 'Oil, corn, industrial and retail, all purpose salad or cooking'),
  ('fino_bread',     '325871', 'Bread, white, commercially prepared'),
  ('hazelnuts',      '170581', 'Nuts, hazelnuts or filberts'),
  ('laban_rayeb',    '171284', 'Yogurt, plain, whole milk'),
  ('lettuce',        '169247', 'Lettuce, cos or romaine, raw'),
  ('mango',          '169910', 'Mangos, raw'),
  ('molasses',       '168820', 'Molasses'),
  ('peanuts',        '172430', 'Peanuts, all types, raw'),
  ('pepper_green',   '170427', 'Peppers, sweet, green, raw'),
  ('roqaq',          '174915', 'Bread, pita, white, enriched'),
  ('shami_bread',    '174915', 'Bread, pita, white, enriched'),
  ('sunflower_seeds','170562', 'Seeds, sunflower seed kernels, dried'),
  ('walnuts',        '170187', 'Nuts, walnuts, english')
)
insert into public.food_source_links
  (qamar_food_id, source_id, external_id, external_type, url, field_provenance)
select f.qamar_food_id, 'usda_fdc', m.fdc_id, 'fdc_id',
       'https://fdc.nal.usda.gov/food-details/' || m.fdc_id || '/nutrients',
       jsonb_build_object(
         'usda_description', m.usda_description,
         'mapped_in', '0052',
         'decided_by', 'hand: closest SR Legacy row with an energy value')
from m
join public.foods f on f.slug = m.slug
on conflict (qamar_food_id, source_id, external_id) do nothing;
