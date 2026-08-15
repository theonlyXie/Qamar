-- Retrieval knowledge base.
--
-- The assistant is not allowed to answer from the model's own memory: every
-- nutrition or training claim it makes has to come from a chunk retrieved
-- here, and the chunk's source travels with the answer so the app can show
-- "why". That is what keeps a general-purpose model inside the narrow job this
-- product is allowed to do.

create extension if not exists vector;

create table if not exists public.kb_documents (
  id uuid primary key default uuid_generate_v4(),
  -- e.g. 'WHO', 'EFSA', 'NIH-ODS', 'ACSM', 'egypt_food_composition'
  source text not null,
  title text not null,
  url text,
  -- Whether the text may be quoted verbatim or only paraphrased.
  licence text,
  -- 'nutrition' | 'training' — the only two topics the assistant serves.
  domain text not null check (domain in ('nutrition', 'training')),
  published_on date,
  retrieved_at timestamptz not null default now()
);

create table if not exists public.kb_chunks (
  id uuid primary key default uuid_generate_v4(),
  document_id uuid not null references public.kb_documents (id) on delete cascade,
  chunk_index int not null,
  content text not null,
  -- 1024 dims matches voyage-3; change together with EMBEDDING_MODEL and
  -- re-embed everything if you switch provider.
  embedding vector(1024),
  created_at timestamptz not null default now(),
  unique (document_id, chunk_index)
);

-- Approximate nearest neighbour. Lists is deliberately small: this index only
-- pays off past a few thousand chunks, and is cheap to rebuild after a bulk
-- ingest.
create index if not exists kb_chunks_embedding_idx
  on public.kb_chunks using ivfflat (embedding vector_cosine_ops) with (lists = 100);

create index if not exists kb_chunks_document_idx on public.kb_chunks (document_id);

-- Reference knowledge, not user data: readable by any signed-in user, written
-- only by the service role during ingestion.
alter table public.kb_documents enable row level security;
alter table public.kb_chunks enable row level security;
-- Postgres has no `create policy if not exists`, so each one is dropped first
-- to keep this file re-runnable.
drop policy if exists kb_documents_read on public.kb_documents;
create policy kb_documents_read on public.kb_documents for select to authenticated using (true);
drop policy if exists kb_chunks_read on public.kb_chunks;
create policy kb_chunks_read on public.kb_chunks for select to authenticated using (true);

-- Vector search used by the gateway.
create or replace function public.match_kb_chunks(
  query_embedding vector(1024),
  match_domain text default null,
  match_count int default 6,
  min_similarity float default 0.25
)
returns table (
  content text,
  similarity float,
  source text,
  title text,
  url text
)
language sql
stable
security definer
set search_path = public
as $$
  select c.content,
         1 - (c.embedding <=> query_embedding) as similarity,
         d.source,
         d.title,
         d.url
  from public.kb_chunks c
  join public.kb_documents d on d.id = c.document_id
  where c.embedding is not null
    and (match_domain is null or d.domain = match_domain)
    and 1 - (c.embedding <=> query_embedding) > min_similarity
  order by c.embedding <=> query_embedding
  limit least(match_count, 20);
$$;

revoke all on function public.match_kb_chunks(vector, text, int, float) from public, anon;
grant execute on function public.match_kb_chunks(vector, text, int, float) to authenticated;

-- ---------------------------------------------------------------------
-- Generated plans
-- ---------------------------------------------------------------------

-- The plan the assistant writes for a user. Stored rather than regenerated so
-- the same day does not silently change under them, and so the sources behind
-- it stay attached to the version they actually saw.
create table if not exists public.meal_plans (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_date date not null,
  -- [{slot, name_ar, name_en, note_ar, note_en, portions:[{ar,en,amount_ar,amount_en,kcal}]}]
  meals jsonb not null,
  target_kcal int not null,
  rationale_ar text,
  rationale_en text,
  -- [{source, title, url}] — what the plan was grounded in.
  sources jsonb not null default '[]',
  model text,
  created_at timestamptz not null default now(),
  unique (user_id, plan_date)
);
create index if not exists meal_plans_user_idx on public.meal_plans (user_id, plan_date desc);

alter table public.meal_plans enable row level security;
drop policy if exists meal_plans_select_own on public.meal_plans;
create policy meal_plans_select_own on public.meal_plans for select using (auth.uid() = user_id);
drop policy if exists meal_plans_insert_own on public.meal_plans;
create policy meal_plans_insert_own on public.meal_plans for insert with check (auth.uid() = user_id);
drop policy if exists meal_plans_update_own on public.meal_plans;
create policy meal_plans_update_own on public.meal_plans for update using (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- Assistant audit trail
-- ---------------------------------------------------------------------

-- Every model call, including the ones refused for being out of scope. Needed
-- to answer "why did it say that", to spot drift, and to rate-limit.
create table if not exists public.ai_interactions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('chat', 'meal_analysis', 'plan')),
  in_scope boolean not null,
  refusal_reason text,
  question text,
  answer text,
  sources jsonb not null default '[]',
  model text,
  created_at timestamptz not null default now()
);
create index if not exists ai_interactions_user_idx on public.ai_interactions (user_id, created_at desc);

alter table public.ai_interactions enable row level security;
drop policy if exists ai_interactions_select_own on public.ai_interactions;
create policy ai_interactions_select_own on public.ai_interactions for select using (auth.uid() = user_id);
