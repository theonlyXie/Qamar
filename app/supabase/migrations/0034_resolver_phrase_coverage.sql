-- How much of what they typed the match actually accounts for.
--
-- The resolver scores an alias against the whole phrase with trigram
-- similarity, which rewards an alias that matches a *part* of it. That is fine
-- for noise words and catastrophic for the word that changes the food:
--
--   برجر لحم       -> beef            at 0.38   (a burger became raw mince)
--   فراخ بروستد    -> chicken_breast  at 0.42   (fried, breaded -> plain breast)
--   fried chicken  -> chicken_thigh   at 0.40
--   رز ابيض مسلوق  -> eggs            at 0.50   (found by this measurement)
--
-- None of those failed. They answered, confidently, with a different food at
-- roughly half the calories, on exactly the foods people under thirty actually
-- eat. 0029 had already written down the rule they violate — "a word the user
-- types that appears in no alias contributes nothing to the match, which is why
-- a modifier that changes the nutrition needs an alias of its own" — but
-- nothing measured it, so nothing could act on it.
--
-- phrase_coverage is that measurement: the fraction of the typed words that
-- carry nutritional weight and are accounted for by the winning alias.
--
-- Two refinements, each of which a frozen case forced:
--
--   بلطي مشوي   grilled tilapia — مشوي narrows the food without changing its
--                                 numbers, so it must not count against
--                                 coverage. Hence neutral_food_modifiers,
--                                 deliberately tiny: anything that changes the
--                                 cooking medium or the water content makes a
--                                 different food and belongs in an alias.
--   كبدة إسكندراني              — a hamza. The alias and the phrase are the same
--                                 words spelled differently, and a literal LIKE
--                                 cannot see that. Trigram similarity exists
--                                 for precisely this and coverage was not using
--                                 it; now a word counts as covered when some
--                                 word of the alias is spelled close enough.
--
-- Coverage is reported, never folded into the score. The two say different
-- things and a caller needs both: score is "how close is this name", coverage
-- is "how much of the question did I answer".

create table if not exists public.neutral_food_modifiers (
  token text primary key,
  note text
);

comment on table public.neutral_food_modifiers is
  'Words that narrow a food without changing its per-100g numbers, so they do '
  'not have to appear in an alias for a match to be complete. Deliberately '
  'short and hard to extend: anything that changes the cooking medium or the '
  'water content (fried, breaded, dried) belongs in an alias instead, because '
  'it makes a different food.';

insert into public.neutral_food_modifiers (token, note) values
  ('مشوي',    'grilled — no added fat, no water change worth modelling'),
  ('مشوية',   'grilled, feminine'),
  ('مشوى',    'grilled, alternative spelling'),
  ('grilled', null),
  ('سادة',    'plain, as opposed to sweetened or spiced'),
  ('plain',   null),
  ('طازة',    'fresh'),
  ('طازج',    'fresh'),
  ('fresh',   null)
on conflict (token) do nothing;

alter table public.neutral_food_modifiers enable row level security;
drop policy if exists neutral_modifiers_read on public.neutral_food_modifiers;
create policy neutral_modifiers_read on public.neutral_food_modifiers
  for select to authenticated using (true);

drop function if exists public.qamar_resolve_food(text, int);

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
  has_nutrients boolean,
  phrase_coverage real
)
language sql
stable
set search_path = public
as $$
  with norm as (
    select btrim(lower(regexp_replace(
      p_phrase, '[0-9٠-٩]+\s*(g|kg|ml|جم|جرام|كجم|مل|جرامات)?', ' ', 'gi'))) as q
  ),
  -- Words worth counting. One-character tokens are dropped — they are almost
  -- always Arabic prepositions or stray letters, and counting them would make
  -- coverage depend on punctuation — and so is anything the modifier table
  -- says carries no nutritional weight.
  tokens as (
    select btrim(t) as t
    from norm, unnest(string_to_array(norm.q, ' ')) as t
    where length(btrim(t)) > 1
      and not exists (
        select 1 from public.neutral_food_modifiers m where m.token = btrim(t))
  ),
  token_count as (select greatest(count(*), 1)::real as n from tokens),
  candidates as (
    select a.qamar_food_id,
           a.alias,
           a.priority,
           case when lower(a.alias) = (select q from norm) then 1.0::real
                else similarity(a.alias, (select q from norm)) end as score,
           case when lower(a.alias) = (select q from norm) then 'exact' else 'fuzzy' end as kind,
           -- A word is covered when the alias contains it, or when one of the
           -- alias's own words is spelled close enough — which is what makes
           -- this survive a hamza.
           (
             select count(*) from tokens tk
              where lower(a.alias) like '%' || tk.t || '%'
                 or exists (
                      select 1 from unnest(string_to_array(lower(a.alias), ' ')) w
                       where w = tk.t or similarity(w, tk.t) >= 0.5)
           )::real / (select n from token_count) as coverage
    from public.food_aliases a, norm
    where norm.q <> ''
      and (lower(a.alias) = norm.q or a.alias % norm.q)
  ),
  best as (
    select distinct on (c.qamar_food_id)
           c.qamar_food_id, c.alias, c.score, c.kind, c.priority, c.coverage
    from candidates c
    order by c.qamar_food_id, c.score desc, c.priority desc, c.alias
  )
  select f.qamar_food_id, f.slug, f.name_en, f.name_ar, f.name_eg, f.is_recipe,
         b.score, b.alias, b.kind,
         exists (select 1 from public.food_nutrients n where n.qamar_food_id = f.qamar_food_id)
           or f.is_recipe,
         least(b.coverage, 1.0)::real
  from best b
  join public.foods f on f.qamar_food_id = b.qamar_food_id
  order by b.score desc,
           b.priority desc,
           f.is_recipe desc,
           f.source_rank desc nulls last,
           f.slug
  limit greatest(p_limit, 1);
$$;

comment on function public.qamar_resolve_food is
  'Resolves a phrase to foods, best first. phrase_coverage is the fraction of '
  'the typed words that carry nutritional weight and are accounted for by the '
  'winning alias, tolerant of spelling. A high score with low coverage means a '
  'word that changes the food was ignored, which is how a burger becomes raw '
  'beef. Callers must read both.';

-- ---------------------------------------------------------------------
-- What "usable" means, in one place
-- ---------------------------------------------------------------------
--
-- The coverage floor applies to ingredients and not to dishes, and that is not
-- a fudge to make a test pass — it is the difference the failures themselves
-- showed. Every wrong answer above returned a raw ingredient while ignoring the
-- word that named a cooked thing. The one legitimate partial match, شاورما
-- فراخ, returned the right dish and merely did not know which protein.
--
-- Answering a dish with a generic version of that dish is incomplete.
-- Answering it with one of its raw ingredients is wrong.

create or replace function public.qamar_eval_usable(
  p_actual jsonb, p_min_score numeric, p_min_coverage numeric
) returns boolean
language sql immutable
set search_path = public
as $$
  select p_actual is not null
     and (p_actual->>'match_score')::numeric >= p_min_score
     and ((p_actual->>'phrase_coverage')::numeric >= p_min_coverage
          or coalesce((p_actual->>'is_recipe')::boolean, false));
$$;

comment on function public.qamar_eval_usable is
  'The gateway''s usability rule, in one place so the evals cannot drift from '
  'it. A dish may answer a phrase it only partly covers; a raw ingredient may '
  'not, because that is how برجر لحم became beef.';

revoke all on function public.qamar_eval_usable(jsonb, numeric, numeric) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- The cases
-- ---------------------------------------------------------------------

insert into public.eval_cases (family, slug, description, input, expected, tolerance)
values
  ('food_resolution','res_burger_is_not_beef',
   'برجر لحم resolved to raw beef at 0.38. A burger is not mince, and the calorie difference is about double.',
   '{"runner":"sql","kind":"resolve_food","phrase":"برجر لحم"}','{"resolves":false}','{}'),
  ('food_resolution','res_broasted_is_not_a_breast',
   'فراخ بروستد resolved to a plain chicken breast. Breaded and deep fried is a different food, not a preparation note.',
   '{"runner":"sql","kind":"resolve_food","phrase":"فراخ بروستد"}','{"resolves":false}','{}'),
  ('food_resolution','res_fried_chicken_is_not_a_thigh',
   'The English half of the same failure.',
   '{"runner":"sql","kind":"resolve_food","phrase":"fried chicken"}','{"resolves":false}','{}'),
  ('food_resolution','res_boiled_rice_is_not_eggs',
   'رز ابيض مسلوق resolved to eggs at 0.50. Found by the coverage measurement rather than by anyone noticing.',
   '{"runner":"sql","kind":"resolve_food","phrase":"رز ابيض مسلوق"}','{"resolves":false}','{}'),
  ('food_resolution','res_coverage_keeps_the_plain_names',
   'The floor must not cost the ordinary case: a bare name still covers all of itself.',
   '{"runner":"sql","kind":"resolve_food","phrase":"شاورما"}','{"slug":"shawarma"}','{"min_coverage":1.0}'),
  ('food_resolution','res_coverage_keeps_two_word_names',
   'And a two-word name whose alias is both of the words.',
   '{"runner":"sql","kind":"resolve_food","phrase":"عيش بلدي"}','{"slug":"baladi_bread"}','{"min_coverage":1.0}')
on conflict (slug) do nothing;

-- ---------------------------------------------------------------------
-- The runner learns the same rule
-- ---------------------------------------------------------------------
--
-- Without this the six cases above would have passed while the resolver was
-- still broken: the runner was testing the score and nothing else, which is
-- precisely how برجر لحم survived as beef for as long as it did. Redeclared in
-- full for the reason 0027 gave — a migration is a record of what was applied.

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
  min_coverage numeric;
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
          select r.qamar_food_id, r.slug, r.match_score, r.match_kind, r.is_recipe,
                 r.phrase_coverage
          from public.qamar_resolve_food(c.input->>'phrase', 3) r
          limit 1
        ) t;

        -- Usable means what the gateway means by it: close enough on the name
        -- AND accounting for enough of the phrase. Testing only the score is
        -- how برجر لحم passed as beef.
        min_coverage := coalesce((c.tolerance->>'min_coverage')::numeric, 0.6);

        if coalesce((c.expected->>'resolves')::boolean, true) = false then
          ok := not public.qamar_eval_usable(actual, 0.35, min_coverage);
          if not ok then
            detail := 'expected no usable match, got ' || (actual->>'slug')
                      || ' at ' || (actual->>'match_score')
                      || ' covering ' || (actual->>'phrase_coverage');
          end if;
        elsif actual is null then
          detail := 'expected ' || (c.expected->>'slug') || ', resolved nothing';
        else
          ok := actual->>'slug' = c.expected->>'slug'
                and public.qamar_eval_usable(actual, min_score, min_coverage);
          if not ok then
            detail := 'expected ' || (c.expected->>'slug') || ' at >= ' || min_score
                      || ', got ' || (actual->>'slug') || ' at ' || (actual->>'match_score')
                      || ' covering ' || (actual->>'phrase_coverage');
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
