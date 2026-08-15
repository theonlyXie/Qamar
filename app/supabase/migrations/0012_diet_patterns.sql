-- Diet pattern ontology.
--
-- A diet is "a set of rules, evidence claims, nutrient risks, use cases and
-- adherence requirements", not a label in a prompt. The reason this is a table
-- is the requirement that the reasoner record *why an alternative was not
-- chosen* — which needs the alternatives to be rows — and the requirement that
-- it must not choose keto or Mediterranean merely because the user named it.
--
-- consumer_scope is the gate for the wellness tier settled on 2026-08-15.
-- Therapeutic ketogenic, low-FODMAP and renal patterns are recognised so Qamar
-- can talk about them accurately and refuse to prescribe them, which is a
-- different thing from pretending they do not exist.

create table if not exists public.diet_patterns (
  id uuid primary key default uuid_generate_v4(),
  slug text not null unique,
  name_en text not null,
  name_ar text,
  definition text not null,
  reasoning_requirements text not null,
  -- Explicit, because "low carb" without a threshold is not a definition.
  defining_threshold text,
  evidence_quality text not null check (evidence_quality in
    ('strong','moderate','limited','contested','insufficient')),
  nutrient_risks text[] not null default '{}',
  contraindications text[] not null default '{}',
  adherence_burden text check (adherence_burden is null or adherence_burden in ('low','moderate','high')),
  requires_clinician boolean not null default false,
  consumer_scope boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists diet_patterns_touch on public.diet_patterns;
create trigger diet_patterns_touch before update on public.diet_patterns
  for each row execute function public.qamar_touch_updated_at();

create table if not exists public.diet_pattern_rules (
  id uuid primary key default uuid_generate_v4(),
  pattern_id uuid not null references public.diet_patterns (id) on delete cascade,
  rule_id uuid not null references public.clinical_rules (rule_id) on delete cascade,
  relation text not null default 'supports' check (relation in ('supports','constrains','contraindicates')),
  unique (pattern_id, rule_id, relation)
);

-- What the user is actually on, and why. The reasoner writes the rationale and
-- the alternatives it rejected, per execution flow B.
create table if not exists public.user_diet_strategy (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  pattern_id uuid not null references public.diet_patterns (id),
  rationale_ar text,
  rationale_en text,
  alternatives_rejected jsonb not null default '[]',  -- [{pattern_slug, reason}]
  selected_at timestamptz not null default now(),
  ended_at timestamptz
);

create index if not exists user_diet_strategy_user_idx
  on public.user_diet_strategy (user_id, selected_at desc);

alter table public.diet_patterns enable row level security;
drop policy if exists diet_patterns_read on public.diet_patterns;
create policy diet_patterns_read on public.diet_patterns
  for select to authenticated using (true);

alter table public.diet_pattern_rules enable row level security;
drop policy if exists diet_pattern_rules_read on public.diet_pattern_rules;
create policy diet_pattern_rules_read on public.diet_pattern_rules
  for select to authenticated using (true);

alter table public.user_diet_strategy enable row level security;
drop policy if exists user_diet_strategy_select_own on public.user_diet_strategy;
create policy user_diet_strategy_select_own on public.user_diet_strategy
  for select using (auth.uid() = user_id);
drop policy if exists user_diet_strategy_insert_own on public.user_diet_strategy;
create policy user_diet_strategy_insert_own on public.user_diet_strategy
  for insert with check (auth.uid() = user_id);

insert into public.diet_patterns
  (slug, name_en, name_ar, definition, reasoning_requirements, defining_threshold,
   evidence_quality, nutrient_risks, contraindications, adherence_burden,
   requires_clinician, consumer_scope)
values
('omnivorous','Omnivorous / flexible','متنوع',
 'No categorical food-group exclusions by default.',
 'Use general healthy-pattern guidance; optimize diversity, adequacy and user preference.',
 null,'strong','{}','{}','low',false,true),

('mediterranean','Mediterranean-style','البحر المتوسط',
 'Plant-forward: vegetables, fruit, legumes, whole grains, nuts and seeds, olive oil, fish.',
 'High-priority evidence-supported template for cardiometabolic health. Localize to Egyptian foods rather than copying Western menus.',
 null,'strong','{}','{}','low',false,true),

('dash','DASH','داش',
 'Vegetables, fruits, whole grains, low-fat dairy, lean proteins, legumes and nuts, with a sodium target framework.',
 'Evidence-based hypertension-oriented pattern; a pattern module, not a single meal plan. Account for kidney disease and medications affecting potassium and sodium.',
 'sodium target per NHLBI framework','strong','{}',
 '{"kidney disease without clinician oversight","potassium-affecting medication"}','moderate',false,true),

('vegetarian','Vegetarian','نباتي',
 'Excludes meat and fish; may include dairy and eggs depending on variant.',
 'Monitor protein quality and quantity, iron, B12, zinc, omega-3, iodine, calcium and vitamin D depending on actual intake.',
 null,'strong','{"iron","vitamin_b12_ug","zinc_mg","iodine_ug","calcium_mg","vitamin_d_ug"}','{}','moderate',false,true),

('vegan','Vegan','نباتي صرف',
 'Excludes all animal-derived foods.',
 'Requires a deliberate B12 strategy. Use evidence and clinical sources, not ideology.',
 null,'moderate','{"vitamin_b12_ug","iron_mg","zinc_mg","iodine_ug","calcium_mg","vitamin_d_ug","omega_3"}','{}','high',false,true),

('pescatarian','Pescatarian','نباتي مع السمك',
 'Plant-forward with seafood, typically no other meat.',
 'Useful preference pattern. Mercury and species guidance belongs in the appropriate module.',
 null,'moderate','{}','{}','low',false,true),

('low_carb','Low-carbohydrate','قليل الكربوهيدرات',
 'Carbohydrate restriction on a continuum, not a single definition.',
 'Define the actual gram or percentage threshold, the indication, medication context and a fibre and micronutrient plan. Never infer the threshold from the name.',
 'must be stated explicitly per user; no default','moderate','{"fiber_g"}',
 '{"glucose-lowering medication without clinician oversight"}','moderate',false,true),

('ketogenic_consumer','Ketogenic (consumer)','كيتو',
 'Very-low-carbohydrate approach used for weight management.',
 'Separate from medical therapeutic ketogenic diets. Strong safety and medication gates for diabetes and other conditions.',
 'typically under 50 g carbohydrate per day','contested','{"fiber_g","micronutrient adequacy"}',
 '{"type 1 diabetes","glucose-lowering medication","pregnancy","lactation"}','high',false,false),

('ketogenic_therapeutic','Ketogenic (therapeutic)','كيتو علاجي',
 'Medically supervised ketogenic therapy for defined clinical indications.',
 'Clinician-controlled. Qamar does not prescribe or adjust it.',
 'clinically specified','moderate','{}','{"any use without clinician supervision"}','high',true,false),

('high_protein','High-protein','عالي البروتين',
 'Protein above general baseline for a defined goal or context.',
 'Set explicit grams per kilogram and a range. Screen renal and clinical context. Distribute across meals where useful.',
 'stated g/kg/day, above AMDR baseline','moderate','{}','{"chronic kidney disease"}','low',false,true),

('time_restricted','Intermittent fasting / time-restricted eating','صيام متقطع',
 'Changes the eating window and timing, not automatically food quality.',
 'Represent the timing protocol separately from the nutrient prescription. Contraindication and risk screen where appropriate. Ramadan is a cultural context, not this pattern.',
 'stated eating window','moderate','{}',
 '{"eating disorder history","glucose-lowering medication","pregnancy","lactation"}','moderate',false,true),

('gluten_free','Gluten-free','خالي من الجلوتين',
 'Excludes gluten-containing grains.',
 'Medical necessity differs from preference. Celiac disease requires contamination and nutrient-quality considerations.',
 null,'strong','{"fiber_g","iron_mg","folate_ug"}','{}','moderate',false,true),

('low_fodmap','Low FODMAP','فودماب منخفض',
 'Structured elimination and reintroduction approach used for IBS under appropriate guidance.',
 'Not a permanent broad restriction. Requires elimination, reintroduction and personalization phases, and licensed food data if implemented.',
 null,'moderate','{"fiber_g","calcium_mg"}','{"use without a reintroduction plan"}','high',true,false),

('renal_modified','Renal / disease-modified','كلوي',
 'Not one diet. Depends on stage, labs, treatment and condition.',
 'Activates a disease-specific guideline module and clinician escalation thresholds. Protein, potassium, phosphorus, sodium and fluid logic all depend on stage and labs.',
 null,'moderate','{}','{"any autonomous use"}','high',true,false),

('carnivore','Carnivore','لحوم فقط',
 'Animal-food-only or near-only variants; definitions vary.',
 'Qamar can recognise and discuss it, but must attach explicit evidence-quality and nutrient-risk metadata rather than treating every named diet as equally evidence-based.',
 null,'insufficient','{"fiber_g","vitamin_c_mg","folate_ug","calcium_mg"}','{}','high',false,false)

on conflict (slug) do nothing;
