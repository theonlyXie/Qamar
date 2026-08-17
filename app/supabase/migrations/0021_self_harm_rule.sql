-- A separate rule for self-harm.
--
-- 0014 had severe_symptom covering everything urgent. Wiring the detection made
-- it obvious that "I have chest pain" and "I want to die" are not the same
-- event: they need different words back, different urgency, and different
-- questions put to whoever reviews them. Folding them together would have
-- produced one blended message that served neither.
--
-- Both escalate to urgent_referral, and both are checked before every other
-- rule in scope.ts — including the prompt-injection guard, because a person in
-- crisis matters more than prompt hygiene and the outcome is a refusal plus an
-- escalation either way, so there is nothing to exploit by combining them.

insert into public.red_flag_rules (slug, description, detection, escalate_to, min_risk_tier)
values
('self_harm',
 'User expresses intent to harm themselves, or that they do not want to live',
 'scope.ts SELF_HARM keyword set, Arabic and English, checked first',
 'urgent_referral', 'high_risk')
on conflict (slug) do nothing;

-- severe_symptom now has detection behind it; the row described an intention.
update public.red_flag_rules
   set detection = 'scope.ts SEVERE_SYMPTOM keyword set, Arabic and English, checked second',
       description = 'Symptoms needing care now rather than a nutrition answer: chest pain, breathing difficulty, fainting, bleeding, severe pain, neurological signs'
 where slug = 'severe_symptom';

-- rapid_weight_change and critical_lab became triggers in 0020.
update public.red_flag_rules
   set detection = 'trigger qamar_flag_rapid_weight_change on weight_entries: 5% of body weight within 30 days, min 3 measurements over 14 days, debounced 7 days'
 where slug = 'rapid_weight_change';

update public.red_flag_rules
   set detection = 'trigger qamar_flag_critical_lab on user_labs: abnormal_flag in (critical_low, critical_high)'
 where slug = 'critical_lab';
