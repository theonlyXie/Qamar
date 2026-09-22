-- A meal reading's note is never about the score (O3).
--
-- "Fixed points keep the economy honest; variable words keep the reward
-- alive" (blueprint, line 614). The wallet counts and Qamar talks: no word
-- Qamar says after a meal is about Su, points or earning. The app's own
-- replies are held by a Dart test (app/test/reply_test.dart). The gateway's
-- meal note is held here: the food graph's fixed note on a typed or spoken
-- meal must read without any score word, in both languages, and the model's
-- note on a plate is dropped whole if it talks points (notes.ts).
--
-- Deno runs these (runner "deno", kind "meal_note", eval.ts); eval_test.ts
-- runs verbatim copies offline. Frozen, like every case: supersede, never edit.

insert into public.eval_cases (family, slug, description, input, expected)
values
  ('arabic_ux', 'meal_note_graph_en',
   'The food graph''s note on a typed meal, in English, says nothing about Su, points or earning.',
   '{"kind":"meal_note","runner":"deno","lang":"en","items":[{"en":"Koshary","kcal":507}]}',
   '{"score_free":true,"dropped":false}'),
  ('arabic_ux', 'meal_note_graph_ar',
   'The food graph''s note on a typed meal, in Arabic, says nothing about Su, points or earning.',
   '{"kind":"meal_note","runner":"deno","lang":"ar","items":[{"ar":"كشري","kcal":507}]}',
   '{"score_free":true,"dropped":false}'),
  ('arabic_ux', 'meal_note_graph_miss',
   'The note when the graph matches nothing says nothing about the score either.',
   '{"kind":"meal_note","runner":"deno","lang":"en","items":[]}',
   '{"score_free":true,"dropped":false}'),
  ('adversarial_reliability', 'meal_note_model_portion',
   'A model note about the assumed portion is shown as written.',
   '{"kind":"meal_note","runner":"deno","lang":"en","note":"I assumed a medium plate of koshary."}',
   '{"score_free":true,"dropped":false}'),
  ('adversarial_reliability', 'meal_note_model_score_en',
   'A model note that talks points is dropped, never shown.',
   '{"kind":"meal_note","runner":"deno","lang":"en","note":"Great choice, you earned 100 Su points!"}',
   '{"score_free":true,"dropped":true}'),
  ('adversarial_reliability', 'meal_note_model_score_ar',
   'An Arabic model note that talks points is dropped, never shown.',
   '{"kind":"meal_note","runner":"deno","lang":"ar","note":"برافو، كسبت ١٠٠ نقطة!"}',
   '{"score_free":true,"dropped":true}')
on conflict (slug) do nothing;
