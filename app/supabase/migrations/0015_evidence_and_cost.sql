-- Evidence packets, verification, and what any of it cost.
--
-- ai_interactions records a question, an answer and a bag of sources. That is
-- enough to show someone what happened and not enough to show why. The packet
-- is the typed unit passed between workers, and persisting it is what makes a
-- past answer reconstructable.
--
-- excluded_rules looks like an odd thing to store until somebody asks why a
-- user never saw a rule that obviously applied to them. Then it is the only
-- answer, which is why it is a column and not an afterthought.

create table if not exists public.evidence_packets (
  task_id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users (id) on delete cascade,
  interaction_id uuid references public.ai_interactions (id) on delete set null,
  kind text not null check (kind in ('chat','meal_analysis','plan','body_scan')),

  -- [{field, value, unit, timestamp, confidence}]
  user_facts_used jsonb not null default '[]',
  -- [{qamar_food_id, quantity_g, nutrients, source_ids}]
  food_facts jsonb not null default '[]',
  -- [{metric, value_or_range, equation_version}]
  calculated_targets jsonb not null default '[]',
  -- [{rule_id, compact_recommendation, source_locator}]
  applicable_rules jsonb not null default '[]',
  -- [{rule_id, reason_not_applicable}]
  excluded_rules jsonb not null default '[]',

  candidate_decision jsonb,
  safety_flags text[] not null default '{}',
  uncertainty jsonb not null default '{}',
  claims_to_verify jsonb not null default '[]',

  created_at timestamptz not null default now()
);

create index if not exists evidence_packets_user_idx
  on public.evidence_packets (user_id, created_at desc);
create index if not exists evidence_packets_interaction_idx
  on public.evidence_packets (interaction_id);

create table if not exists public.verifier_results (
  id uuid primary key default uuid_generate_v4(),
  task_id uuid not null references public.evidence_packets (task_id) on delete cascade,
  verdict text not null check (verdict in ('PASS','REVISE','ESCALATE')),
  -- [{claim, failure_type, detail}] — machine readable, not prose.
  failures jsonb not null default '[]',
  recomputed jsonb not null default '{}',
  -- One bounded correction for routine tasks; unresolved contradictions
  -- escalate rather than starting an agent debate. This counter is where that
  -- limit is actually enforced.
  revision_number int not null default 0 check (revision_number >= 0 and revision_number <= 2),
  model text,
  created_at timestamptz not null default now(),
  unique (task_id, revision_number)
);

create index if not exists verifier_results_task_idx on public.verifier_results (task_id);
create index if not exists verifier_results_verdict_idx on public.verifier_results (verdict, created_at desc);

-- Per-stage cost. Without this the token-minimisation rules are unmeasurable,
-- and a budget you cannot measure is a wish.
create table if not exists public.ai_stage_costs (
  id uuid primary key default uuid_generate_v4(),
  task_id uuid references public.evidence_packets (task_id) on delete cascade,
  interaction_id uuid references public.ai_interactions (id) on delete set null,
  user_id uuid references auth.users (id) on delete set null,
  stage text not null check (stage in
    ('extractor','router','risk_triage','food_resolver','retrieval','requirement',
     'reasoner','optimizer','verifier','composer','adaptation','other')),
  model text,
  input_tokens int,
  output_tokens int,
  cached_input_tokens int,
  external_api_calls int not null default 0,
  cost_usd numeric(12,6),
  latency_ms int,
  created_at timestamptz not null default now()
);

create index if not exists ai_stage_costs_task_idx on public.ai_stage_costs (task_id);
create index if not exists ai_stage_costs_stage_idx on public.ai_stage_costs (stage, created_at desc);

-- Ceilings per stage. Exceeding one is a signal to route differently, not to
-- silently spend more.
create table if not exists public.stage_budgets (
  stage text primary key,
  max_input_tokens int,
  max_output_tokens int,
  max_cost_usd numeric(12,6),
  max_external_calls int,
  notes text
);

alter table public.evidence_packets enable row level security;
drop policy if exists evidence_packets_select_own on public.evidence_packets;
create policy evidence_packets_select_own on public.evidence_packets
  for select using (auth.uid() = user_id);

-- Verifier output, cost and budgets are operational. Server only.
alter table public.verifier_results enable row level security;
alter table public.ai_stage_costs enable row level security;
alter table public.stage_budgets enable row level security;

insert into public.stage_budgets (stage, max_input_tokens, max_output_tokens, max_external_calls, notes) values
('extractor', 4000, 600, 0, 'Small cheap model, schema-constrained JSON. Should never see conversation history.'),
('risk_triage', 2000, 200, 0, 'Rules first; model only on ambiguous high-risk cases.'),
('food_resolver', 4000, 800, 6, 'Local graph first. External calls are the fallback, not the default.'),
('retrieval', 3000, 400, 1, 'Metadata filter before vector search; 3-8 rules, not 50 chunks.'),
('reasoner', 12000, 1500, 0, 'Sees the evidence packet, never raw sources.'),
('optimizer', 2000, 400, 0, 'Solver, not free-form generation.'),
('verifier', 8000, 800, 0, 'Sees candidate claims and calculations only, not the original chat.'),
('composer', 6000, 800, 0, 'Verified packet in, user-facing answer out. No new facts.')
on conflict (stage) do nothing;
