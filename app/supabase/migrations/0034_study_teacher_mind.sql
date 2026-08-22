-- Study Mode / Teacher AI Mind: allow ai_interactions.kind = 'study'.

alter table public.ai_interactions drop constraint if exists ai_interactions_kind_check;
alter table public.ai_interactions add constraint ai_interactions_kind_check
  check (kind in ('chat', 'meal_analysis', 'plan', 'body_scan', 'study'));
