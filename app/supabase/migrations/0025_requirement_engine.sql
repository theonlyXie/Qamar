-- The requirement engine.
--
-- `targets` has held kcal and macros since 0001 with `formula_version` defaulted
-- to the string 'calc v2.0', naming a formula whose coefficients existed
-- nowhere. Three rows are in that table and nothing in this repository can say
-- how any of them was derived. That is the gap 0010 was written to close and
-- then deliberately left open, because seeding coefficients from memory is how
-- unciteable numbers end up behind a provenance column.
--
-- This closes the half that can be closed honestly. The resting-metabolic-rate
-- equations are published, short, and checkable digit by digit — Mifflin-St
-- Jeor is four coefficients — so they are seeded with their citations and the
-- engine reads them from the table rather than embedding them in SQL. A
-- correction is an UPDATE.
--
-- The half that stays open: `dri_reference` is still empty, so micronutrient
-- targets are not computed here. The NASEM DRI tables are hundreds of values
-- across nutrient, sex, life stage and age band, and transcription risk scales
-- with the size of the table in a way it does not for a four-term equation. The
-- EER row from 0010 also keeps its null coefficients — this engine uses RMR
-- times a physical activity level instead, which is the standard consumer
-- approach and is recorded as such on every target it writes.
--
-- Everything here is a screening estimate for a healthy adult in the consumer
-- wellness tier. It refuses rather than guesses for pregnancy, lactation, and
-- anyone under 18, because those need equations this engine does not have.

-- ---------------------------------------------------------------------
-- Coefficients
-- ---------------------------------------------------------------------
-- One row per sex where the equation differs by sex, because the difference is
-- a coefficient rather than a separate equation, and 0010's unique key
-- (name, version, sex_or_life_stage) already models that.

insert into public.equation_versions
  (name, version, source_id, citation, population, min_age_years, sex_or_life_stage,
   coefficients, unit, is_default, notes)
values
  ('RMR','Mifflin-StJeor-1990','nasem_dri',
   'Mifflin MD, St Jeor ST et al. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr 1990;51(2):241-247.',
   'healthy adults', 18, 'male',
   '{"weight_kg": 10, "height_cm": 6.25, "age_years": -5, "constant": 5}',
   'kcal/day', true,
   'RMR = 10*kg + 6.25*cm - 5*years + 5. Default because it is the best validated predictive equation for adults without a body composition measurement.'),

  ('RMR','Mifflin-StJeor-1990','nasem_dri',
   'Mifflin MD, St Jeor ST et al. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr 1990;51(2):241-247.',
   'healthy adults', 18, 'female',
   '{"weight_kg": 10, "height_cm": 6.25, "age_years": -5, "constant": -161}',
   'kcal/day', false,
   'RMR = 10*kg + 6.25*cm - 5*years - 161. Differs from the male form only in the constant.'),

  ('RMR','Katch-McArdle','nasem_dri',
   'Katch-McArdle / Cunningham lean-mass equation, as given in McArdle, Katch & Katch, Exercise Physiology.',
   'adults with a body composition measurement', 18, 'any',
   '{"lean_mass_kg": 21.6, "constant": 370}',
   'kcal/day', false,
   'RMR = 370 + 21.6*LBM. Preferred when body fat is actually measured, because it needs no sex term: it is already reading the tissue the sex term stands in for. Never used from an estimated body fat.'),

  ('RMR','Harris-Benedict-Roza-1984','nasem_dri',
   'Roza AM, Shizgal HM. The Harris Benedict equation reevaluated. Am J Clin Nutr 1984;40(1):168-182.',
   'healthy adults', 18, 'male',
   '{"weight_kg": 13.397, "height_cm": 4.799, "age_years": -5.677, "constant": 88.362}',
   'kcal/day', false,
   'Kept for comparison and for anyone who wants the older number. Not the default: it tends to run high against Mifflin-St Jeor in modern populations.'),

  ('RMR','Harris-Benedict-Roza-1984','nasem_dri',
   'Roza AM, Shizgal HM. The Harris Benedict equation reevaluated. Am J Clin Nutr 1984;40(1):168-182.',
   'healthy adults', 18, 'female',
   '{"weight_kg": 9.247, "height_cm": 3.098, "age_years": -4.330, "constant": 447.593}',
   'kcal/day', false,
   'Female form of the revised Harris-Benedict.')
on conflict (name, version, sex_or_life_stage) do nothing;

-- The EER row stays uncoefficiented, and now says what is used instead rather
-- than only what is missing.
update public.equation_versions
   set notes = 'Coefficients still pending ingestion from the NASEM report. Until then the '
               'engine uses RMR (Mifflin-St Jeor, or Katch-McArdle when body fat is measured) '
               'multiplied by the physical activity level, and records that on every target '
               'it writes. This row is the specification, not the implementation.'
 where name = 'EER' and version = 'NASEM-2023';

-- ---------------------------------------------------------------------
-- Safety and policy constants
-- ---------------------------------------------------------------------
-- In one table rather than scattered through the function, because these are
-- the numbers somebody will want to argue about, and an argument you can settle
-- with an UPDATE is better than one that needs a migration.

create table if not exists public.requirement_policy (
  key text primary key,
  value numeric not null,
  unit text,
  rationale text not null
);

alter table public.requirement_policy enable row level security;

insert into public.requirement_policy (key, value, unit, rationale) values
  ('energy_per_kg_body_mass', 7700, 'kcal/kg',
   'Energy equivalent of a kilogram of body mass. Converts a target rate of change into a daily deficit.'),
  ('max_loss_rate_pct_per_week', 0.75, '%/week',
   'Sits inside the 0.5-1% of body weight per week that general guidance treats as sustainable. The one number to tune if the app feels too slow or too aggressive.'),
  ('max_gain_rate_pct_per_week', 0.25, '%/week',
   'Above this, the surplus is mostly fat. Lean tissue does not accrue faster because the plate is bigger.'),
  ('max_deficit_fraction_of_tdee', 0.20, 'fraction',
   'A second ceiling that binds for light people, where a percentage of body weight alone would still allow a large relative cut.'),
  ('max_surplus_fraction_of_tdee', 0.15, 'fraction', 'The gain-side equivalent.'),
  ('absolute_floor_kcal_male', 1500, 'kcal/day',
   'Consumer safety floor. Below this an ordinary diet cannot reliably meet micronutrient needs without supervision.'),
  ('absolute_floor_kcal_female', 1200, 'kcal/day', 'As above.'),
  ('protein_g_per_kg_lose', 1.8, 'g/kg/day',
   'Higher in a deficit, where the job of protein is to protect lean mass rather than to add it.'),
  ('protein_g_per_kg_maintain', 1.4, 'g/kg/day', 'Comfortably above the RDA, which is a floor for deficiency and not a target.'),
  ('protein_g_per_kg_gain', 1.8, 'g/kg/day', 'Training plus surplus.'),
  ('protein_min_pct_energy', 0.10, 'fraction', 'AMDR lower bound.'),
  ('protein_max_pct_energy', 0.35, 'fraction', 'AMDR upper bound. This is what actually stops protein running away at high body weight.'),
  ('fat_pct_energy', 0.28, 'fraction', 'Mid AMDR. Egyptian home cooking sits here comfortably.'),
  ('fat_min_pct_energy', 0.20, 'fraction', 'AMDR lower bound.'),
  ('fat_max_pct_energy', 0.35, 'fraction', 'AMDR upper bound.'),
  ('fat_min_g_per_kg', 0.6, 'g/kg/day', 'Floor for fat-soluble vitamin absorption, independent of the percentage band.')
on conflict (key) do nothing;

-- SECURITY DEFINER because requirement_policy has RLS on and no policy, and a
-- signed-in client computing their own target must still be able to read the
-- constants. They are policy, not anyone's data.
--
-- The raise is the important half. Left as a plain SELECT, a missing or
-- unreadable key returns NULL, and NULL propagates: the deficit, both floors,
-- the macro split and finally the target all become NULL while ok stays true.
-- A target of nulls still looks like an answer, which is worse than an error.
create or replace function public.qamar_policy(p_key text)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v numeric;
begin
  select value into v from public.requirement_policy where key = p_key;
  if v is null then
    raise exception 'requirement policy % is missing', p_key
      using errcode = 'internal_error';
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------
-- Resting metabolic rate
-- ---------------------------------------------------------------------

create or replace function public.qamar_estimate_rmr(
  p_weight_kg numeric,
  p_height_cm numeric,
  p_age_years numeric,
  p_sex text,
  p_body_fat_pct numeric default null
) returns table (
  rmr_kcal numeric,
  equation text,
  assumptions text[]
)
language plpgsql
stable
set search_path = public
as $$
declare
  c jsonb;
  notes text[] := '{}';
  lbm numeric;
begin
  if p_weight_kg is null then
    return;
  end if;

  -- Measured body composition beats a sex-and-height proxy for it, so when the
  -- body fat figure exists it is used and the sex term becomes unnecessary.
  if p_body_fat_pct is not null and p_body_fat_pct between 3 and 70 then
    select coefficients into c from public.equation_versions
      where name = 'RMR' and version = 'Katch-McArdle';
    lbm := p_weight_kg * (1 - p_body_fat_pct / 100.0);
    return query select
      round((c->>'constant')::numeric + (c->>'lean_mass_kg')::numeric * lbm, 0),
      'Katch-McArdle'::text,
      array['lean mass ' || round(lbm, 1) || ' kg from a measured body fat of ' || p_body_fat_pct || '%'];
    return;
  end if;

  if p_height_cm is null or p_age_years is null then
    return;
  end if;

  -- Matched on the recorded sex, which finds nothing when it is not recorded.
  -- Defaulting to one of them here would silently pick a side.
  select coefficients into c from public.equation_versions
    where name = 'RMR' and version = 'Mifflin-StJeor-1990'
      and sex_or_life_stage = nullif(p_sex, '');

  if c is null then
    -- Sex unrecorded. The two Mifflin forms differ only in the constant, so the
    -- midpoint is the arithmetic centre of the two answers rather than a guess
    -- at which one applies — and it is flagged, because the spread is 166 kcal
    -- and that is not nothing.
    select coefficients into c from public.equation_versions
      where name = 'RMR' and version = 'Mifflin-StJeor-1990' and sex_or_life_stage = 'male';
    c := jsonb_set(c, '{constant}', to_jsonb(-78::numeric));
    -- Cast is load-bearing: an untyped literal on the right of || against a
    -- text[] is read as an array literal, not as one element.
    notes := notes || 'sex not recorded; midpoint of the male and female constants used (+/-83 kcal)'::text;
  end if;

  return query select
    round(
      (c->>'weight_kg')::numeric * p_weight_kg
    + (c->>'height_cm')::numeric * p_height_cm
    + (c->>'age_years')::numeric * p_age_years
    + (c->>'constant')::numeric, 0),
    'Mifflin-St Jeor'::text,
    notes;
end;
$$;

comment on function public.qamar_estimate_rmr is
  'Resting metabolic rate, from coefficients held in equation_versions rather '
  'than written into this function. Returns no row when the inputs cannot '
  'support any equation — never a default number.';

-- ---------------------------------------------------------------------
-- The whole requirement, for one person
-- ---------------------------------------------------------------------

create or replace function public.qamar_compute_targets(p_user_id uuid)
returns table (
  ok boolean,
  blocked_reason text,
  rmr_kcal int,
  tdee_kcal int,
  target_kcal int,
  protein_g int,
  carbs_g int,
  fat_g int,
  equation text,
  adjustment_kcal int,
  floor_applied text,
  assumptions text[],
  inputs jsonb
)
language plpgsql
stable
set search_path = public
as $$
declare
  p record;
  age numeric;
  v_rmr numeric;
  v_equation text;
  v_assumptions text[];
  pal numeric;
  tdee numeric;
  adjust numeric := 0;
  target numeric;
  floor_kcal numeric;
  floor_note text := null;
  notes text[] := '{}';
  g_per_kg numeric;
  protein numeric;
  fat numeric;
  carbs numeric;
begin
  select * into p from public.profiles where user_id = p_user_id;
  if not found then
    return query select false, 'no profile', null::int, null::int, null::int,
      null::int, null::int, null::int, null::text, null::int, null::text, '{}'::text[], '{}'::jsonb;
    return;
  end if;

  age := case when p.birth_date is null then null
              else extract(year from age(current_date, p.birth_date)) end;

  -- The refusals. Each one is a population this engine has no equation for, and
  -- producing a number anyway is the failure the whole provenance design exists
  -- to prevent.
  if p.life_stage is not null and p.life_stage <> 'none' then
    return query select false, 'life stage ' || p.life_stage || ' is out of scope for this engine',
      null::int, null::int, null::int, null::int, null::int, null::int,
      null::text, null::int, null::text, '{}'::text[], '{}'::jsonb;
    return;
  end if;
  if age is null or age < 18 then
    return query select false, coalesce('age ' || age || ' is under 18', 'birth date not recorded'),
      null::int, null::int, null::int, null::int, null::int, null::int,
      null::text, null::int, null::text, '{}'::text[], '{}'::jsonb;
    return;
  end if;
  if p.weight_kg is null or p.height_cm is null then
    return query select false, 'weight and height are both required',
      null::int, null::int, null::int, null::int, null::int, null::int,
      null::text, null::int, null::text, '{}'::text[], '{}'::jsonb;
    return;
  end if;

  -- Aliased because this function's own OUT parameters are called rmr_kcal,
  -- equation and assumptions too, and an unqualified reference is ambiguous
  -- between the two.
  select r.rmr_kcal, r.equation, r.assumptions
    into v_rmr, v_equation, v_assumptions
    from public.qamar_estimate_rmr(p.weight_kg, p.height_cm, age, p.gender, p.body_fat_pct) r;
  if v_rmr is null then
    return query select false, 'no equation applies to these inputs',
      null::int, null::int, null::int, null::int, null::int, null::int,
      null::text, null::int, null::text, '{}'::text[], '{}'::jsonb;
    return;
  end if;
  notes := notes || coalesce(v_assumptions, '{}');

  pal := coalesce(p.activity_factor, 1.4);
  if p.activity_factor is null then
    notes := notes || 'activity level not recorded; lightly active (1.4) assumed'::text;
  end if;
  tdee := v_rmr * pal;

  -- The adjustment is a rate, expressed as energy. Two ceilings apply and the
  -- smaller wins: a share of body weight per week, and a share of maintenance.
  -- The first binds for heavy people, the second for light ones.
  if p.goal = 'lose' then
    adjust := -least(
      p.weight_kg * qamar_policy('max_loss_rate_pct_per_week') / 100.0
        * qamar_policy('energy_per_kg_body_mass') / 7.0,
      tdee * qamar_policy('max_deficit_fraction_of_tdee'));
  elsif p.goal = 'gain' then
    adjust := least(
      p.weight_kg * qamar_policy('max_gain_rate_pct_per_week') / 100.0
        * qamar_policy('energy_per_kg_body_mass') / 7.0,
      tdee * qamar_policy('max_surplus_fraction_of_tdee'));
  end if;

  target := tdee + adjust;

  -- Two floors, and the higher one binds. Prescribing below resting metabolic
  -- rate is the line this must not cross whatever the goal says, and the
  -- absolute floor catches the small-and-sedentary case where RMR alone would
  -- still allow an intake no ordinary diet meets micronutrient needs at.
  floor_kcal := greatest(
    v_rmr,
    case when p.gender = 'female' then qamar_policy('absolute_floor_kcal_female')
         else qamar_policy('absolute_floor_kcal_male') end);
  if target < floor_kcal then
    floor_note := case when floor_kcal = v_rmr then 'resting metabolic rate'
                       else 'absolute consumer floor' end;
    notes := notes ||
      ('requested deficit reduced: target held at the ' || floor_note ||
       ' of ' || round(floor_kcal) || ' kcal');
    target := floor_kcal;
    adjust := target - tdee;
  end if;

  -- Macros. Protein is set per kilogram and then bounded by the AMDR, which is
  -- what stops it running away at high body weight — total weight is used
  -- rather than lean mass, and that band is the correction for it.
  g_per_kg := case p.goal
    when 'lose' then qamar_policy('protein_g_per_kg_lose')
    when 'gain' then qamar_policy('protein_g_per_kg_gain')
    else qamar_policy('protein_g_per_kg_maintain') end;
  protein := p.weight_kg * g_per_kg;
  protein := least(protein, target * qamar_policy('protein_max_pct_energy') / 4.0);
  protein := greatest(protein, target * qamar_policy('protein_min_pct_energy') / 4.0);

  fat := target * qamar_policy('fat_pct_energy') / 9.0;
  fat := greatest(fat, p.weight_kg * qamar_policy('fat_min_g_per_kg'));
  fat := least(fat, target * qamar_policy('fat_max_pct_energy') / 9.0);
  fat := greatest(fat, target * qamar_policy('fat_min_pct_energy') / 9.0);

  carbs := (target - protein * 4 - fat * 9) / 4.0;
  if carbs < 0 then
    -- Only reachable if protein and fat floors collide with a very low target.
    -- Recorded rather than hidden, because it means the floors are fighting.
    notes := notes || 'protein and fat floors exceed the energy target; carbohydrate set to zero'::text;
    carbs := 0;
  end if;

  return query select
    true,
    null::text,
    v_rmr::int,
    round(tdee)::int,
    round(target)::int,
    round(protein)::int,
    round(carbs)::int,
    round(fat)::int,
    v_equation || ' x PAL ' || pal,
    round(adjust)::int,
    floor_note,
    notes,
    jsonb_build_object(
      'weight_kg', p.weight_kg, 'height_cm', p.height_cm, 'age_years', age,
      'gender', p.gender, 'body_fat_pct', p.body_fat_pct,
      'activity_factor', pal, 'goal', coalesce(p.goal, 'maintain'),
      'life_stage', p.life_stage,
      'rmr_kcal', v_rmr, 'tdee_kcal', round(tdee),
      'equation', v_equation,
      'policy_version', '0025');
end;
$$;

comment on function public.qamar_compute_targets is
  'Screening estimate for a healthy adult, not a prescription. Returns ok=false '
  'with a reason rather than a number whenever the person is outside the '
  'population these equations were derived on.';

-- ---------------------------------------------------------------------
-- Writing it down
-- ---------------------------------------------------------------------

-- The same guard the wallet has used since 0002, under a name that does not
-- claim to be about wallets. The server acts for anyone; a signed-in client
-- acts only for itself.
create or replace function public.qamar_assert_self(p_user_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.role() = 'service_role' then
    return;
  end if;
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'not your account' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.qamar_set_target(p_user_id uuid)
returns public.targets
language plpgsql
security definer
set search_path = public
as $$
declare
  t record;
  v_row public.targets;
begin
  perform public.qamar_assert_self(p_user_id);

  select * into t from public.qamar_compute_targets(p_user_id);
  if not found or not t.ok then
    raise exception 'cannot set a target: %', coalesce(t.blocked_reason, 'no result');
  end if;

  -- The previous target is closed rather than replaced. A target is a decision
  -- made on a particular day from particular inputs, and overwriting it loses
  -- the answer to "what were they eating to in March".
  update public.targets
     set valid_to = now()
   where user_id = p_user_id and valid_to is null;

  insert into public.targets
    (user_id, kcal, protein_g, carbs_g, fat_g, formula_version, inputs)
  values (p_user_id, t.target_kcal, t.protein_g, t.carbs_g, t.fat_g,
          t.equation,
          t.inputs || jsonb_build_object(
            'adjustment_kcal', t.adjustment_kcal,
            'floor_applied', t.floor_applied,
            'assumptions', to_jsonb(t.assumptions)))
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.qamar_set_target(uuid) from public;
grant execute on function public.qamar_set_target(uuid) to authenticated, service_role;
revoke all on function public.qamar_assert_self(uuid) from public, anon, authenticated;

comment on function public.qamar_set_target is
  'Computes and stores a target, closing the previous one instead of '
  'overwriting it. formula_version stops being the string "calc v2.0" and '
  'starts naming the equation that produced the number.';
