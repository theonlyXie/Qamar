-- Egyptian food seed: the layer no external database has.
--
-- What is here and what is deliberately not:
--
--   HERE   names, Arabic and Egyptian colloquial aliases, misspellings, food
--          groups, diet attributes, household portions, recipe compositions.
--          This is language and culture. It is authored, and it is the half
--          that makes "أكلت رغيف عيش بلدي" resolve locally instead of costing
--          an API call and a paragraph of tokens.
--
--   NOT    a single nutrient value. Those come from USDA FoodData Central via
--          ingest_usda.ts, written with source_id = 'usda_fdc' and the fdcId in
--          food_source_links, so every figure traces to a laboratory analysis.
--          Typing per-100g numbers from memory into a table whose purpose is
--          provenance would defeat the table.
--
-- Portions are estimates and say so: basis = 'estimated', confidence 0.5,
-- human_reviewed = false. An Egyptian loaf varies by bakery and a ladle varies
-- by household, so these are a usable starting point for a resolver and a
-- worklist for a dietitian, not measurements. The UI should treat low
-- confidence as a prompt to confirm rather than a number to assert.

-- ---------------------------------------------------------------------
-- Foods
-- ---------------------------------------------------------------------

with f(slug, en, ar, eg, grp, state, vegan, vegetarian, gluten, allergens) as (values
-- breads and grains
('baladi_bread','Baladi bread','خبز بلدي','عيش بلدي','grain','baked',true,true,true,'{gluten}'),
('fino_bread','Fino roll','خبز فينو','عيش فينو','grain','baked',true,true,true,'{gluten}'),
('shami_bread','Shami bread','خبز شامي','عيش شامي','grain','baked',true,true,true,'{gluten}'),
('feteer','Feteer meshaltet','فطير مشلتت','فطير','grain','baked',false,true,true,'{gluten,dairy}'),
('roqaq','Roqaq sheets','رقاق','رقاق','grain','baked',true,true,true,'{gluten}'),
('white_rice','White rice, cooked','أرز أبيض مطبوخ','رز','grain','boiled',true,true,false,'{}'),
('brown_rice','Brown rice, cooked','أرز بني مطبوخ','رز بني','grain','boiled',true,true,false,'{}'),
('macaroni','Macaroni, cooked','مكرونة مسلوقة','مكرونة','grain','boiled',true,true,true,'{gluten}'),
('vermicelli','Vermicelli','شعرية','شعرية','grain','cooked',true,true,true,'{gluten}'),
('freekeh','Freekeh, cooked','فريك مطبوخ','فريك','grain','boiled',true,true,true,'{gluten}'),
('bulgur','Bulgur, cooked','برغل مطبوخ','برغل','grain','boiled',true,true,true,'{gluten}'),
('oats','Oats','شوفان','شوفان','grain','raw',true,true,false,'{}'),
-- legumes
('foul_beans','Fava beans, cooked','فول مدمس','فول','legume','boiled',true,true,false,'{}'),
('foul_nabet','Sprouted fava beans','فول نابت','فول نابت','legume','boiled',true,true,false,'{}'),
('yellow_lentils','Yellow lentils, cooked','عدس أصفر مطبوخ','عدس أصفر','legume','boiled',true,true,false,'{}'),
('brown_lentils','Brown lentils, cooked','عدس أسود مطبوخ','عدس أسود','legume','boiled',true,true,false,'{}'),
('chickpeas','Chickpeas, cooked','حمص مسلوق','حمص','legume','boiled',true,true,false,'{}'),
('white_beans','White beans, cooked','فاصوليا بيضاء','فاصوليا','legume','boiled',true,true,false,'{}'),
('black_eyed_peas','Black-eyed peas','لوبيا','لوبيا','legume','boiled',true,true,false,'{}'),
('green_peas','Green peas','بسلة','بسلة','legume','boiled',true,true,false,'{}'),
('lupini','Lupini beans','ترمس','ترمس','legume','boiled',true,true,false,'{}'),
-- dairy and eggs
('areesh_cheese','Areesh cheese','جبنة قريش','قريش','dairy','prepared',false,true,false,'{dairy}'),
('white_cheese','White brined cheese','جبنة بيضاء','جبنة بيضة','dairy','prepared',false,true,false,'{dairy}'),
('roumy_cheese','Roumy cheese','جبنة رومي','رومي','dairy','prepared',false,true,false,'{dairy}'),
('istanbouli_cheese','Istanbouli cheese','جبنة إسطنبولي','إسطنبولي','dairy','prepared',false,true,false,'{dairy}'),
('milk','Milk','لبن','لبن حليب','dairy','raw',false,true,false,'{dairy}'),
('yogurt','Yogurt','زبادي','زبادي','dairy','prepared',false,true,false,'{dairy}'),
('laban_rayeb','Laban rayeb','لبن رايب','رايب','dairy','prepared',false,true,false,'{dairy}'),
('eshta','Clotted cream','قشطة','قشطة','dairy','prepared',false,true,false,'{dairy}'),
('butter','Butter','زبدة','زبدة','fat','prepared',false,true,false,'{dairy}'),
('samna','Ghee','سمنة','سمنة','fat','prepared',false,true,false,'{dairy}'),
('eggs','Eggs','بيض','بيض','protein','boiled',false,true,false,'{egg}'),
-- meat, poultry, fish
('chicken_breast','Chicken breast','صدور فراخ','فراخ','protein','grilled',false,false,false,'{}'),
('chicken_thigh','Chicken thigh','ورك فراخ','ورك فراخ','protein','grilled',false,false,false,'{}'),
('beef','Beef','لحم بقري','لحمة','protein','cooked',false,false,false,'{}'),
('lamb','Lamb','لحم ضاني','ضاني','protein','cooked',false,false,false,'{}'),
('liver','Liver','كبدة','كبدة','protein','cooked',false,false,false,'{}'),
('sausage_egyptian','Egyptian sausage','سجق','سجق','protein','cooked',false,false,false,'{}'),
('basterma','Basterma','بسطرمة','بسطرمة','protein','prepared',false,false,false,'{}'),
('tilapia','Tilapia','سمك بلطي','بلطي','protein','grilled',false,false,false,'{fish}'),
('mullet','Mullet','سمك بوري','بوري','protein','grilled',false,false,false,'{fish}'),
('herring','Herring','رنجة','رنجة','protein','prepared',false,false,false,'{fish}'),
('fesikh','Fesikh','فسيخ','فسيخ','protein','prepared',false,false,false,'{fish}'),
('sardines','Sardines','سردين','سردين','protein','canned',false,false,false,'{fish}'),
('tuna_canned','Canned tuna','تونة معلبة','تونة','protein','canned',false,false,false,'{fish}'),
('shrimp','Shrimp','جمبري','جمبري','protein','cooked',false,false,false,'{shellfish}'),
-- vegetables
('tomato','Tomato','طماطم','قوطة','vegetable','raw',true,true,false,'{}'),
('cucumber','Cucumber','خيار','خيار','vegetable','raw',true,true,false,'{}'),
('onion','Onion','بصل','بصل','vegetable','raw',true,true,false,'{}'),
('garlic','Garlic','ثوم','توم','vegetable','raw',true,true,false,'{}'),
('carrot','Carrot','جزر','جزر','vegetable','raw',true,true,false,'{}'),
('potato','Potato','بطاطس','بطاطس','vegetable','boiled',true,true,false,'{}'),
('sweet_potato','Sweet potato','بطاطا','بطاطا','vegetable','baked',true,true,false,'{}'),
('eggplant','Eggplant','باذنجان','بتنجان','vegetable','cooked',true,true,false,'{}'),
('zucchini','Zucchini','كوسة','كوسة','vegetable','cooked',true,true,false,'{}'),
('okra','Okra','بامية','بامية','vegetable','cooked',true,true,false,'{}'),
('molokhia_leaves','Molokhia leaves','ملوخية','ملوخية','vegetable','cooked',true,true,false,'{}'),
('spinach','Spinach','سبانخ','سبانخ','vegetable','cooked',true,true,false,'{}'),
('pepper_green','Green pepper','فلفل أخضر','فلفل','vegetable','raw',true,true,false,'{}'),
('cabbage','Cabbage','كرنب','كرنب','vegetable','raw',true,true,false,'{}'),
('cauliflower','Cauliflower','قرنبيط','قرنبيط','vegetable','cooked',true,true,false,'{}'),
('lettuce','Lettuce','خس','خس','vegetable','raw',true,true,false,'{}'),
('arugula','Arugula','جرجير','جرجير','vegetable','raw',true,true,false,'{}'),
('radish','Radish','فجل','فجل','vegetable','raw',true,true,false,'{}'),
('parsley','Parsley','بقدونس','بقدونس','vegetable','raw',true,true,false,'{}'),
('coriander','Coriander','كزبرة','كزبرة','vegetable','raw',true,true,false,'{}'),
('dill','Dill','شبت','شبت','vegetable','raw',true,true,false,'{}'),
('taro','Taro','قلقاس','قلقاس','vegetable','cooked',true,true,false,'{}'),
('grape_leaves','Grape leaves','ورق عنب','ورق عنب','vegetable','cooked',true,true,false,'{}'),
-- fruit
('banana','Banana','موز','موز','fruit','raw',true,true,false,'{}'),
('orange','Orange','برتقال','برتقان','fruit','raw',true,true,false,'{}'),
('apple','Apple','تفاح','تفاح','fruit','raw',true,true,false,'{}'),
('grapes','Grapes','عنب','عنب','fruit','raw',true,true,false,'{}'),
('mango','Mango','مانجو','مانجا','fruit','raw',true,true,false,'{}'),
('watermelon','Watermelon','بطيخ','بطيخ','fruit','raw',true,true,false,'{}'),
('cantaloupe','Cantaloupe','كنتالوب','كنتالوب','fruit','raw',true,true,false,'{}'),
('strawberry','Strawberry','فراولة','فراولة','fruit','raw',true,true,false,'{}'),
('figs','Figs','تين','تين','fruit','raw',true,true,false,'{}'),
('dates','Dates','تمر','بلح','fruit','raw',true,true,false,'{}'),
('pomegranate','Pomegranate','رمان','رمان','fruit','raw',true,true,false,'{}'),
('guava','Guava','جوافة','جوافة','fruit','raw',true,true,false,'{}'),
('peach','Peach','خوخ','خوخ','fruit','raw',true,true,false,'{}'),
('apricot','Apricot','مشمش','مشمش','fruit','raw',true,true,false,'{}'),
('lemon','Lemon','ليمون','لمون','fruit','raw',true,true,false,'{}'),
-- nuts, seeds, fats
('tahina','Tahina','طحينة','طحينة','fat','prepared',true,true,false,'{sesame}'),
('sesame','Sesame seeds','سمسم','سمسم','fat','raw',true,true,false,'{sesame}'),
('almonds','Almonds','لوز','لوز','fat','raw',true,true,false,'{tree_nut}'),
('walnuts','Walnuts','عين جمل','عين جمل','fat','raw',true,true,false,'{tree_nut}'),
('hazelnuts','Hazelnuts','بندق','بندق','fat','raw',true,true,false,'{tree_nut}'),
('peanuts','Peanuts','فول سوداني','سوداني','fat','raw',true,true,false,'{peanut}'),
('sunflower_seeds','Sunflower seeds','لب سوري','لب','fat','raw',true,true,false,'{}'),
('olive_oil','Olive oil','زيت زيتون','زيت زيتون','fat','raw',true,true,false,'{}'),
('corn_oil','Corn oil','زيت ذرة','زيت','fat','raw',true,true,false,'{}'),
('olives','Olives','زيتون','زيتون','vegetable','prepared',true,true,false,'{}'),
-- sweets and sugars
('sugar','Sugar','سكر','سكر','sweet','raw',true,true,false,'{}'),
('honey','Honey','عسل نحل','عسل نحل','sweet','raw',false,true,false,'{}'),
('molasses','Black honey / molasses','عسل أسود','عسل أسود','sweet','prepared',true,true,false,'{}'),
('halawa','Halva','حلاوة طحينية','حلاوة','sweet','prepared',true,true,false,'{sesame}'),
('konafa','Konafa','كنافة','كنافة','sweet','baked',false,true,true,'{gluten,dairy,tree_nut}'),
('basbousa','Basbousa','بسبوسة','بسبوسة','sweet','baked',false,true,true,'{gluten,dairy}'),
('om_ali','Om Ali','أم علي','أم علي','sweet','baked',false,true,true,'{gluten,dairy,tree_nut}'),
('balah_el_sham','Balah el Sham','بلح الشام','بلح الشام','sweet','fried',false,true,true,'{gluten}'),
('zalabia','Zalabia','زلابية','زلابية','sweet','fried',true,true,true,'{gluten}'),
('mahalabia','Mahalabia','مهلبية','مهلبية','sweet','prepared',false,true,false,'{dairy}'),
('rice_pudding','Rice pudding','أرز بلبن','رز بلبن','sweet','prepared',false,true,false,'{dairy}'),
-- drinks
('tea','Tea, brewed','شاي','شاي','drink','prepared',true,true,false,'{}'),
('coffee','Coffee','قهوة','قهوة','drink','prepared',true,true,false,'{}'),
('karkade','Hibiscus drink','كركديه','كركديه','drink','prepared',true,true,false,'{}'),
('erksous','Liquorice drink','عرقسوس','عرقسوس','drink','prepared',true,true,false,'{}'),
('tamr_hindi','Tamarind drink','تمر هندي','تمر هندي','drink','prepared',true,true,false,'{}'),
('sobia','Sobia','سوبيا','سوبيا','drink','prepared',false,true,false,'{dairy}'),
('sugarcane_juice','Sugarcane juice','عصير قصب','عصير قصب','drink','raw',true,true,false,'{}'),
('mango_juice','Mango juice','عصير مانجو','عصير مانجا','drink','prepared',true,true,false,'{}'),
('soft_drink','Soft drink','مشروب غازي','حاجة ساقعة','drink','prepared',true,true,false,'{}'),
-- composite dishes, marked as recipes
('koshary','Koshary','كشري','كشري','dish','prepared',true,true,true,'{gluten}'),
('molokhia_dish','Molokhia with chicken','ملوخية بالفراخ','ملوخية','dish','cooked',false,false,false,'{}'),
('taameya','Taameya (falafel)','طعمية','طعمية','dish','fried',true,true,false,'{}'),
('mahshi_cabbage','Stuffed cabbage','محشي كرنب','محشي كرنب','dish','cooked',true,true,false,'{}'),
('mahshi_grape','Stuffed grape leaves','محشي ورق عنب','ورق عنب محشي','dish','cooked',true,true,false,'{}'),
('bamia_meat','Okra with meat','بامية باللحمة','بامية باللحمة','dish','cooked',false,false,false,'{}'),
('shakshouka','Shakshouka','شكشوكة','شكشوكة','dish','cooked',false,true,false,'{egg}'),
('mesaqaa','Mesaqaa','مسقعة','مسقعة','dish','fried',true,true,false,'{}'),
('hawawshi','Hawawshi','حواوشي','حواوشي','dish','baked',false,false,true,'{gluten}'),
('shawarma','Shawarma','شاورما','شاورما','dish','grilled',false,false,true,'{gluten}'),
('kebda_eskandarani','Alexandrian liver','كبدة إسكندراني','كبدة إسكندراني','dish','cooked',false,false,false,'{}'),
('fatta','Fatta','فتة','فتة','dish','prepared',false,false,true,'{gluten}'),
('macarona_bechamel','Macaroni bechamel','مكرونة بشاميل','مكرونة بشاميل','dish','baked',false,false,true,'{gluten,dairy}'),
('sayadeya','Sayadeya','صيادية','صيادية','dish','cooked',false,false,false,'{fish}'),
('baba_ghanoug','Baba ghanoug','بابا غنوج','بابا غنوج','dish','prepared',true,true,false,'{sesame}'),
('salata_baladi','Baladi salad','سلطة بلدي','سلطة بلدي','dish','raw',true,true,false,'{}'),
('tahina_salad','Tahina salad','سلطة طحينة','سلطة طحينة','dish','prepared',true,true,false,'{sesame}')
)
insert into public.foods
  (slug, name_en, name_ar, name_eg, food_group, food_state, is_vegan, is_vegetarian,
   contains_gluten, allergens, is_recipe, country_region, confidence, human_reviewed, source_rank)
select f.slug, f.en, f.ar, f.eg, f.grp, f.state, f.vegan, f.vegetarian,
       f.gluten, f.allergens::text[], (f.grp = 'dish'), 'EG', 0.50, false, 50
from f
on conflict (slug) do nothing;

-- ---------------------------------------------------------------------
-- Aliases: how people actually say it, including how they mistype it
-- ---------------------------------------------------------------------

with a(slug, alias, lang, misspell) as (values
('baladi_bread','عيش','eg',false),('baladi_bread','عيش بلدى','eg',true),('baladi_bread','رغيف','eg',false),
('baladi_bread','خبز','ar',false),('baladi_bread','aish baladi','translit',false),('baladi_bread','eish','translit',true),
('foul_beans','فول مدمس','eg',false),('foul_beans','فول بالزيت','eg',false),('foul_beans','ful','translit',false),
('foul_beans','foul medames','translit',false),('foul_beans','فول مدمص','eg',true),
('taameya','فلافل','eg',false),('taameya','falafel','translit',false),('taameya','ta3meya','translit',false),
('taameya','طعميه','eg',true),
('koshary','كشرى','eg',true),('koshary','koshari','translit',false),('koshary','kushari','translit',false),
('koshary','كوشري','eg',true),
('molokhia_dish','ملوخيه','eg',true),('molokhia_dish','molokhia','translit',false),('molokhia_dish','mulukhiyah','translit',false),
('areesh_cheese','قريش','eg',false),('areesh_cheese','جبنه قريش','eg',true),('areesh_cheese','areesh','translit',false),
('white_cheese','جبنه بيضا','eg',true),('white_cheese','جبنة فيتا','ar',false),
('roumy_cheese','جبنه رومي','eg',true),('roumy_cheese','roumy','translit',false),
('white_rice','رز أبيض','eg',false),('white_rice','أرز','ar',false),('white_rice','rozz','translit',false),
('macaroni','مكرونه','eg',true),('macaroni','باستا','ar',false),('macaroni','makarona','translit',false),
('eggs','بيضة','ar',false),('eggs','بيض مسلوق','eg',false),('eggs','beid','translit',false),
('chicken_breast','فراخ','eg',false),('chicken_breast','دجاج','ar',false),('chicken_breast','firakh','translit',false),
('beef','لحمة بقري','eg',false),('beef','لحمه','eg',true),('beef','lahma','translit',false),
('tilapia','بلطى','eg',true),('tilapia','سمك','eg',false),('tilapia','bolti','translit',false),
('yogurt','زبادى','eg',true),('yogurt','روب','eg',false),('yogurt','zabady','translit',false),
('tomato','طماطم','ar',false),('tomato','أوطة','eg',false),('tomato','2ota','translit',false),
('molokhia_leaves','ورق ملوخية','ar',false),
('okra','باميا','eg',true),('okra','bamia','translit',false),
('eggplant','باذنجان','ar',false),('eggplant','betengan','translit',false),
('dates','بلح','eg',false),('dates','تمر','ar',false),('dates','balah','translit',false),
('mango','مانجا','eg',false),('mango','manga','translit',false),
('tahina','طحينه','eg',true),('tahina','tahini','translit',false),
('tea','شاى','eg',true),('tea','shay','translit',false),
('sugarcane_juice','قصب','eg',false),('sugarcane_juice','asab','translit',false),
('hawawshi','حواوشى','eg',true),('hawawshi','hawawshi','translit',false),
('shawarma','شورما','eg',true),('shawarma','shawerma','translit',false),
('mahshi_cabbage','محشي','eg',false),('mahshi_cabbage','mahshi','translit',false),
('mahshi_grape','محشي عنب','eg',false),('mahshi_grape','warak enab','translit',false),
('macarona_bechamel','بشاميل','eg',false),('macarona_bechamel','bechamel','translit',false),
('kebda_eskandarani','كبدة','eg',false),('kebda_eskandarani','kebda','translit',false),
('basbousa','بسبوسه','eg',true),('basbousa','basbousa','translit',false),
('konafa','كنافه','eg',true),('konafa','kunafa','translit',false),
('om_ali','ام علي','eg',true),('om_ali','om ali','translit',false),
('molasses','عسل إسود','eg',true),
('lupini','ترمص','eg',true),
('feteer','فطير','eg',false),('feteer','feteer','translit',false),
('shakshouka','شكشوكه','eg',true),
('baba_ghanoug','متبل','eg',false),('baba_ghanoug','baba ghanoush','translit',false),
('salata_baladi','سلطة خضرا','eg',false),('salata_baladi','سلطه','eg',true)
)
insert into public.food_aliases (qamar_food_id, alias, lang, is_misspelling, priority)
select fo.qamar_food_id, a.alias, a.lang, a.misspell, case when a.misspell then 50 else 100 end
from a join public.foods fo on fo.slug = a.slug
on conflict (qamar_food_id, alias, lang) do nothing;

-- Every food also answers to its own three names.
insert into public.food_aliases (qamar_food_id, alias, lang, priority)
select qamar_food_id, name_en, 'en', 120 from public.foods where name_en is not null
on conflict (qamar_food_id, alias, lang) do nothing;
insert into public.food_aliases (qamar_food_id, alias, lang, priority)
select qamar_food_id, name_ar, 'ar', 120 from public.foods where name_ar is not null
on conflict (qamar_food_id, alias, lang) do nothing;
insert into public.food_aliases (qamar_food_id, alias, lang, priority)
select qamar_food_id, name_eg, 'eg', 130 from public.foods where name_eg is not null
on conflict (qamar_food_id, alias, lang) do nothing;

-- ---------------------------------------------------------------------
-- Household portions — ESTIMATES, flagged as such
-- ---------------------------------------------------------------------

with p(slug, label_en, label_ar, grams, is_default) as (values
('baladi_bread','1 loaf','رغيف',90,true),('baladi_bread','half loaf','نص رغيف',45,false),
('fino_bread','1 roll','عيشة فينو',60,true),
('shami_bread','1 loaf','رغيف شامي',70,true),
('feteer','1 slice','قطعة',120,true),
('white_rice','1 serving spoon','معلقة أرز',60,false),('white_rice','1 plate','طبق',180,true),
('macaroni','1 plate','طبق',200,true),
('foul_beans','1 plate','طبق فول',200,true),('foul_beans','1 sandwich portion','سندوتش',60,false),
('taameya','1 piece','قرص',25,true),('taameya','1 sandwich (3 pieces)','سندوتش',75,false),
('koshary','small bowl','علبة صغيرة',350,true),('koshary','large bowl','علبة كبيرة',550,false),
('molokhia_dish','1 bowl','سلطانية',250,true),
('yogurt','1 tub','علبة زبادي',105,true),
('milk','1 cup','كوباية',240,true),
('areesh_cheese','1 tablespoon','معلقة',30,false),('areesh_cheese','1 serving','طبق صغير',100,true),
('white_cheese','1 slice','شريحة',30,true),
('roumy_cheese','1 slice','شريحة',25,true),
('eggs','1 egg','بيضة',50,true),('eggs','2 eggs','بيضتين',100,false),
('chicken_breast','1 breast','صدر',150,true),
('chicken_thigh','1 thigh','ورك',120,true),
('beef','1 serving','قطعة لحمة',150,true),
('liver','1 serving','طبق كبدة',120,true),
('tilapia','1 fish','سمكة',200,true),
('tuna_canned','1 can','علبة',140,true),
('sardines','1 can','علبة',100,true),
('tea','1 glass','كوباية شاي',200,true),
('coffee','1 cup','فنجان',60,true),
('sugar','1 teaspoon','معلقة صغيرة سكر',5,true),('sugar','1 tablespoon','معلقة كبيرة سكر',15,false),
('sugarcane_juice','1 glass','كوباية قصب',300,true),
('mango_juice','1 glass','كوباية',250,true),
('soft_drink','1 can','علبة',330,true),
('olive_oil','1 tablespoon','معلقة زيت',14,true),
('tahina','1 tablespoon','معلقة طحينة',15,true),
('banana','1 medium','موزة',120,true),
('orange','1 medium','برتقالة',150,true),
('apple','1 medium','تفاحة',180,true),
('mango','1 medium','مانجة',200,true),
('dates','1 date','بلحة',8,true),('dates','1 handful','حفنة',50,false),
('guava','1 medium','جوافة',120,true),
('watermelon','1 slice','شريحة بطيخ',280,true),
('potato','1 medium','بطاطسة',150,true),
('tomato','1 medium','طماطمة',120,true),
('cucumber','1 medium','خيارة',110,true),
('onion','1 medium','بصلة',110,true),
('hawawshi','1 piece','حواوشي',220,true),
('shawarma','1 sandwich','سندوتش شاورما',250,true),
('mahshi_cabbage','1 piece','ورقة محشي',40,true),
('mahshi_grape','1 piece','ورقة عنب',15,true),
('macarona_bechamel','1 serving','طبق',300,true),
('basbousa','1 piece','قطعة',80,true),
('konafa','1 piece','قطعة',100,true),
('om_ali','1 bowl','طبق',200,true),
('rice_pudding','1 bowl','طبق رز بلبن',180,true),
('mahalabia','1 bowl','طبق مهلبية',150,true),
('halawa','1 tablespoon','معلقة حلاوة',20,true),
('molasses','1 tablespoon','معلقة عسل أسود',20,true),
('honey','1 tablespoon','معلقة عسل',21,true),
('salata_baladi','1 plate','طبق سلطة',150,true),
('baba_ghanoug','1 serving','طبق',100,true),
('lupini','1 cup','كوباية ترمس',150,true),
('peanuts','1 handful','حفنة',30,true),
('sunflower_seeds','1 handful','حفنة لب',25,true)
)
insert into public.food_portions
  (qamar_food_id, label_en, label_ar, grams, is_household, is_default, basis, confidence, source_id)
select fo.qamar_food_id, p.label_en, p.label_ar, p.grams, true, p.is_default,
       'estimated', 0.50, null
from p join public.foods fo on fo.slug = p.slug
on conflict (qamar_food_id, label_en) do nothing;

-- ---------------------------------------------------------------------
-- Recipes — how the dishes are built
-- ---------------------------------------------------------------------
-- Compositions are cultural knowledge and reliable. The gram splits are
-- estimates on the same footing as the portions above: a household ladle is
-- not a measurement.

insert into public.recipes (qamar_food_id, servings, cooking_method, loss_gain_factor, household_note, confidence)
select qamar_food_id, s.servings, s.method, s.factor, s.note, 0.50
from (values
  ('koshary', 1.0, 'assembled', 1.000, 'Street portions vary widely; the small bowl is the common takeaway size.'),
  ('molokhia_dish', 4.0, 'boiled', 1.000, 'Served over rice, which is logged separately.'),
  ('taameya', 12.0, 'fried', 0.850, 'Absorbs frying oil; yield factor accounts for water loss.'),
  ('mahshi_cabbage', 20.0, 'boiled', 1.000, 'Rice filling swells during cooking.'),
  ('macarona_bechamel', 6.0, 'baked', 0.950, 'Family tray, cut into squares.'),
  ('salata_baladi', 2.0, 'raw', 1.000, 'Proportions vary; tomato-heavy is typical.')
) as s(slug, servings, method, factor, note)
join public.foods fo on fo.slug = s.slug
on conflict (qamar_food_id) do nothing;

with ri(recipe, ingredient, grams, ord) as (values
-- koshary, one small bowl
('koshary','white_rice',120,1),('koshary','macaroni',80,2),('koshary','brown_lentils',70,3),
('koshary','chickpeas',30,4),('koshary','onion',30,5),('koshary','tomato',50,6),('koshary','corn_oil',15,7),
-- molokhia, per pot of 4
('molokhia_dish','molokhia_leaves',400,1),('molokhia_dish','chicken_thigh',400,2),
('molokhia_dish','garlic',15,3),('molokhia_dish','samna',30,4),('molokhia_dish','coriander',10,5),
-- taameya, batch of 12
('taameya','foul_nabet',400,1),('taameya','onion',80,2),('taameya','parsley',40,3),
('taameya','coriander',30,4),('taameya','dill',20,5),('taameya','garlic',15,6),('taameya','corn_oil',60,7),
-- mahshi kromb, batch of 20
('mahshi_cabbage','cabbage',500,1),('mahshi_cabbage','white_rice',300,2),('mahshi_cabbage','tomato',150,3),
('mahshi_cabbage','onion',80,4),('mahshi_cabbage','dill',30,5),('mahshi_cabbage','corn_oil',45,6),
-- macarona bechamel, tray of 6
('macarona_bechamel','macaroni',500,1),('macarona_bechamel','beef',400,2),('macarona_bechamel','milk',750,3),
('macarona_bechamel','butter',60,4),('macarona_bechamel','onion',100,5),
-- salata baladi, for 2
('salata_baladi','tomato',150,1),('salata_baladi','cucumber',100,2),('salata_baladi','onion',40,3),
('salata_baladi','parsley',15,4),('salata_baladi','lemon',20,5),('salata_baladi','olive_oil',10,6)
)
-- NOT EXISTS rather than ON CONFLICT: the unique constraint carries `note`,
-- which is null here, and Postgres treats nulls as distinct — so a re-run would
-- duplicate every ingredient rather than conflicting.
insert into public.recipe_ingredients (recipe_id, ingredient_food_id, grams, sort_order)
select r.qamar_food_id, i.qamar_food_id, ri.grams, ri.ord
from ri
join public.foods r on r.slug = ri.recipe
join public.foods i on i.slug = ri.ingredient
where not exists (
  select 1 from public.recipe_ingredients x
  where x.recipe_id = r.qamar_food_id and x.ingredient_food_id = i.qamar_food_id
);
