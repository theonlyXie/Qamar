-- The first clinical rules, and the source gate that was keeping them out.
--
-- qamar_rule_selection (0022) returned nothing for every request. The obvious
-- reason was that clinical_rules is empty. It was not the only one: the
-- function also filters on qamar_source_usable_for_advice (0008), which is
-- true only when a source is `active`, has `ai_advice_rights = true` and is
-- not proprietary_unlicensed. Every guidance body in the registry —
-- who_nutrition, efsa_drv, nasem_dri, nih_ods, dga_2025 — was seeded
-- `deprecated` with `ai_advice_rights` null, so a fully populated rules table
-- would still have returned nothing. Both gates are opened here, and only for
-- sources whose licence is not in question.
--
-- WHICH SOURCES. Only works of the United States federal government, which
-- are public domain by 17 U.S.C. § 105: the Dietary Guidelines for Americans,
-- the Physical Activity Guidelines for Americans, and the NIH Office of
-- Dietary Supplements fact sheets. WHO, EFSA and NASEM stay `deprecated`:
-- their numbers are quotable but their licences are recorded as `unknown`,
-- and this file does not get to decide that question. Someone with the
-- authority to read a licence should; until they do, no rule may cite them.
--
-- WHICH RULES. The same rule that governs the food graph governs this file:
-- nothing is written from memory that cannot be traced. Every row below is a
-- quantitative, population-level value that has been stable across editions,
-- each carrying the edition it came from in `source_version` and a locator
-- that names the chapter or fact sheet. Nothing diagnostic, nothing
-- therapeutic, nothing about pregnancy or minors — scope.ts refuses all three
-- before a rule is ever selected, so a rule for those populations would be
-- unreachable and misleading to store.
--
-- NOT YET REVIEWED. `curator_id` says who entered each row; `reviewer_id` and
-- `last_verified` are null on every one, which is this schema's way of saying
-- no professional has checked it. dga_2020 is cited rather than dga_2025
-- because the 2020-2025 edition is the one these figures are quoted from; the
-- 2025-2030 edition supersedes it and every row needs re-verifying against it
-- (that is what supersedes_rule_id is for). The view at the end lists exactly
-- what is outstanding. This is a starting corpus, not a reviewed one.

-- ---------------------------------------------------------------------
-- 1. The sources
-- ---------------------------------------------------------------------

insert into public.source_registry (
  source_id, name, kind, official_docs_url, license_class, storage_rights,
  ai_advice_rights, regions_languages, status, notes
) values
  ('dga_2020', 'Dietary Guidelines for Americans 2020-2025', 'population_guidance',
   'https://www.dietaryguidelines.gov/', 'public_domain', 'indefinite', true,
   array['us','en'], 'active',
   'US federal work, public domain (17 U.S.C. 105). Superseded by the 2025-2030 edition; rules citing it must be re-verified against the current edition.'),
  ('hhs_pag_2018', 'Physical Activity Guidelines for Americans, 2nd edition (2018)', 'population_guidance',
   'https://health.gov/our-work/nutrition-physical-activity/physical-activity-guidelines',
   'public_domain', 'indefinite', true, array['us','en'], 'active',
   'US federal work, public domain (17 U.S.C. 105).')
on conflict (source_id) do update set
  license_class = excluded.license_class,
  storage_rights = excluded.storage_rights,
  ai_advice_rights = excluded.ai_advice_rights,
  status = excluded.status,
  notes = excluded.notes;

-- NIH ODS was already recorded public_domain; it only lacked the rights
-- answer and an active status.
update public.source_registry
   set status = 'active',
       ai_advice_rights = true,
       notes = coalesce(notes || ' ', '') ||
               'Activated for advice in 0056: US federal work, public domain.'
 where source_id = 'nih_ods';

-- Said out loud, so nobody reads the silence as "no rights".
update public.source_registry
   set notes = coalesce(notes || ' ', '') ||
               'Left deprecated in 0056: the numbers are quotable but the licence is '
               'unrecorded. A licence determination is needed before any rule may cite it.'
 where source_id in ('who_nutrition', 'efsa_drv', 'nasem_dri', 'dga_2025');

-- ---------------------------------------------------------------------
-- 2. The rules
-- ---------------------------------------------------------------------
--
-- One row per recommendation. `variable` uses the nutrient codes from 0009
-- where the recommendation is about a nutrient, and an explicit ratio name
-- where it is about a share of energy.

insert into public.clinical_rules (
  source_id, source_version, publication_date, jurisdiction,
  condition, min_age_years, max_age_years, sex, life_stage,
  recommendation_type, variable, comparator, value_low, value_high, unit,
  compact_recommendation, strength_of_recommendation, certainty_or_evidence_grade,
  source_locator, licensing_class, curator_id, is_active
)
select
  v.source_id, v.source_version, v.publication_date::date, v.jurisdiction,
  v.condition, v.min_age, v.max_age, v.sex, v.life_stage,
  v.rec_type, v.variable, v.comparator, v.value_low, v.value_high, v.unit,
  v.compact, v.strength, v.grade,
  v.locator::jsonb, 'public_domain', 'qamar:0056', true
from (values
  -- Dietary Guidelines for Americans 2020-2025 ------------------------
  ('dga_2020', '2020-2025', '2020-12-29', 'US',
   'general_wellness', 19::numeric, null::numeric, 'any', 'adult',
   'limit', 'sodium_mg', '<', null::numeric, 2300::numeric, 'mg/day',
   'Keep sodium under 2,300 mg a day — about a level teaspoon of salt in total, including what is already in bread, cheese and processed food.',
   'key recommendation', null,
   '{"url":"https://www.dietaryguidelines.gov/","section":"Chapter 1: Nutrition and Health Across the Lifespan","table":"Dietary Guidelines quantitative limits"}'),

  ('dga_2020', '2020-2025', '2020-12-29', 'US',
   'general_wellness', 19::numeric, null::numeric, 'any', 'adult',
   'limit', 'added_sugars_pct_energy', '<', null::numeric, 10::numeric, '%E',
   'Keep added sugars under 10% of the day''s calories. On a 2,000 kcal day that is under 200 kcal, roughly 50 g.',
   'key recommendation', null,
   '{"url":"https://www.dietaryguidelines.gov/","section":"Chapter 1: Nutrition and Health Across the Lifespan","table":"Dietary Guidelines quantitative limits"}'),

  ('dga_2020', '2020-2025', '2020-12-29', 'US',
   'general_wellness', 19::numeric, null::numeric, 'any', 'adult',
   'limit', 'sat_fat_pct_energy', '<', null::numeric, 10::numeric, '%E',
   'Keep saturated fat under 10% of the day''s calories, replacing it with unsaturated oils rather than with refined starch.',
   'key recommendation', null,
   '{"url":"https://www.dietaryguidelines.gov/","section":"Chapter 1: Nutrition and Health Across the Lifespan","table":"Dietary Guidelines quantitative limits"}'),

  ('dga_2020', '2020-2025', '2020-12-29', 'US',
   'general_wellness', 19::numeric, null::numeric, 'any', 'adult',
   'target', 'fiber_g', '>=', 14::numeric, null::numeric, 'g per 1000 kcal',
   'Aim for about 14 g of fibre for every 1,000 calories — on a 2,000 kcal day, about 28 g.',
   'adequate intake', null,
   '{"url":"https://www.dietaryguidelines.gov/","section":"Appendix: Nutritional Goals for Age-Sex Groups","note":"Adequate Intake, 14 g per 1,000 kcal"}'),

  -- Physical Activity Guidelines for Americans, 2nd edition ------------
  ('hhs_pag_2018', '2nd edition', '2018-11-12', 'US',
   'general_wellness', 19::numeric, null::numeric, 'any', 'adult',
   'target', 'moderate_aerobic_minutes_per_week', 'between', 150::numeric, 300::numeric, 'min/week',
   'Aim for 150 to 300 minutes a week of moderate activity — a brisk walk counts, and it can be split into any blocks that fit the week.',
   'strongly recommended', 'strong',
   '{"url":"https://health.gov/our-work/nutrition-physical-activity/physical-activity-guidelines","section":"Key Guidelines for Adults"}'),

  ('hhs_pag_2018', '2nd edition', '2018-11-12', 'US',
   'general_wellness', 19::numeric, null::numeric, 'any', 'adult',
   'target', 'muscle_strengthening_days_per_week', '>=', 2::numeric, null::numeric, 'days/week',
   'Work the major muscle groups on two days a week or more, alongside the walking.',
   'strongly recommended', 'strong',
   '{"url":"https://health.gov/our-work/nutrition-physical-activity/physical-activity-guidelines","section":"Key Guidelines for Adults"}'),

  ('hhs_pag_2018', '2nd edition', '2018-11-12', 'US',
   'general_wellness', 19::numeric, null::numeric, 'any', 'adult',
   'prefer', 'sedentary_time', 'n/a', null::numeric, null::numeric, null,
   'Sit less. Some activity is better than none, and moving even a little counts towards the week.',
   'strongly recommended', 'moderate',
   '{"url":"https://health.gov/our-work/nutrition-physical-activity/physical-activity-guidelines","section":"Key Guidelines for Adults"}'),

  -- NIH Office of Dietary Supplements fact sheets ----------------------
  ('nih_ods', 'ODS fact sheet', null, 'US',
   'general_wellness', 19::numeric, 70::numeric, 'any', 'adult',
   'target', 'vitamin_d_ug', '>=', 15::numeric, null::numeric, 'µg/day',
   'Adults need about 15 µg (600 IU) of vitamin D a day.',
   'RDA', null,
   '{"url":"https://ods.od.nih.gov/factsheets/VitaminD-HealthProfessional/","section":"Recommended Intakes","table":"RDA, adults 19-70 y"}'),

  ('nih_ods', 'ODS fact sheet', null, 'US',
   'general_wellness', 19::numeric, 50::numeric, 'any', 'adult',
   'target', 'calcium_mg', '>=', 1000::numeric, null::numeric, 'mg/day',
   'Adults up to 50 need about 1,000 mg of calcium a day — roughly three servings of dairy, or the equivalent in sesame, greens and fortified foods.',
   'RDA', null,
   '{"url":"https://ods.od.nih.gov/factsheets/Calcium-HealthProfessional/","section":"Recommended Intakes","table":"RDA, adults 19-50 y"}'),

  ('nih_ods', 'ODS fact sheet', null, 'US',
   'general_wellness', 19::numeric, 50::numeric, 'female', 'adult',
   'target', 'iron_mg', '>=', 18::numeric, null::numeric, 'mg/day',
   'Women under 51 need about 18 mg of iron a day — more than men, because of menstrual losses. Vitamin C at the same meal helps absorb the iron in beans and greens.',
   'RDA', null,
   '{"url":"https://ods.od.nih.gov/factsheets/Iron-HealthProfessional/","section":"Recommended Intakes","table":"RDA, women 19-50 y"}'),

  ('nih_ods', 'ODS fact sheet', null, 'US',
   'general_wellness', 19::numeric, null::numeric, 'male', 'adult',
   'target', 'iron_mg', '>=', 8::numeric, null::numeric, 'mg/day',
   'Men need about 8 mg of iron a day.',
   'RDA', null,
   '{"url":"https://ods.od.nih.gov/factsheets/Iron-HealthProfessional/","section":"Recommended Intakes","table":"RDA, men 19+ y"}'),

  ('nih_ods', 'ODS fact sheet', null, 'US',
   'general_wellness', 19::numeric, null::numeric, 'any', 'adult',
   'target', 'vitamin_b12_ug', '>=', 2.4::numeric, null::numeric, 'µg/day',
   'Adults need about 2.4 µg of vitamin B12 a day. It comes from animal foods, so a diet without them needs a fortified food or a supplement.',
   'RDA', null,
   '{"url":"https://ods.od.nih.gov/factsheets/VitaminB12-HealthProfessional/","section":"Recommended Intakes","table":"RDA, adults"}'),

  ('nih_ods', 'ODS fact sheet', null, 'US',
   'general_wellness', 19::numeric, null::numeric, 'any', 'adult',
   'target', 'folate_ug', '>=', 400::numeric, null::numeric, 'µg DFE/day',
   'Adults need about 400 µg DFE of folate a day — pulses, liver and leafy greens are the usual sources.',
   'RDA', null,
   '{"url":"https://ods.od.nih.gov/factsheets/Folate-HealthProfessional/","section":"Recommended Intakes","table":"RDA, adults"}'),

  ('nih_ods', 'ODS fact sheet', null, 'US',
   'general_wellness', 19::numeric, null::numeric, 'any', 'adult',
   'target', 'vitamin_c_mg', '>=', 75::numeric, null::numeric, 'mg/day',
   'Adults need about 75 to 90 mg of vitamin C a day — 90 for men, 75 for women; one guava or two oranges covers it.',
   'RDA', null,
   '{"url":"https://ods.od.nih.gov/factsheets/VitaminC-HealthProfessional/","section":"Recommended Intakes","table":"RDA, adults"}'),

  ('nih_ods', 'ODS fact sheet', null, 'US',
   'general_wellness', 19::numeric, null::numeric, 'any', 'adult',
   'target', 'zinc_mg', '>=', 8::numeric, null::numeric, 'mg/day',
   'Adults need about 8 to 11 mg of zinc a day — 11 for men, 8 for women.',
   'RDA', null,
   '{"url":"https://ods.od.nih.gov/factsheets/Zinc-HealthProfessional/","section":"Recommended Intakes","table":"RDA, adults"}'),

  ('nih_ods', 'ODS fact sheet', null, 'US',
   'general_wellness', 19::numeric, null::numeric, 'any', 'adult',
   'target', 'magnesium_mg', '>=', 310::numeric, null::numeric, 'mg/day',
   'Adults need roughly 310 to 420 mg of magnesium a day, depending on age and sex. Wholegrains, pulses and nuts carry most of it.',
   'RDA', null,
   '{"url":"https://ods.od.nih.gov/factsheets/Magnesium-HealthProfessional/","section":"Recommended Intakes","table":"RDA, adults"}'),

  ('nih_ods', 'ODS fact sheet', null, 'US',
   'general_wellness', 19::numeric, null::numeric, 'any', 'adult',
   'target', 'potassium_mg', '>=', 2600::numeric, null::numeric, 'mg/day',
   'Adults need roughly 2,600 to 3,400 mg of potassium a day — 3,400 for men, 2,600 for women. Potatoes, pulses, dates and leafy greens are the everyday sources.',
   'adequate intake', null,
   '{"url":"https://ods.od.nih.gov/factsheets/Potassium-HealthProfessional/","section":"Recommended Intakes","table":"AI, adults"}')
) as v(source_id, source_version, publication_date, jurisdiction,
       condition, min_age, max_age, sex, life_stage,
       rec_type, variable, comparator, value_low, value_high, unit,
       compact, strength, grade, locator)
where not exists (
  select 1 from public.clinical_rules r
  where r.source_id = v.source_id
    and r.variable is not distinct from v.variable
    and r.sex = v.sex
    and r.min_age_years is not distinct from v.min_age
);

-- ---------------------------------------------------------------------
-- 3. What is still outstanding
-- ---------------------------------------------------------------------
--
-- A rule reaches the reasoner on `is_active` and its source's rights alone —
-- there is no review gate in qamar_rule_selection, by design, because an
-- unreviewed rule is still better than silence. That makes it the operator's
-- job to know which rows nobody has checked. This view is that list.

create or replace view public.clinical_rule_review as
select
  r.rule_id,
  r.source_id,
  r.source_version,
  r.variable,
  r.compact_recommendation,
  r.is_active,
  r.curator_id,
  r.reviewer_id is null as needs_review,
  r.last_verified,
  s.status as source_status,
  public.qamar_source_usable_for_advice(r.source_id) as source_usable
from public.clinical_rules r
left join public.source_registry s on s.source_id = r.source_id;

alter view public.clinical_rule_review set (security_invoker = true);

comment on view public.clinical_rule_review is
  'Every clinical rule with the two things an operator needs to see: whether a '
  'professional has reviewed it (reviewer_id), and whether its source is '
  'currently allowed to inform advice at all. Rows seeded by 0056 are all '
  'needs_review = true until someone signs them off.';
