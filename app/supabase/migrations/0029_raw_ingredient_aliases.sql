-- Teaching the graph the words that distinguish a raw ingredient from its dish.
--
-- 0028 made "كبدة" resolve to the cooked dish, which is right. The eval then
-- caught what that cost: "كبدة نيئة" — raw liver — resolved to the dish too.
--
-- The reason is worth writing down, because it is a limit of the resolver and
-- not a bad row. For that phrase both candidates' best alias is the identical
-- string "كبدة", at identical priority, at identical trigram similarity of 0.5.
-- The word "نيئة" is not weighed and discarded — it never enters the comparison
-- at all. Matching is alias-to-phrase, so any word in the phrase that no alias
-- contains contributes nothing, and no ordering rule downstream can recover
-- information that was never measured.
--
-- Two honest responses, and this migration is the second:
--
--   Fix the ranking. Impossible here. There is no signal to rank on; the two
--   candidates are indistinguishable by construction.
--
--   Give the distinguishing word an alias. Then it is measured, the raw
--   ingredient scores higher than the dish on that phrase, and it wins on score
--   before any tie-break is consulted.
--
-- The aliases below are words people actually use, not phrases invented to make
-- a test pass: raw liver is bought and cooked at home, and frozen molokhia is
-- how most of it is sold. The test asserts a real user need; this is the graph
-- learning the vocabulary that need is expressed in.
--
-- The general limitation stands and is not fixed here: a modifier can only be
-- honoured if some alias contains it. "بلطي مشوي" resolves to tilapia because
-- "بلطي" carries it, not because the graph knows what مشوي means. That is
-- acceptable while every modifier merely narrows a food rather than changing
-- it, and stops being acceptable the moment a modifier changes the nutrition —
-- which is exactly the raw-versus-cooked case handled here.

insert into public.food_aliases (qamar_food_id, alias, lang, priority)
select f.qamar_food_id, v.alias, v.lang, v.priority
from (values
  -- The ingredient side of every contested name in contested_food_aliases.
  ('liver',           'كبدة نيئة',      'ar',      140),
  ('liver',           'كبدة نية',       'eg',      140),
  ('liver',           'raw liver',      'en',      140),
  ('molokhia_leaves', 'ملوخية مجمدة',   'eg',      140),
  ('molokhia_leaves', 'raw molokhia',   'en',      140),
  ('molokhia_leaves', 'molokhia leaves','en',      140)
) as v(slug, alias, lang, priority)
join public.foods f on f.slug = v.slug
on conflict (qamar_food_id, alias, lang) do nothing;

-- Priority 140 is above the 130 a food's own colloquial name carries, and that
-- is deliberate: "كبدة نيئة" is a more specific claim than "كبدة", and the more
-- specific claim should win when the user made it. It only ever applies to a
-- phrase that contains the extra word, because a shorter phrase scores lower
-- against a longer alias.

comment on table public.food_aliases is
  'Every name a food answers to. Matching is alias-to-phrase, so a word the '
  'user types that appears in no alias contributes nothing to the match — '
  'which is why a modifier that changes the nutrition (raw, frozen) needs an '
  'alias of its own, and one that merely narrows it (grilled) does not. '
  'See 0029.';
