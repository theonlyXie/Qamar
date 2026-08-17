-- Mobile API surface — remaining entities from spec_mvp.txt §29.6 / Part 28
-- that 0001–0006 deferred: billing, media, food catalogue, memory, insights,
-- devices/reminders, privacy jobs, idempotency, app config, founder ops.
-- Additive only; existing RLS tables are unchanged.

-- ---------------------------------------------------------------------
-- App config + feature flags (bootstrap / founder ops)
-- ---------------------------------------------------------------------

create table if not exists public.app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);

insert into public.app_config (key, value) values
  ('min_app_version', '"0.9.0"'::jsonb),
  ('flags', '{"ask_qamar": true, "body_scan": true, "wallet": true, "plans": true}'::jsonb),
  ('quotas', '{"chat_per_day": 40, "meal_analyze_per_day": 30, "plan_per_day": 5}'::jsonb),
  ('wallet_ruleset', '{"version": "v1", "signup_bonus": 100}'::jsonb),
  ('journey_ruleset', '{"version": "v1", "daily_quest_points": 5}'::jsonb)
on conflict (key) do nothing;

alter table public.app_config enable row level security;
-- Readable by authenticated clients for bootstrap; writes are service-role /
-- admin Edge Function only (no insert/update policies for authenticated).
drop policy if exists app_config_read on public.app_config;
create policy app_config_read on public.app_config for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- Idempotency (confirmation, wallet, billing, export, deletion)
-- ---------------------------------------------------------------------

create table if not exists public.idempotency_keys (
  user_id uuid not null references auth.users (id) on delete cascade,
  scope text not null,
  key text not null,
  request_hash text,
  response_status int not null,
  response_body jsonb not null,
  created_at timestamptz not null default now(),
  primary key (user_id, scope, key)
);
create index if not exists idempotency_keys_created_idx
  on public.idempotency_keys (created_at);

alter table public.idempotency_keys enable row level security;
-- Owned only by the Edge Function (service role). No client policies.

-- ---------------------------------------------------------------------
-- Billing / entitlement / promo
-- ---------------------------------------------------------------------

create table if not exists public.entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  tier text not null default 'free' check (tier in ('free', 'qamar_plus')),
  product_id text,
  store text check (store is null or store in ('apple', 'google', 'revenuecat', 'manual')),
  original_transaction_id text,
  expires_at timestamptz,
  will_renew boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.billing_events (
  id uuid primary key default uuid_generate_v4(),
  provider text not null check (provider in ('revenuecat', 'apple', 'google')),
  provider_event_id text not null,
  user_id uuid references auth.users (id) on delete set null,
  payload jsonb not null,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (provider, provider_event_id)
);
create index if not exists billing_events_user_idx on public.billing_events (user_id, created_at desc);

create table if not exists public.promo_codes (
  code_hash text primary key,
  campaign text not null,
  offer_id text not null,
  max_redemptions int,
  redemptions int not null default 0,
  active boolean not null default true,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.promo_redemptions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  code_hash text not null references public.promo_codes (code_hash),
  created_at timestamptz not null default now(),
  unique (user_id, code_hash)
);

alter table public.entitlements enable row level security;
alter table public.billing_events enable row level security;
alter table public.promo_codes enable row level security;
alter table public.promo_redemptions enable row level security;

drop policy if exists entitlements_select_own on public.entitlements;
create policy entitlements_select_own on public.entitlements
  for select using (auth.uid() = user_id);
drop policy if exists promo_redemptions_select_own on public.promo_redemptions;
create policy promo_redemptions_select_own on public.promo_redemptions
  for select using (auth.uid() = user_id);
-- billing_events / promo_codes: service role only

-- ---------------------------------------------------------------------
-- Media (private storage metadata)
-- ---------------------------------------------------------------------

create table if not exists public.media_objects (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  bucket text not null default 'private-media',
  object_path text not null,
  mime_type text not null,
  byte_size int not null check (byte_size > 0 and byte_size <= 10485760),
  purpose text not null check (purpose in ('meal_photo', 'label', 'body_scan', 'voice', 'export')),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  created_at timestamptz not null default now(),
  unique (bucket, object_path)
);
create index if not exists media_objects_user_idx on public.media_objects (user_id, created_at desc);

alter table public.media_objects enable row level security;
drop policy if exists media_objects_select_own on public.media_objects;
create policy media_objects_select_own on public.media_objects
  for select using (auth.uid() = user_id);
drop policy if exists media_objects_insert_own on public.media_objects;
create policy media_objects_insert_own on public.media_objects
  for insert with check (auth.uid() = user_id);
drop policy if exists media_objects_delete_own on public.media_objects;
create policy media_objects_delete_own on public.media_objects
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- Food catalogue + barcode cache + corrections
-- ---------------------------------------------------------------------

-- trigram for fuzzy food search (must exist before gin_trgm_ops indexes)
create extension if not exists pg_trgm;

create table if not exists public.foods (
  id uuid primary key default uuid_generate_v4(),
  canonical_name text not null,
  locale_names jsonb not null default '{}'::jsonb, -- {ar, en, arabizi?}
  per_100g jsonb not null, -- {kcal, protein_g, carbs_g, fat_g}
  source text not null,
  source_url text,
  source_ref text, -- fdcId / OFF code / internal
  review_status text not null default 'approved'
    check (review_status in ('draft', 'approved', 'retired')),
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists foods_canonical_trgm_idx
  on public.foods using gin (canonical_name gin_trgm_ops);
create index if not exists foods_review_idx on public.foods (review_status);

create table if not exists public.food_aliases (
  id uuid primary key default uuid_generate_v4(),
  food_id uuid not null references public.foods (id) on delete cascade,
  alias text not null,
  lang text not null default 'ar' check (lang in ('ar', 'en', 'arabizi')),
  unique (alias, lang)
);
create index if not exists food_aliases_alias_idx on public.food_aliases using gin (alias gin_trgm_ops);

create table if not exists public.barcode_cache (
  gtin text primary key,
  food_id uuid references public.foods (id) on delete set null,
  provider text not null,
  payload jsonb not null,
  fetched_at timestamptz not null default now()
);

create table if not exists public.product_label_drafts (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  media_id uuid references public.media_objects (id) on delete set null,
  parsed jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft', 'confirmed', 'discarded')),
  created_at timestamptz not null default now(),
  confirmed_at timestamptz
);

create table if not exists public.food_corrections (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  food_id uuid references public.foods (id) on delete set null,
  meal_log_id uuid references public.meal_logs (id) on delete set null,
  proposed jsonb not null,
  status text not null default 'queued'
    check (status in ('queued', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

alter table public.foods enable row level security;
alter table public.food_aliases enable row level security;
alter table public.barcode_cache enable row level security;
alter table public.product_label_drafts enable row level security;
alter table public.food_corrections enable row level security;

drop policy if exists foods_read_approved on public.foods;
create policy foods_read_approved on public.foods
  for select to authenticated using (review_status = 'approved');
drop policy if exists food_aliases_read on public.food_aliases;
create policy food_aliases_read on public.food_aliases
  for select to authenticated using (true);
drop policy if exists barcode_cache_read on public.barcode_cache;
create policy barcode_cache_read on public.barcode_cache
  for select to authenticated using (true);
drop policy if exists product_label_drafts_own on public.product_label_drafts;
create policy product_label_drafts_select on public.product_label_drafts
  for select using (auth.uid() = user_id);
create policy product_label_drafts_insert on public.product_label_drafts
  for insert with check (auth.uid() = user_id);
create policy product_label_drafts_update on public.product_label_drafts
  for update using (auth.uid() = user_id);
drop policy if exists food_corrections_own on public.food_corrections;
create policy food_corrections_select on public.food_corrections
  for select using (auth.uid() = user_id);
create policy food_corrections_insert on public.food_corrections
  for insert with check (auth.uid() = user_id);

-- Fuzzy food search RPC used by the API Edge Function.
create or replace function public.search_foods(
  query text,
  match_count int default 20
)
returns table (
  id uuid,
  canonical_name text,
  locale_names jsonb,
  per_100g jsonb,
  source text,
  source_url text,
  score real
)
language sql
stable
security definer
set search_path = public
as $$
  select f.id,
         f.canonical_name,
         f.locale_names,
         f.per_100g,
         f.source,
         f.source_url,
         greatest(
           similarity(f.canonical_name, query),
           coalesce((
             select max(similarity(a.alias, query))
             from public.food_aliases a
             where a.food_id = f.id
           ), 0)
         )::real as score
    from public.foods f
   where f.review_status = 'approved'
     and (
       f.canonical_name % query
       or exists (
         select 1 from public.food_aliases a
          where a.food_id = f.id and a.alias % query
       )
       or f.canonical_name ilike '%' || query || '%'
       or exists (
         select 1 from public.food_aliases a
          where a.food_id = f.id and a.alias ilike '%' || query || '%'
       )
     )
   order by score desc, f.canonical_name
   limit least(match_count, 50);
$$;

revoke all on function public.search_foods(text, int) from public, anon;
grant execute on function public.search_foods(text, int) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- Memory + insights
-- ---------------------------------------------------------------------

create table if not exists public.memories (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('preference', 'exclusion', 'context', 'correction')),
  content text not null,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists memories_user_idx on public.memories (user_id, created_at desc);

create table if not exists public.memory_proposals (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  content text not null,
  provenance jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'dismissed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table if not exists public.insights (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  body text not null,
  evidence_ids jsonb not null default '[]'::jsonb,
  action_taken text,
  created_at timestamptz not null default now()
);
create index if not exists insights_user_idx on public.insights (user_id, created_at desc);

alter table public.memories enable row level security;
alter table public.memory_proposals enable row level security;
alter table public.insights enable row level security;

drop policy if exists memories_own on public.memories;
create policy memories_select on public.memories for select using (auth.uid() = user_id);
create policy memories_insert on public.memories for insert with check (auth.uid() = user_id);
create policy memories_update on public.memories for update using (auth.uid() = user_id);
create policy memories_delete on public.memories for delete using (auth.uid() = user_id);

drop policy if exists memory_proposals_own on public.memory_proposals;
create policy memory_proposals_select on public.memory_proposals for select using (auth.uid() = user_id);
create policy memory_proposals_insert on public.memory_proposals for insert with check (auth.uid() = user_id);
create policy memory_proposals_update on public.memory_proposals for update using (auth.uid() = user_id);

drop policy if exists insights_own on public.insights;
create policy insights_select on public.insights for select using (auth.uid() = user_id);
create policy insights_insert on public.insights for insert with check (auth.uid() = user_id);
create policy insights_update on public.insights for update using (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- Chat conversations (streaming stop / report)
-- ---------------------------------------------------------------------

create table if not exists public.chat_conversations (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  lang text not null default 'ar' check (lang in ('ar', 'en')),
  status text not null default 'open' check (status in ('open', 'stopped', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.chat_messages (
  id uuid primary key default uuid_generate_v4(),
  conversation_id uuid not null references public.chat_conversations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'system')),
  content text not null,
  sources jsonb not null default '[]'::jsonb,
  reported_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_conv_idx
  on public.chat_messages (conversation_id, created_at);

create table if not exists public.pending_actions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  payload jsonb not null,
  confirmation_token text not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'expired', 'cancelled')),
  expires_at timestamptz not null default (now() + interval '15 minutes'),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

alter table public.chat_conversations enable row level security;
alter table public.chat_messages enable row level security;
alter table public.pending_actions enable row level security;

drop policy if exists chat_conversations_own on public.chat_conversations;
create policy chat_conversations_select on public.chat_conversations for select using (auth.uid() = user_id);
create policy chat_conversations_insert on public.chat_conversations for insert with check (auth.uid() = user_id);
create policy chat_conversations_update on public.chat_conversations for update using (auth.uid() = user_id);

drop policy if exists chat_messages_own on public.chat_messages;
create policy chat_messages_select on public.chat_messages for select using (auth.uid() = user_id);
create policy chat_messages_insert on public.chat_messages for insert with check (auth.uid() = user_id);
create policy chat_messages_update on public.chat_messages for update using (auth.uid() = user_id);

drop policy if exists pending_actions_own on public.pending_actions;
create policy pending_actions_select on public.pending_actions for select using (auth.uid() = user_id);
create policy pending_actions_insert on public.pending_actions for insert with check (auth.uid() = user_id);
create policy pending_actions_update on public.pending_actions for update using (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------

create table if not exists public.devices (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text not null check (platform in ('ios', 'android', 'web')),
  push_token text not null,
  locale text not null default 'ar',
  timezone text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, push_token)
);
create index if not exists devices_user_idx on public.devices (user_id);

create table if not exists public.reminders (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('meal', 'water', 'weigh_in', 'quest', 'custom')),
  local_time time not null,
  days_of_week int[] not null default '{1,2,3,4,5,6,7}',
  enabled boolean not null default true,
  template_id text not null default 'generic',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.devices enable row level security;
alter table public.reminders enable row level security;

drop policy if exists devices_own on public.devices;
create policy devices_select on public.devices for select using (auth.uid() = user_id);
create policy devices_insert on public.devices for insert with check (auth.uid() = user_id);
create policy devices_update on public.devices for update using (auth.uid() = user_id);
create policy devices_delete on public.devices for delete using (auth.uid() = user_id);

drop policy if exists reminders_own on public.reminders;
create policy reminders_select on public.reminders for select using (auth.uid() = user_id);
create policy reminders_insert on public.reminders for insert with check (auth.uid() = user_id);
create policy reminders_update on public.reminders for update using (auth.uid() = user_id);
create policy reminders_delete on public.reminders for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- Privacy: exports + account deletion
-- ---------------------------------------------------------------------

create table if not exists public.data_exports (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'queued'
    check (status in ('queued', 'ready', 'failed', 'expired')),
  object_path text,
  error text,
  created_at timestamptz not null default now(),
  ready_at timestamptz,
  expires_at timestamptz
);

create table if not exists public.account_deletion_jobs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'queued'
    check (status in ('queued', 'running', 'done', 'failed')),
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  error text
);

alter table public.data_exports enable row level security;
alter table public.account_deletion_jobs enable row level security;

drop policy if exists data_exports_own on public.data_exports;
create policy data_exports_select on public.data_exports for select using (auth.uid() = user_id);
create policy data_exports_insert on public.data_exports for insert with check (auth.uid() = user_id);

drop policy if exists account_deletion_jobs_own on public.account_deletion_jobs;
create policy account_deletion_jobs_select on public.account_deletion_jobs
  for select using (auth.uid() = user_id);
create policy account_deletion_jobs_insert on public.account_deletion_jobs
  for insert with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- Analytics (content-free) + feedback + support
-- ---------------------------------------------------------------------

create table if not exists public.analytics_events (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users (id) on delete set null,
  name text not null,
  props jsonb not null default '{}'::jsonb,
  client_ts timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists analytics_events_name_idx
  on public.analytics_events (name, created_at desc);

create table if not exists public.feedback (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  category text not null default 'general',
  body text not null,
  created_at timestamptz not null default now()
);

alter table public.analytics_events enable row level security;
alter table public.feedback enable row level security;

drop policy if exists analytics_events_insert_own on public.analytics_events;
create policy analytics_events_insert_own on public.analytics_events
  for insert with check (auth.uid() = user_id or user_id is null);
drop policy if exists feedback_own on public.feedback;
create policy feedback_insert on public.feedback for insert with check (auth.uid() = user_id);
create policy feedback_select on public.feedback for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- Guidance claim registry (why / sources)
-- ---------------------------------------------------------------------

create table if not exists public.guidance_claims (
  id text primary key,
  title text not null,
  summary text not null,
  source_ids uuid[] not null default '{}',
  assumptions jsonb not null default '[]'::jsonb,
  approved boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.decision_traces (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  claim_ids text[] not null default '{}',
  assumptions jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.guidance_claims enable row level security;
alter table public.decision_traces enable row level security;

drop policy if exists guidance_claims_read on public.guidance_claims;
create policy guidance_claims_read on public.guidance_claims
  for select to authenticated using (approved = true);
drop policy if exists decision_traces_own on public.decision_traces;
create policy decision_traces_select on public.decision_traces
  for select using (auth.uid() = user_id);
create policy decision_traces_insert on public.decision_traces
  for insert with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- Rate limits (per-user daily counters)
-- ---------------------------------------------------------------------

create table if not exists public.rate_limits (
  user_id uuid not null references auth.users (id) on delete cascade,
  bucket text not null,
  day date not null default (timezone('utc', now()))::date,
  count int not null default 0,
  primary key (user_id, bucket, day)
);

alter table public.rate_limits enable row level security;
-- service role only

-- ---------------------------------------------------------------------
-- Achievements / cosmetics (Journey)
-- ---------------------------------------------------------------------

create table if not exists public.achievements (
  id text primary key,
  title_ar text not null,
  title_en text not null,
  active boolean not null default true
);

create table if not exists public.user_achievements (
  user_id uuid not null references auth.users (id) on delete cascade,
  achievement_id text not null references public.achievements (id),
  earned_at timestamptz not null default now(),
  primary key (user_id, achievement_id)
);

create table if not exists public.cosmetics (
  id text primary key,
  title_ar text not null,
  title_en text not null,
  price_points int not null default 0,
  active boolean not null default true
);

create table if not exists public.user_cosmetics (
  user_id uuid not null references auth.users (id) on delete cascade,
  cosmetic_id text not null references public.cosmetics (id),
  equipped boolean not null default false,
  unlocked_at timestamptz not null default now(),
  primary key (user_id, cosmetic_id)
);

alter table public.achievements enable row level security;
alter table public.user_achievements enable row level security;
alter table public.cosmetics enable row level security;
alter table public.user_cosmetics enable row level security;

drop policy if exists achievements_read on public.achievements;
create policy achievements_read on public.achievements for select to authenticated using (active);
drop policy if exists cosmetics_read on public.cosmetics;
create policy cosmetics_read on public.cosmetics for select to authenticated using (active);
drop policy if exists user_achievements_own on public.user_achievements;
create policy user_achievements_select on public.user_achievements for select using (auth.uid() = user_id);
drop policy if exists user_cosmetics_own on public.user_cosmetics;
create policy user_cosmetics_select on public.user_cosmetics for select using (auth.uid() = user_id);
create policy user_cosmetics_update on public.user_cosmetics for update using (auth.uid() = user_id);
create policy user_cosmetics_insert on public.user_cosmetics for insert with check (auth.uid() = user_id);

insert into public.achievements (id, title_ar, title_en) values
  ('first_meal', 'أول وجبة', 'First meal'),
  ('seven_day', 'سبعة أيام', 'Seven-day streak')
on conflict do nothing;

insert into public.cosmetics (id, title_ar, title_en, price_points) values
  ('orb_glow', 'توهج القمر', 'Moon glow', 40)
on conflict do nothing;

-- ---------------------------------------------------------------------
-- Founder admins
-- ---------------------------------------------------------------------

create table if not exists public.founder_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null default 'founder' check (role in ('founder', 'ops')),
  created_at timestamptz not null default now()
);

alter table public.founder_admins enable row level security;
-- no client policies; Edge Function checks via service role

-- ---------------------------------------------------------------------
-- Meal drafts: allow parse/clarify timestamps (soft columns via jsonb already)
-- Plan versioning helper
-- ---------------------------------------------------------------------

alter table public.meal_plans
  add column if not exists version int not null default 1;

-- Support codes derived from user id hash (stable, non-PII).
create or replace function public.qamar_support_code(uid uuid)
returns text
language sql
immutable
as $$
  select 'Q-' || upper(substr(md5(uid::text), 1, 8));
$$;

revoke all on function public.qamar_support_code(uuid) from public, anon;
grant execute on function public.qamar_support_code(uuid) to authenticated, service_role;

-- Seed a few high-frequency Egyptian staples so /foods/search works before
-- the full catalogue bakeoff lands.
insert into public.foods (canonical_name, locale_names, per_100g, source, source_ref, review_status)
select v.canonical_name, v.locale_names, v.per_100g, v.source, v.source_ref, v.review_status
from (values
  ('foul medames', '{"ar":"فول مدمس","en":"foul medames"}'::jsonb,
   '{"kcal":100,"protein_g":7,"carbs_g":14,"fat_g":2}'::jsonb, 'qamar_seed', 'seed:foul', 'approved'),
  ('baladi bread', '{"ar":"عيش بلدي","en":"baladi bread"}'::jsonb,
   '{"kcal":260,"protein_g":9,"carbs_g":52,"fat_g":2}'::jsonb, 'qamar_seed', 'seed:baladi', 'approved'),
  ('koshary', '{"ar":"كشري","en":"koshary"}'::jsonb,
   '{"kcal":150,"protein_g":5,"carbs_g":28,"fat_g":3}'::jsonb, 'qamar_seed', 'seed:koshary', 'approved'),
  ('taameya', '{"ar":"طعمية","en":"taameya"}'::jsonb,
   '{"kcal":280,"protein_g":10,"carbs_g":22,"fat_g":16}'::jsonb, 'qamar_seed', 'seed:taameya', 'approved'),
  ('white rice cooked', '{"ar":"رز أبيض","en":"white rice cooked"}'::jsonb,
   '{"kcal":130,"protein_g":2,"carbs_g":28,"fat_g":0}'::jsonb, 'qamar_seed', 'seed:rice', 'approved')
) as v(canonical_name, locale_names, per_100g, source, source_ref, review_status)
where not exists (
  select 1 from public.foods f where f.source_ref = v.source_ref
);

insert into public.food_aliases (food_id, alias, lang)
select f.id, a.alias, a.lang
from public.foods f
join (values
  ('foul medames', 'فول', 'ar'),
  ('foul medames', 'ful', 'en'),
  ('baladi bread', 'عيش', 'ar'),
  ('koshary', 'كشري', 'ar'),
  ('taameya', 'فلافل', 'ar'),
  ('taameya', 'falafel', 'en')
) as a(canonical, alias, lang) on f.canonical_name = a.canonical
where not exists (
  select 1 from public.food_aliases x where x.alias = a.alias and x.lang = a.lang
);
