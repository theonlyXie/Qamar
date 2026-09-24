-- Store what the citation actually says, and flag the ones that disagree.
--
-- 0074 had to correct thirty-six curated foods whose nutrients came from the
-- wrong USDA entry. Every guard in this project checks that a claim carries a
-- source. None of them could check whether the source was about the right
-- food, because the only thing stored was an id — 173472 tells nobody it means
-- "Horseradish, prepared". A citation you cannot read is a citation you cannot
-- check, and this is the column that makes it readable.
--
-- Applied live on 2026-08-23 as `store_and_check_cited_titles`.

alter table public.food_source_links
  add column if not exists source_title text;

comment on column public.food_source_links.source_title is
  'What the cited source calls this food, in its own words. Stored so a human '
  'or a check can see whether the citation is about the right thing, which an '
  'id alone can never show.';

-- Fill it from the bulk catalogue, which holds the same USDA foods under slugs
-- ending in their fdc_id.
update public.food_source_links l
set source_title = d.name_en
from public.foods d
where l.source_id = 'usda_fdc'
  and l.source_title is null
  and d.source_rank = 10
  and d.slug like '%\_' || l.external_id;

-- Flags a curated food whose name has nothing in common with the source it
-- cites. Trigram similarity, not exact matching: "Tilapia" against "Fish,
-- tilapia, raw" should pass, and "Sugar" against "Sugar-apples, (sweetsop),
-- raw" is exactly the near-miss that has to fail.
--
-- It has false positives on purpose. "Apple" against "Apples, raw, golden
-- delicious, with skin" scores 0.128 and is correct; a review queue that only
-- listed certainties would have missed every one of the foods 0074 fixed.
create or replace view public.food_citation_suspects
with (security_invoker = true) as
select f.slug,
       f.name_en,
       l.external_id,
       l.source_title,
       round(similarity(lower(f.name_en), lower(coalesce(l.source_title, '')))::numeric, 3)
         as name_similarity,
       (select fn.amount from public.food_nutrients fn
         where fn.qamar_food_id = f.qamar_food_id
           and fn.nutrient_code = 'energy_kcal') as kcal_per_100g
from public.foods f
join public.food_source_links l on l.qamar_food_id = f.qamar_food_id
where f.source_rank > 10
  and (
    l.source_title is null
    or similarity(lower(f.name_en), lower(l.source_title)) < 0.20
  )
order by name_similarity nulls first, f.slug;

comment on view public.food_citation_suspects is
  'Curated foods whose cited source does not appear to be about them. Review '
  'these before trusting their numbers; see migration 0074 for what happened '
  'when nobody could.';

revoke all on public.food_citation_suspects from public, anon, authenticated;
grant select on public.food_citation_suspects to service_role;

notify pgrst, 'reload schema';
