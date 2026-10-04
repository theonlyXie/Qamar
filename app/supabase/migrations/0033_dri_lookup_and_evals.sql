-- The DRI lookup, separated from the profile, and frozen into the eval set.
--
-- 0032 could only be tested through qamar_micronutrient_targets, which needs a
-- profile row, which means a user, which means the test either fabricates one or
-- depends on whoever happens to be in the database. Neither belongs in a
-- regression suite that is supposed to say the same thing next year.
--
-- So the selection rule comes out into a function that takes a sex and an age
-- and nothing else. qamar_micronutrient_targets keeps its signature and becomes
-- the thin part: read the profile, work out the age, ask this.

create or replace function public.qamar_dri_lookup(
  p_sex text,
  p_age_years numeric,
  p_life_stage text default 'adult'
)
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
language sql
stable
set search_path = public
as $$
  -- distinct on picks one row per nutrient; the order by below is the whole
  -- selection rule, and it is a total order so the answer cannot depend on the
  -- physical order of the table.
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
  where p_age_years is not null
    and d.min_age_years <= p_age_years
    and (d.max_age_years is null or p_age_years <= d.max_age_years)
    and (d.sex = 'any' or d.sex = p_sex)
    and d.kind in ('RDA','AI')
    and d.life_stage = coalesce(p_life_stage, 'adult')
  order by d.nutrient_code,
           (d.sex <> 'any') desc,  -- a sex-specific row is the better match
           (d.kind = 'RDA') desc,  -- an RDA is a stronger statement than an AI
           d.min_age_years desc,   -- the narrowest band that still contains them
           d.source_edition;       -- last resort, so the order is total
$$;

comment on function public.qamar_dri_lookup is
  'The DRI row that applies to a sex and an age, one per nutrient. Knows nothing '
  'about users, which is what makes it testable. Returns nothing for an age no '
  'seeded band contains — currently anything outside 19-50.';

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
language sql
stable
set search_path = public
as $$
  select l.*
  from public.profiles p
  cross join lateral public.qamar_dri_lookup(
    p.gender,
    case when p.birth_date is null then null
         else extract(year from age(current_date, p.birth_date)) end,
    case when p.life_stage in ('pregnancy','lactation') then p.life_stage
         else 'adult' end
  ) l
  where p.user_id = p_user_id;
$$;

comment on function public.qamar_micronutrient_targets is
  'The DRI row that applies to one person, per nutrient. Returns nothing when '
  'the profile has no birth date, and nothing for a nutrient whose seeded age '
  'bands do not contain them — 19-50 is all that is loaded, so a 60-year-old '
  'gets an empty set rather than a wrong number.';

revoke all on function public.qamar_dri_lookup(text, numeric, text) from public, anon;
grant execute on function public.qamar_dri_lookup(text, numeric, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------
-- The runner
-- ---------------------------------------------------------------------

-- One more kind for qamar_run_eval. Everything else in that function is
-- unchanged; this rewrites it to add a branch, because a plpgsql body cannot be
-- patched in place.
create or replace function public.qamar_eval_dri(
  p_input jsonb,
  p_expected jsonb,
  out ok boolean,
  out detail text
)
language plpgsql
stable
set search_path = public
as $$
declare
  r record;
begin
  ok := false;

  select * into r
  from public.qamar_dri_lookup(
    p_input->>'sex',
    (p_input->>'age_years')::numeric,
    coalesce(p_input->>'life_stage', 'adult'))
  where nutrient_code = p_input->>'nutrient_code';

  if coalesce((p_expected->>'resolves')::boolean, true) = false then
    ok := not found;
    if not ok then
      detail := 'expected no applicable value, got ' || r.target || ' ' || r.unit;
    end if;
    return;
  end if;

  if not found then
    detail := 'expected ' || (p_expected->>'target') || ', got no applicable row';
    return;
  end if;

  if r.target <> (p_expected->>'target')::numeric then
    detail := 'expected ' || (p_expected->>'target') || ' ' || r.unit
              || ', got ' || r.target;
    return;
  end if;

  -- The value being right is not enough. RDA and AI carry different weight, and
  -- a report that calls an AI shortfall a deficiency is wrong even when the
  -- arithmetic is not.
  if p_expected ? 'kind' and r.kind <> (p_expected->>'kind') then
    detail := 'right number, wrong kind: got ' || r.kind
              || ', expected ' || (p_expected->>'kind');
    return;
  end if;

  ok := true;
end;
$$;

comment on function public.qamar_eval_dri is
  'Eval runner for kind = dri_target. Separate from qamar_run_eval so adding a '
  'case family does not mean rewriting the dispatcher every time.';

revoke all on function public.qamar_eval_dri(jsonb, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- The cases
-- ---------------------------------------------------------------------
--
-- These are the claims the reference table is making. If a later edition moves
-- a value, one of these fails and somebody reads the source before the app
-- starts telling a woman she needs 8 mg of iron.

insert into public.eval_cases (family, slug, description, input, expected)
values
  ('guideline_applicability', 'dri-iron-female-adult',
   'A woman of reproductive age needs more than twice the male iron target.',
   '{"runner":"sql","kind":"dri_target","nutrient_code":"iron_mg","sex":"female","age_years":25}',
   '{"target":18,"kind":"RDA"}'),
  ('guideline_applicability', 'dri-iron-male-adult',
   'The male iron RDA, which is the value a sex-blind app would wrongly give everyone.',
   '{"runner":"sql","kind":"dri_target","nutrient_code":"iron_mg","sex":"male","age_years":25}',
   '{"target":8,"kind":"RDA"}'),
  ('guideline_applicability', 'dri-magnesium-female-young',
   'Magnesium is the one adult nutrient with two bands inside 19-50; this is the lower one.',
   '{"runner":"sql","kind":"dri_target","nutrient_code":"magnesium_mg","sex":"female","age_years":25}',
   '{"target":310,"kind":"RDA"}'),
  ('guideline_applicability', 'dri-magnesium-female-older',
   'The same woman at 40 needs 320, and picking the wrong band is a silent error.',
   '{"runner":"sql","kind":"dri_target","nutrient_code":"magnesium_mg","sex":"female","age_years":40}',
   '{"target":320,"kind":"RDA"}'),
  ('guideline_applicability', 'dri-magnesium-male-older',
   'And the male 31-50 band.',
   '{"runner":"sql","kind":"dri_target","nutrient_code":"magnesium_mg","sex":"male","age_years":40}',
   '{"target":420,"kind":"RDA"}'),
  ('guideline_applicability', 'dri-magnesium-band-boundary',
   'Exactly 31 belongs to the upper band, not the lower one.',
   '{"runner":"sql","kind":"dri_target","nutrient_code":"magnesium_mg","sex":"male","age_years":31}',
   '{"target":420,"kind":"RDA"}'),
  ('guideline_applicability', 'dri-potassium-is-an-ai',
   'Potassium has an AI and not an RDA, and the difference changes what a shortfall means.',
   '{"runner":"sql","kind":"dri_target","nutrient_code":"potassium_mg","sex":"male","age_years":30}',
   '{"target":3400,"kind":"AI"}'),
  ('guideline_applicability', 'dri-sodium-is-an-ai',
   'Sodium likewise, and it is a floor rather than a goal.',
   '{"runner":"sql","kind":"dri_target","nutrient_code":"sodium_mg","sex":"female","age_years":30}',
   '{"target":1500,"kind":"AI"}'),
  ('guideline_applicability', 'dri-b12-sex-neutral',
   'A sex-neutral row applies to both, without a sex-specific row existing to shadow it.',
   '{"runner":"sql","kind":"dri_target","nutrient_code":"vitamin_b12_ug","sex":"female","age_years":30}',
   '{"target":2.4,"kind":"RDA"}'),
  ('guideline_applicability', 'dri-niacin-female',
   'Niacin, one of the four B vitamins added with the micronutrient phase.',
   '{"runner":"sql","kind":"dri_target","nutrient_code":"niacin_mg","sex":"female","age_years":30}',
   '{"target":14,"kind":"RDA"}'),
  ('guideline_applicability', 'dri-refuses-past-the-seeded-band',
   'Iron falls to 8 mg for a woman after menopause and that band is not seeded, so the answer must be nothing rather than 18.',
   '{"runner":"sql","kind":"dri_target","nutrient_code":"iron_mg","sex":"female","age_years":60}',
   '{"resolves":false}'),
  ('guideline_applicability', 'dri-refuses-under-19',
   'Adolescent values differ and are not seeded either.',
   '{"runner":"sql","kind":"dri_target","nutrient_code":"calcium_mg","sex":"male","age_years":16}',
   '{"resolves":false}'),
  ('guideline_applicability', 'dri-refuses-pregnancy',
   'Pregnancy raises iron to 27 and folate to 600. Until those are seeded, a pregnant user must get no target rather than the non-pregnant one.',
   '{"runner":"sql","kind":"dri_target","nutrient_code":"iron_mg","sex":"female","age_years":30,"life_stage":"pregnancy"}',
   '{"resolves":false}')
on conflict (slug) do nothing;

-- ---------------------------------------------------------------------
-- The dispatcher
-- ---------------------------------------------------------------------
--
-- Redeclared in full rather than patched, for the same reason 0027 gave: a
-- migration is a record of what was applied, and an ALTER that only makes sense
-- against the previous file's text is not one. The only change from 0027 is the
-- dri_target branch.

create or replace function public.qamar_run_eval(
  p_label text default 'manual',
  p_trigger text default 'manual',
  p_family text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_run uuid;
  c record;
  actual jsonb;
  ok boolean;
  detail text;
  started timestamptz;
  n_pass int := 0;
  n_fail int := 0;
  v_food uuid;
  v_grams numeric;
  v_label text;
  v_matched boolean;
  v_distinct int;
  v_answer text;
  min_score numeric;
begin
  insert into public.eval_runs (label, trigger, food_data_version, clinical_content_version, notes)
  values (
    p_label, p_trigger,
    (select count(*) from public.foods) || ' foods, '
      || (select count(*) from public.food_nutrients) || ' nutrient rows',
    (select count(*) from public.clinical_rules) || ' clinical rules',
    'SQL-runnable families only; scope and verifier cases run from eval.ts')
  returning id into v_run;

  for c in
    select * from public.eval_cases
     where input->>'runner' = 'sql'
       and (p_family is null or family = p_family)
     order by family, slug
  loop
    started := clock_timestamp();
    ok := false;
    detail := null;
    actual := null;
    min_score := coalesce((c.tolerance->>'min_score')::numeric, 0.35);

    begin
      if c.input->>'kind' = 'resolve_food' then
        select to_jsonb(t) into actual from (
          select r.qamar_food_id, r.slug, r.match_score, r.match_kind, r.is_recipe
          from public.qamar_resolve_food(c.input->>'phrase', 3) r
          limit 1
        ) t;

        if coalesce((c.expected->>'resolves')::boolean, true) = false then
          ok := actual is null or (actual->>'match_score')::numeric < 0.35;
          if not ok then
            detail := 'expected no usable match, got ' || (actual->>'slug')
                      || ' at ' || (actual->>'match_score');
          end if;
        elsif actual is null then
          detail := 'expected ' || (c.expected->>'slug') || ', resolved nothing';
        else
          ok := actual->>'slug' = c.expected->>'slug'
                and (actual->>'match_score')::numeric >= min_score;
          if not ok then
            detail := 'expected ' || (c.expected->>'slug') || ' at >= ' || min_score
                      || ', got ' || (actual->>'slug') || ' at ' || (actual->>'match_score');
          end if;

          if ok and c.expected ? 'is_recipe'
             and (actual->>'is_recipe')::boolean <> (c.expected->>'is_recipe')::boolean then
            ok := false;
            detail := 'resolved to the right food but is_recipe = ' || (actual->>'is_recipe');
          end if;

          if ok and c.expected ? 'portion_matched' then
            v_food := (actual->>'qamar_food_id')::uuid;
            v_grams := null; v_label := null; v_matched := null;
            select p.grams, p.label_en, p.matched_in_phrase
              into v_grams, v_label, v_matched
            from public.qamar_resolve_portion(v_food, c.input->>'phrase') p limit 1;

            actual := actual || jsonb_build_object(
              'portion_label', v_label, 'portion_g', v_grams, 'portion_matched', v_matched);

            if v_grams is null then
              ok := false;
              detail := 'no portion resolved at all';
            elsif coalesce(v_matched, false) <> (c.expected->>'portion_matched')::boolean then
              ok := false;
              detail := 'portion matched_in_phrase = ' || coalesce(v_matched::text, 'null')
                        || ', expected ' || (c.expected->>'portion_matched');
            end if;
          end if;
        end if;

      elsif c.input->>'kind' = 'resolve_food_stable' then
        select s.distinct_answers, s.answer into v_distinct, v_answer
        from public.qamar_eval_stable_slug(
          c.input->>'phrase', coalesce((c.input->>'repeats')::int, 5)) s;
        actual := jsonb_build_object('distinct_answers', v_distinct, 'answer', v_answer);
        ok := v_distinct = 1;
        if not ok then
          detail := 'the same phrase resolved ' || v_distinct || ' different ways';
        end if;

      elsif c.input->>'kind' = 'rmr' then
        select to_jsonb(t) into actual from (
          select r.rmr_kcal, r.equation, r.assumptions
          from public.qamar_estimate_rmr(
            (c.input->>'weight_kg')::numeric,
            (c.input->>'height_cm')::numeric,
            (c.input->>'age_years')::numeric,
            c.input->>'sex',
            (c.input->>'body_fat_pct')::numeric) r
        ) t;

        if coalesce((c.expected->>'resolves')::boolean, true) = false then
          ok := actual is null or actual->>'rmr_kcal' is null;
          if not ok then
            detail := 'expected no equation to apply, got ' || (actual->>'rmr_kcal') || ' kcal';
          end if;
        elsif actual is null or actual->>'rmr_kcal' is null then
          detail := 'expected ' || (c.expected->>'rmr_kcal') || ' kcal, got nothing';
        else
          ok := abs((actual->>'rmr_kcal')::numeric - (c.expected->>'rmr_kcal')::numeric)
                <= coalesce((c.tolerance->>'kcal')::numeric, 1);
          if not ok then
            detail := 'expected ' || (c.expected->>'rmr_kcal')
                      || ' kcal, got ' || (actual->>'rmr_kcal');
          elsif c.expected ? 'equation' and actual->>'equation' <> c.expected->>'equation' then
            ok := false;
            detail := 'right number from the wrong equation: ' || (actual->>'equation');
          end if;
        end if;

      elsif c.input->>'kind' = 'dri_target' then
        select r.eval_ok, r.eval_detail into ok, detail
        from (
          select e.ok as eval_ok, e.detail as eval_detail
          from public.qamar_eval_dri(c.input, c.expected) e
        ) r;
        actual := jsonb_build_object('detail', detail);

      else
        detail := 'no SQL runner for kind ' || coalesce(c.input->>'kind', '(none)');
      end if;

    exception when others then
      ok := false;
      detail := 'error: ' || sqlerrm;
    end;

    insert into public.eval_results
      (run_id, case_id, passed, actual, failure_detail, latency_ms)
    values (
      v_run, c.id, ok, actual, detail,
      round(extract(epoch from (clock_timestamp() - started)) * 1000)::int);

    if ok then n_pass := n_pass + 1; else n_fail := n_fail + 1; end if;
  end loop;

  update public.eval_runs
     set finished_at = now(), passed = n_pass, failed = n_fail
   where id = v_run;

  return v_run;
end;
$fn$;
revoke all on function public.qamar_run_eval(text, text, text) from public, anon, authenticated;
grant execute on function public.qamar_run_eval(text, text, text) to service_role;
