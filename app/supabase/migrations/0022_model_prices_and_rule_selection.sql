-- What a call cost, and which rules were considered.
--
-- 0015 built ai_stage_costs with a cost_usd column and no way to fill it, and
-- evidence_packets with applicable_rules / excluded_rules and no way to decide
-- what belongs in either. Both gaps are the same shape: the edge function knows
-- the raw facts (tokens, model, the person) but not the policy (what a token
-- costs, which rules are in population). Policy belongs in the database, the
-- way red_flag_rules already holds escalation policy rather than TypeScript.
--
-- The alternative was a price table compiled into the gateway. Prices change,
-- gateways get redeployed on their own schedule, and a stale constant produces
-- a number that looks authoritative and is wrong. Here a correction is one
-- UPDATE, and past rows can be recomputed because the inputs are kept.

-- ---------------------------------------------------------------------
-- Model prices
-- ---------------------------------------------------------------------

create table if not exists public.model_prices (
  model text not null,
  -- Dated rather than versioned: introductory pricing and list pricing are the
  -- same model at different times, and a cost written last month must not be
  -- re-derived at this month's rate.
  effective_from date not null,
  input_usd_per_mtok numeric(10,4) not null,
  output_usd_per_mtok numeric(10,4) not null,
  -- Cache reads bill at a fraction of input. Null falls back to the input rate,
  -- which over-states rather than under-states.
  cached_input_usd_per_mtok numeric(10,4),
  note text,
  recorded_at timestamptz not null default now(),
  primary key (model, effective_from)
);

comment on table public.model_prices is
  'Published list prices, entered by hand. This is a billing estimate for '
  'budget control, not an invoice — the authority on what was actually charged '
  'is the provider''s own billing.';

alter table public.model_prices enable row level security;
-- Operational. Nothing in the app needs to read what a call cost us.

insert into public.model_prices
  (model, effective_from, input_usd_per_mtok, output_usd_per_mtok, cached_input_usd_per_mtok, note)
values
  ('claude-opus-5',      date '2026-01-01', 5.0000, 25.0000, 0.5000, 'list'),
  ('claude-opus-4-8',    date '2026-01-01', 5.0000, 25.0000, 0.5000, 'list'),
  ('claude-opus-4-7',    date '2026-01-01', 5.0000, 25.0000, 0.5000, 'list'),
  ('claude-opus-4-6',    date '2026-01-01', 5.0000, 25.0000, 0.5000, 'list'),
  ('claude-fable-5',     date '2026-01-01', 10.0000, 50.0000, 1.0000, 'list'),
  ('claude-sonnet-4-6',  date '2026-01-01', 3.0000, 15.0000, 0.3000, 'list'),
  ('claude-haiku-4-5',   date '2026-01-01', 1.0000, 5.0000, 0.1000, 'list'),
  -- Sonnet 5 is the gateway default, and it is the one model here whose price
  -- is known to change on a date. Both rows are seeded now so the change does
  -- not depend on anyone remembering.
  ('claude-sonnet-5',    date '2026-01-01', 2.0000, 10.0000, 0.2000, 'introductory, through 2026-08-31'),
  ('claude-sonnet-5',    date '2026-09-01', 3.0000, 15.0000, 0.3000, 'list')
on conflict (model, effective_from) do nothing;

create or replace function public.qamar_model_price(
  p_model text,
  p_at timestamptz default now()
) returns public.model_prices
language sql
stable
set search_path = public
as $$
  select p.*
  from public.model_prices p
  where p.model = p_model
    and p.effective_from <= (p_at at time zone 'UTC')::date
  order by p.effective_from desc
  limit 1;
$$;

create or replace function public.qamar_token_cost(
  p_model text,
  p_input_tokens int,
  p_output_tokens int,
  p_cached_input_tokens int default 0,
  p_at timestamptz default now()
) returns numeric
language plpgsql
stable
set search_path = public
as $$
declare
  pr public.model_prices;
begin
  if p_model is null then
    return null;
  end if;
  select * into pr from public.qamar_model_price(p_model, p_at);
  -- An unpriced model returns null, not zero. "We do not know what this cost"
  -- and "this was free" are different facts and must not collapse into one.
  if pr.model is null then
    return null;
  end if;

  return round((
      coalesce(p_input_tokens, 0)::numeric  * pr.input_usd_per_mtok
    + coalesce(p_output_tokens, 0)::numeric * pr.output_usd_per_mtok
    + coalesce(p_cached_input_tokens, 0)::numeric
        * coalesce(pr.cached_input_usd_per_mtok, pr.input_usd_per_mtok)
  ) / 1000000.0, 6);
end;
$$;

comment on function public.qamar_token_cost is
  'Anthropic reports cache reads separately from input_tokens, so the three '
  'counts are additive and none of them double-counts another.';

-- Costing happens on write, from the row's own model and timestamp. Doing it
-- in a trigger means every path that inserts a cost row gets it — the gateway
-- today, a batch job or a backfill tomorrow — rather than whichever caller
-- remembered.
create or replace function public.qamar_price_stage_cost()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.cost_usd is null then
    new.cost_usd := public.qamar_token_cost(
      new.model, new.input_tokens, new.output_tokens, new.cached_input_tokens,
      coalesce(new.created_at, now()));
  end if;
  return new;
exception
  -- A pricing failure must not lose the token counts, which are the part that
  -- cannot be reconstructed later.
  when others then
    raise warning 'qamar_price_stage_cost failed: %', sqlerrm;
    return new;
end;
$$;

drop trigger if exists ai_stage_costs_price on public.ai_stage_costs;
create trigger ai_stage_costs_price
  before insert on public.ai_stage_costs
  for each row execute function public.qamar_price_stage_cost();

-- ---------------------------------------------------------------------
-- Spend, in the shape somebody asks about it
-- ---------------------------------------------------------------------

create or replace view public.ai_cost_daily
with (security_invoker = true) as
select
  created_at::date as day,
  stage,
  model,
  count(*) as calls,
  sum(input_tokens) as input_tokens,
  sum(output_tokens) as output_tokens,
  sum(cached_input_tokens) as cached_input_tokens,
  sum(external_api_calls) as external_api_calls,
  round(sum(cost_usd), 4) as cost_usd,
  round(avg(latency_ms)) as avg_latency_ms,
  max(latency_ms) as max_latency_ms
from public.ai_stage_costs
group by created_at::date, stage, model
order by day desc, stage;

-- Where a stage is running over the ceiling 0015 declared for it. A budget
-- nobody compares against is a comment.
create or replace view public.stage_budget_pressure
with (security_invoker = true) as
select
  b.stage,
  b.max_input_tokens,
  b.max_output_tokens,
  b.max_external_calls,
  count(c.id) as calls_7d,
  round(avg(c.input_tokens)) as avg_input_tokens,
  round(avg(c.output_tokens)) as avg_output_tokens,
  count(c.id) filter (
    where b.max_input_tokens is not null and c.input_tokens > b.max_input_tokens
  ) as over_input_budget,
  count(c.id) filter (
    where b.max_output_tokens is not null and c.output_tokens > b.max_output_tokens
  ) as over_output_budget,
  count(c.id) filter (
    where b.max_external_calls is not null and c.external_api_calls > b.max_external_calls
  ) as over_external_budget
from public.stage_budgets b
left join public.ai_stage_costs c
  on c.stage = b.stage and c.created_at > now() - interval '7 days'
group by b.stage, b.max_input_tokens, b.max_output_tokens, b.max_external_calls
order by b.stage;

-- ---------------------------------------------------------------------
-- Rule selection
-- ---------------------------------------------------------------------
-- qamar_rule_applies (0011) answers the question for one rule. The packet needs
-- the whole partition: what applied, what did not, and why not. Returning both
-- halves from one call is what makes excluded_rules cost nothing to populate —
-- and a reason nobody had to write twice.

create or replace function public.qamar_rule_selection(
  p_age_years numeric,
  p_sex text,
  p_life_stage text default 'any',
  p_condition text default 'general_wellness'
) returns table (
  rule_id uuid,
  applies boolean,
  compact_recommendation text,
  recommendation_type text,
  source_id text,
  source_version text,
  source_locator jsonb,
  reason_not_applicable text
)
language sql
stable
set search_path = public
as $$
  select
    r.rule_id,
    public.qamar_rule_applies(r, p_age_years, p_sex, p_life_stage, p_condition),
    r.compact_recommendation,
    r.recommendation_type,
    r.source_id,
    r.source_version,
    r.source_locator,
    nullif(concat_ws('; ',
      case when not (r.condition = 'general_wellness' or r.condition = p_condition)
        then 'rule is for condition ' || r.condition end,
      case when not (r.sex = 'any' or p_sex is null or r.sex = p_sex)
        then 'rule is for sex ' || r.sex end,
      case when not (r.life_stage = 'any' or p_life_stage is null or r.life_stage = p_life_stage)
        then 'rule is for life stage ' || r.life_stage end,
      case when r.min_age_years is not null and p_age_years is not null
             and p_age_years < r.min_age_years
        then 'minimum age ' || r.min_age_years end,
      case when r.max_age_years is not null and p_age_years is not null
             and p_age_years > r.max_age_years
        then 'maximum age ' || r.max_age_years end
    ), '')
  from public.clinical_rules r
  where r.is_active
    -- Only rules whose source may be used for advice. 0008 built that gate and
    -- retrieval is where it has to bite: a rule from a blocked source must
    -- never reach the reasoner, whatever its population.
    and public.qamar_source_usable_for_advice(r.source_id);
$$;

comment on function public.qamar_rule_selection is
  'Both halves of the population filter in one pass. Returns nothing while '
  'clinical_rules is empty, which is the honest answer — an empty '
  'applicable_rules array in a packet means no rule was curated yet, not that '
  'the filter rejected everything.';
