-- Qamar core schema — MVP subset of spec_mvp.txt Part 28 (Data model).
-- Scope: identity/consent, nutrition profile + target, meal logging, Su
-- Points wallet + ledger, quests, weight trend. Deferred (not in this
-- migration): GuidelineDocument/Claim + RAG tables, Food/SourceRecord +
-- ProviderFoodReference + FoodAlias/Embedding (needs pgvector + a real
-- food-data pipeline), Entitlement/BillingEvent/PromoCampaign (needs a
-- store-billing integration to design against), founder/ops tables.
-- All of those are additive — nothing here blocks adding them later.

create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------------
-- Identity & consent
-- ---------------------------------------------------------------------

-- Supabase's auth.users is the identity root (anonymous + linked Apple/
-- Google/email-OTP all land here per spec_mvp.txt §29.1). This table holds
-- the Qamar-specific profile fields keyed to it.
create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  name text,
  locale text not null default 'ar' check (locale in ('ar', 'en')),
  age int check (age between 13 and 100),
  height_cm int check (height_cm between 100 and 230),
  weight_kg int check (weight_kg between 30 and 250),
  body_fat_pct int check (body_fat_pct between 3 and 70),
  goal text check (goal in ('lose', 'maintain', 'gain')),
  activity_factor numeric check (activity_factor between 1.0 and 2.2),
  food_exclusions text[] not null default '{}',
  eligibility_status text not null default 'pending' check (eligibility_status in ('pending', 'eligible', 'blocked_minor', 'blocked_safety')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.consents (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  type text not null check (type in ('processing_required', 'improve_optional')),
  version text not null,
  granted_at timestamptz,
  withdrawn_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists consents_user_idx on public.consents (user_id);

-- ---------------------------------------------------------------------
-- Target
-- ---------------------------------------------------------------------

-- One row per calculated target so corrections stay traceable
-- (spec_mvp.txt: "every derived record stores its policy/formula version").
create table if not exists public.targets (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kcal int not null,
  protein_g int not null,
  carbs_g int not null,
  fat_g int not null,
  formula_version text not null default 'calc v2.0',
  inputs jsonb not null, -- {age, height_cm, weight_kg, activity_factor, goal}
  confirmed_at timestamptz not null default now(),
  valid_from timestamptz not null default now(),
  valid_to timestamptz
);
create index if not exists targets_user_idx on public.targets (user_id, valid_from desc);

-- ---------------------------------------------------------------------
-- Meal logging (S21-S26: draft -> confirm-before-write -> log)
-- ---------------------------------------------------------------------

create table if not exists public.meal_drafts (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  input_type text not null check (input_type in ('photo', 'voice', 'text', 'barcode', 'label', 'recent')),
  candidate_items jsonb not null, -- [{name, portion, confidence, kcal, protein_g, carbs_g, fat_g, qty}]
  raw_text text,
  media_path text, -- Supabase Storage short-lived object path, never a public bucket
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '1 hour')
);

create table if not exists public.meal_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  draft_id uuid references public.meal_drafts (id) on delete set null,
  name text not null,
  source text not null, -- e.g. "text · estimate", "photo · high confidence"
  items jsonb not null,
  kcal int not null,
  protein_g int not null,
  carbs_g int not null,
  fat_g int not null,
  logged_at timestamptz not null default now(),
  confirmed_at timestamptz not null default now()
);
create index if not exists meal_logs_user_day_idx on public.meal_logs (user_id, logged_at desc);

-- ---------------------------------------------------------------------
-- Su Points wallet (S59) — ledger is the source of truth; wallet_accounts
-- is a materialized balance for fast reads.
-- ---------------------------------------------------------------------

create table if not exists public.wallet_accounts (
  user_id uuid primary key references auth.users (id) on delete cascade,
  available_points int not null default 0,
  lifetime_earned int not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.su_point_ledger (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  delta int not null, -- positive = credit, negative = debit/refund
  reason text not null, -- 'onboarding_complete' | 'first_meal' | 'daily_quest' | 'redemption:<item_id>' | 'refund:<ledger_id>'
  idempotency_key text not null,
  balance_after int not null,
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);
create index if not exists su_ledger_user_idx on public.su_point_ledger (user_id, created_at desc);

create table if not exists public.wallet_catalog_items (
  id text primary key, -- 'photo' | 'insight' | 'plan' | 'cosmetic', matches SPEND in the client
  price int not null,
  monthly_limit int,
  active boolean not null default true
);

create table if not exists public.wallet_redemptions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  catalog_item_id text not null references public.wallet_catalog_items (id),
  ledger_id uuid not null references public.su_point_ledger (id),
  status text not null default 'redeemed' check (status in ('redeemed', 'refunded')),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Quests, weight trend
-- ---------------------------------------------------------------------

create table if not exists public.quests (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  quest_type text not null default 'primary_daily',
  title text not null,
  reason text not null,
  su_points int not null default 5,
  issued_at timestamptz not null default now(),
  expires_at timestamptz,
  completed_at timestamptz,
  replaced_at timestamptz
);
create index if not exists quests_user_idx on public.quests (user_id, issued_at desc);

create table if not exists public.weight_entries (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  value_kg numeric not null,
  measured_at timestamptz not null default now(),
  source text not null default 'manual'
);
create index if not exists weight_entries_user_idx on public.weight_entries (user_id, measured_at desc);

-- ---------------------------------------------------------------------
-- Row-level security — every table above is strictly owner-scoped for MVP.
-- ---------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.consents enable row level security;
alter table public.targets enable row level security;
alter table public.meal_drafts enable row level security;
alter table public.meal_logs enable row level security;
alter table public.wallet_accounts enable row level security;
alter table public.su_point_ledger enable row level security;
alter table public.wallet_redemptions enable row level security;
alter table public.quests enable row level security;
alter table public.weight_entries enable row level security;

do $$
declare
  t text;
begin
  for t in select unnest(array[
    'profiles', 'consents', 'targets', 'meal_drafts', 'meal_logs',
    'wallet_accounts', 'su_point_ledger', 'wallet_redemptions', 'quests', 'weight_entries'
  ])
  loop
    execute format('
      create policy %I on public.%I for select using (auth.uid() = user_id);
      create policy %I on public.%I for insert with check (auth.uid() = user_id);
      create policy %I on public.%I for update using (auth.uid() = user_id);
    ', t || '_select_own', t, t || '_insert_own', t, t || '_update_own', t);
  end loop;
end $$;

-- wallet_catalog_items is public read-only reference data (prices), no RLS needed beyond default deny-write.
alter table public.wallet_catalog_items enable row level security;
create policy wallet_catalog_read on public.wallet_catalog_items for select using (true);

insert into public.wallet_catalog_items (id, price, monthly_limit) values
  ('photo', 20, 5),
  ('insight', 30, null),
  ('plan', 25, 2),
  ('cosmetic', 50, null)
on conflict (id) do nothing;
