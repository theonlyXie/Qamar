-- The first eval run found this, which is the whole argument for having one.
--
-- "ملوخية" resolved to molokhia_leaves — the raw leaf — at an exact score of 1.
-- Nobody eats raw molokhia. Someone logging a bowl of it would have been priced
-- against a leafy green at roughly 40 kcal per 100 g instead of a cooked dish
-- eaten by the 300 g bowl, and nothing anywhere would have said so. "كبدة" had
-- the same shape.
--
-- Two defects, and the second is the one that would have kept biting.
--
-- 1. No meaningful tie-break between a dish and its own ingredient. Both carry
--    the same bare alias at the same priority, because both are legitimately
--    called that.
--
-- 2. No deterministic tie-break at all. The ordering ended at
--    `source_rank desc nulls last`, and when that ties too the row order is
--    whatever the plan happens to produce — so the same phrase could resolve
--    differently between two runs, and an eval case could pass on Tuesday and
--    fail on Wednesday with nothing changed. That is worse than a wrong answer,
--    because it makes every other result untrustworthy.
--
-- The rule added here is narrow on purpose: prefer the recipe only when score
-- AND priority are both already tied. That state is reachable essentially only
-- when a dish and an ingredient share a name, which is exactly the case being
-- fixed — it is not a general "dishes win" preference, which would be wrong.
--
-- It also does not hide the ambiguity. graph.ts flags a runner-up within 0.1 as
-- "could also be X", and an exact tie is a gap of zero, so the user is still
-- asked. The change decides which one is offered first, not whether they get a
-- say.

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
  has_nutrients boolean
)
language sql
stable
set search_path = public
as $$
  with norm as (
    -- Strip quantities and units so "100 جرام جبنة قريش" matches the cheese
    -- rather than missing on the number.
    select btrim(lower(regexp_replace(
      p_phrase, '[0-9٠-٩]+\s*(g|kg|ml|جم|جرام|كجم|مل|جرامات)?', ' ', 'gi'))) as q
  ),
  candidates as (
    select a.qamar_food_id,
           a.alias,
           a.priority,
           case when lower(a.alias) = (select q from norm) then 1.0::real
                else similarity(a.alias, (select q from norm)) end as score,
           case when lower(a.alias) = (select q from norm) then 'exact' else 'fuzzy' end as kind
    from public.food_aliases a, norm
    where norm.q <> ''
      and (lower(a.alias) = norm.q or a.alias % norm.q)
  ),
  best as (
    select distinct on (c.qamar_food_id)
           c.qamar_food_id, c.alias, c.score, c.kind, c.priority
    from candidates c
    -- alias last so the winning alias for one food is reproducible too.
    order by c.qamar_food_id, c.score desc, c.priority desc, c.alias
  )
  select f.qamar_food_id, f.slug, f.name_en, f.name_ar, f.name_eg, f.is_recipe,
         b.score, b.alias, b.kind,
         exists (select 1 from public.food_nutrients n where n.qamar_food_id = f.qamar_food_id)
           or f.is_recipe
  from best b
  join public.foods f on f.qamar_food_id = b.qamar_food_id
  order by b.score desc,
           b.priority desc,
           -- Only reachable when a dish and an ingredient answer to the same
           -- name at the same priority. In Egypt that phrase means the meal.
           f.is_recipe desc,
           f.source_rank desc nulls last,
           -- Total order. Without this the resolver is not a function of its
           -- inputs, and nothing built on it can be regression tested.
           f.slug
  limit greatest(p_limit, 1);
$$;

comment on function public.qamar_resolve_food is
  'Local-first food identity. Exact alias match scores 1.0; anything else is a '
  'trigram score the caller must treat as uncertain. Ordering is a total order, '
  'so the same phrase always resolves the same way. On an exact tie between a '
  'dish and its own ingredient the dish wins — both are still returned, so the '
  'caller can ask.';

-- The two collisions that exist today, recorded as cases so a future alias
-- import that reintroduces the problem fails the suite instead of shipping.
insert into public.eval_cases (family, slug, description, input, expected, tolerance) values
('food_resolution','res_kebda_dish','Bare "كبدة" means the cooked dish, as "ملوخية" does',
 '{"runner":"sql","kind":"resolve_food","phrase":"كبدة"}',
 '{"slug":"kebda_eskandarani","is_recipe":true}','{"min_score":0.6}'),
('food_resolution','res_liver_ingredient','The raw ingredient stays reachable when named as such',
 '{"runner":"sql","kind":"resolve_food","phrase":"كبدة نيئة"}','{"slug":"liver"}','{"min_score":0.4}'),
('food_resolution','res_determinism','Repeated resolution agrees with itself. A weak check by nature - the strong guarantee is the slug key at the end of the ORDER BY - but it catches the gross case where that key is removed',
 '{"runner":"sql","kind":"resolve_food_stable","phrase":"ملوخية","repeats":8}',
 '{"stable":true}','{}')
on conflict (slug) do nothing;

-- The runner learns the new kind.
create or replace function public.qamar_eval_stable_slug(p_phrase text, p_repeats int)
returns table (distinct_answers int, answer text)
language plpgsql
stable
set search_path = public
as $fn$
declare
  seen text[] := '{}';
  s text;
  i int;
begin
  for i in 1..greatest(p_repeats, 2) loop
    select r.slug into s from public.qamar_resolve_food(p_phrase, 3) r limit 1;
    if not (coalesce(s, '(none)') = any(seen)) then
      seen := seen || coalesce(s, '(none)');
    end if;
  end loop;
  return query select cardinality(seen), seen[1];
end;
$fn$;

-- The runner gains one branch for the new kind. Redeclared in full rather than
-- patched, because a migration is a record of what was applied and an ALTER
-- that only makes sense against 0026's text is not one.
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
