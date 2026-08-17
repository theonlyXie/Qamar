# Deploying the backend

Two things ship outside the app: the SQL migrations, the `ai-gateway` Edge
Function, and the `billing` Edge Function (Paymob). All of them need credentials that only the project owner has — a Supabase
personal access token, or the database password — so they are run from your
machine rather than from a build agent.

## 0. Two things that will bite you

**The `vector` extension.** `0005` opens with `create extension if not exists
vector`. In the dashboard SQL editor this works, because that runs as
`postgres`. Running the file through a connection pooler as a lesser role will
fail on that first line and take the rest of the file with it.

**1024 dimensions, and never mix providers.** `kb_chunks.embedding` is declared
`vector(1024)`. Voyage's `voyage-3` produces 1024 natively; OpenAI's
`text-embedding-3-small` is asked for 1024 explicitly in `ingest.ts`. Pick one
provider and stay on it. Embeddings from two different models are not
comparable — retrieval will still return rows, ranked by nothing meaningful,
and the app will quietly answer from the wrong passages. Re-ingesting from
scratch is the only fix.

## 1. Apply the migrations

`0001`–`0038` live in `supabase/migrations/`. Version numbers are unique: the
Paymob, pricing, and micronutrient files that once shared `0031`–`0033` were
renamed to `0033`–`0037` so `supabase db push` cannot skip a file. `0038` is
the MVP closeout (server Su awards, daily quest, Plus helper, wipe, reports).

If a live database already applied a file under an old duplicate name, the new
filename is a new version — objects use `IF NOT EXISTS` / `create or replace`
so re-applying the SQL is safe. Do not skip `0006`.

The quickest path is the SQL editor in the dashboard: open each file, paste,
run, in order. They are idempotent — `create table if not exists`, `create or
replace function`, and every `create policy` is preceded by a `drop policy if
exists` — so re-running one is harmless.

Run them in order and do not skip `0006`: `0004` alone leaves a signup bonus
that looks installed and never pays out. See the header of `0006` for why.

With the CLI instead:

```sh
supabase login                       # opens a browser
supabase link --project-ref stqirjlqzchcoeegumoq
supabase db push
```

`db push` applies everything in `supabase/migrations/` that the project has not
seen, tracked in `supabase_migrations.schema_migrations`.

Check it landed:

```sql
select table_name from information_schema.tables
where table_schema = 'public'
  and table_name in ('kb_documents','kb_chunks','meal_plans','ai_interactions');
-- expect 4 rows

select tgname from pg_trigger where tgname = 'qamar_on_auth_user_created';
-- expect 1 row (the 2,500-point signup bonus)
```

The trigger existing is not evidence the bonus works — that was exactly the
`0004` failure. Check the payout itself, which is what `0006` fixed:

```sql
select count(*) from public.su_point_ledger where reason = 'signup_bonus';
-- expect one row per user; zero means the credit is being refused and
-- swallowed, and the warning is in the Postgres logs
```

`0006` also backfills the bonus for users who already exist, so the wallet on
your test account should jump to 2,500 the moment it runs.

## 2. Set the function's secrets

The gateway reads these at runtime. They never enter the repository, and never
go through chat.

```sh
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase secrets set VOYAGE_API_KEY=pa-...        # or OPENAI_API_KEY for embeddings
supabase secrets set USDA_API_KEY=...             # free from api.data.gov, and worth it
supabase secrets set PAYMOB_SECRET_KEY=...        # Paymob dashboard — never the phone
supabase secrets set PAYMOB_PUBLIC_KEY=...
supabase secrets set PAYMOB_HMAC_SECRET=...
supabase secrets set PAYMOB_INTEGRATION_IDS=123,456
```

Paymob in plain language: `PAYMOB.md`. `billing` is deployed with `--no-verify-jwt`
because Paymob’s webhook cannot send a Supabase token; checkout still checks
the user’s JWT itself.

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically —
do not set them yourself.

## 3. Deploy the function

```sh
supabase functions deploy ai-gateway
supabase functions deploy billing --no-verify-jwt
```

`ai-gateway` is already deployed and ACTIVE (`verify_jwt` on), and answers an
unauthenticated call with 401. It has no secrets yet, so every route that
reaches the model returns 500 until section 2 is done.

That first deploy went up through the Supabase MCP connector, which uploads
file contents rather than a directory, so run the command above once from a
checkout when convenient. It republishes straight from `supabase/functions/`
and makes the deployed bundle provably identical to the repository.

**The running version is that first deploy, and it is now well behind the
repository.** The food resolver, the safety recording, the self-harm and
severe-symptom guards, the evidence packets and the verifier are all in
`supabase/functions/` and none of them are live until the command above is run.
The function is seven files bigger than the deployed one (`graph.ts`,
`safety.ts`, `packet.ts`, `verify.ts` and their tests), which is the other
reason to deploy from a checkout rather than file by file.

Before deploying, from `supabase/functions/ai-gateway/`:

```sh
deno check index.ts     # types
deno test               # scope, packet, verifier, plus gate, barcode scale
```

Verify it is up. A 401 is the correct answer to an unauthenticated call — it
means the function is running and rejecting you, which is what you want. A 404
means it is not deployed.

```sh
curl -i -X POST \
  https://stqirjlqzchcoeegumoq.supabase.co/functions/v1/ai-gateway/chat/reply \
  -H 'Content-Type: application/json' -d '{}'
```

## 4. Fill the knowledge base

The assistant answers only from retrieved sources and refuses when there are
none, so an empty knowledge base means it refuses everything. That is the
grounding rule working, not a bug — but it does mean the app is not usable
until real guidance is loaded.

A seed corpus lives in `supabase/knowledge/` — ten documents covering WHO's
quantitative targets, energy and protein requirements, safe rates of weight
change, Egyptian dishes as ingredient recipes, household portions, eating
culture, Ramadan, heat and hydration, training basics, and the safety boundary.

```sh
cd supabase/knowledge
deno run --allow-read --allow-write build_sources.ts
cd ../..
deno run --allow-net --allow-env --allow-read \
  supabase/functions/ai-gateway/ingest.ts supabase/knowledge/sources.json
```

Then rebuild the vector index, which the ingest script reminds you about:

```sql
reindex index kb_chunks_embedding_idx;
```

Check the corpus is really in there:

```sql
select d.title, count(c.id) as chunks
from kb_documents d left join kb_chunks c on c.document_id = d.id
group by d.title order by d.title;
-- expect 10 documents, every one with chunks > 0

select count(*) from kb_chunks where embedding is null;
-- expect 0 — a chunk with no embedding is invisible to retrieval
```

Read `supabase/knowledge/README.md` before adding to it. The short version:
guidance and structure belong in the corpus, per-dish calorie numbers do not —
those come from USDA and Open Food Facts at query time, so every figure the app
shows is traceable to a laboratory analysis rather than to a blog post.

## 5. Turn the assistant on in the app

Only once the function answers. Adding this define while the function is a 404
turns honest "not connected yet" messages into network errors.

```sh
flutter build apk --release --split-per-abi \
  --dart-define=SUPABASE_URL=https://stqirjlqzchcoeegumoq.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key> \
  --dart-define=AI_GATEWAY_URL=https://stqirjlqzchcoeegumoq.supabase.co/functions/v1/ai-gateway
```

## 6. End-to-end check

With the function deployed and the corpus ingested, ask it something it should
be able to ground, using a real user's token rather than the anon key:

```sh
curl -s -X POST \
  https://stqirjlqzchcoeegumoq.supabase.co/functions/v1/ai-gateway/chat/reply \
  -H "Authorization: Bearer <a signed-in user's access token>" \
  -H 'Content-Type: application/json' \
  -d '{"message":"how much protein should I eat","lang":"en"}'
```

What the answers mean:

- **A grounded reply with `[1]` citations** — everything works.
- **`"refused": true, "reason": "no_grounding"`** — the function is up but
  retrieval found nothing. The corpus is not ingested, or it was embedded with
  a different model than the gateway queries with.
- **`401`** — the token is wrong or expired, not a deployment problem.
- **`500`** — check `supabase functions logs ai-gateway`; almost always a
  missing secret.
- **`404`** — not deployed.

Then rebuild the APK with `AI_GATEWAY_URL` set, per the README.

## 6b. The safety log

Every refusal, escalation and hard block is now recorded. Three views answer
the questions worth asking:

```sql
select * from public.safety_rule_activity;  -- which rules fire, and when last
select * from public.safety_daily;          -- tier mix per day, with a denominator
select * from public.clinician_queue;       -- what is waiting on a human
```

All nine rules now have detection behind them. Five are keyword sets in
`scope.ts` — `self_harm`, `severe_symptom`, `medical_question`,
`eating_disorder`, `minor`, `pregnancy_declared` and `prompt_injection` — and
two are database triggers, so they fire on a weight or a lab arriving from any
path, not only from the app:

- `rapid_weight_change` — trigger on `weight_entries`: 5% of body weight inside
  30 days, needing at least three measurements over at least 14 days, debounced
  to one review a week.
- `critical_lab` — trigger on `user_labs`, on `critical_low` / `critical_high`.

Four rules escalate rather than merely refusing, so they queue a clinician
review: `self_harm` and `severe_symptom` as urgent, `eating_disorder` and
`rapid_weight_change` as routine. **Check `clinician_queue` has an owner before
relying on any of that** — an urgent row ageing in that queue is the exact
failure the escalation design exists to prevent.

A rule at zero is either never triggered or quietly broken, and from inside the
application those look identical. `safety_rule_activity` is where the
difference becomes visible, so it is worth reading after the first week of real
traffic rather than assuming silence means safety.

These views are staff surfaces. `0023` revoked them from `anon` and
`authenticated`, so they are reachable with the service role or from the SQL
editor, and not through the app's API.

## 6c. The evidence trail and what it costs

Every request now writes an `evidence_packets` row — the facts about the person
that were in play, what the food resolver made of each phrase and how sure it
was, the target, which curated rules applied and which were excluded and why,
and the claims the answer made in a form something could later check.

```sql
-- The last few answers, and what each of them stood on
select created_at, kind, jsonb_array_length(food_facts) as foods,
       jsonb_array_length(claims_to_verify) as claims, uncertainty
from public.evidence_packets order by created_at desc limit 20;

select * from public.ai_cost_daily;           -- spend and latency per stage
select * from public.stage_budget_pressure;   -- stages running over their 0015 ceiling
```

`cost_usd` is computed on insert by a trigger from `model_prices`, not by the
gateway. **If a price changes, update `model_prices` — do not redeploy the
function.** A model with no row there records its tokens and leaves `cost_usd`
null, which reads as "unpriced", not "free":

```sql
insert into public.model_prices
  (model, effective_from, input_usd_per_mtok, output_usd_per_mtok, cached_input_usd_per_mtok, note)
values ('some-new-model', current_date, 3.0, 15.0, 0.3, 'list')
on conflict (model, effective_from) do nothing;
```

The seeded prices are published list rates entered by hand and are a budgeting
estimate, not an invoice. Reconcile against the provider's own billing before
anyone makes a decision on them.

`applicable_rules` is empty on every packet because `clinical_rules` is empty —
no rule has been curated, which is different from the population filter
rejecting them all.

## 6d. The verifier

Every answer is now checked before it goes out, and the check is arithmetic, not
a second model. Nothing here is anyone's opinion: each finding recomputes a
number from figures already in the packet, which is why `verifier_results.model`
is null on every row.

```sql
select * from public.verifier_activity;    -- verdicts per day and per pass
select * from public.verifier_failures;    -- what is actually failing, commonest first
select * from public.verifier_revisions;   -- whether the correction round earns its cost
```

What each route can honestly check:

| Route | Checked | Not checked |
|---|---|---|
| `plan` | meal totals against the target, every portion has a kcal, alternatives near their meal, **and no restricted food in the output** | — |
| `meal/analyze` | macros reconcile with kcal at 4/4/9, kcal plausible | restrictions: the user is reporting what they ate, not being offered it |
| `chat/reply` | a restricted food is *mentioned* — advisory only | the numbers, because prose does not attach them to a resolved food |
| `scan/read` | nothing | re-reading the image needs another vision call, which is the trap this avoids. The plausibility filter in the route is the whole check |

Three verdicts, and they do different things:

- **PASS** — the response carries `verification.verified: true`.
- **REVISE** — one bounded correction. The model is re-asked with the specific
  failures and its own previous answer, and the new version is accepted **only
  if it has strictly fewer failures**. A meal-photo revision drops the image and
  uses the text prompt, because fixing a sum needs no picture.
- **ESCALATE** — either a safety failure, or a revision that did not land. The
  cap is enforced by the `unique (task_id, revision_number)` constraint from
  `0015`, not by the gateway remembering.

**An ESCALATE does not always block.** A day of food still 9% off target is
returned with `verification.verified: false` and the recomputed total attached —
withholding someone's meals over an energy sum would be worse for them than
showing it with the correction. What is never returned is a plan naming a food
the person has recorded as an allergy: that is refused with 409, written to
`safety_events` as a `hard_block`, and not re-asked for, because the model has
already been told once and a second round of the same model is not a control.

That last check is the one that is not redundant with anything upstream. The
route already removes restricted foods from the list the model is *shown*;
nothing stops it naming one that was never on that list.

## 6e. The eval suite

52 frozen cases. Every tolerance in this system — the 0.35 fuzzy-match floor,
the verifier's 20% Atwater band, the 5% plan target — was a number chosen with
no way to tell whether it was right. This is what makes them measurable.

Half runs in the database with **no API key at all**:

```sql
select public.qamar_run_eval('before the deploy');   -- returns a run id
select * from public.eval_latest limit 5;            -- pass rate per run
select * from public.eval_failures;                  -- what broke, with detail
select * from public.eval_coverage;                  -- which families have cases
```

The other half is pure TypeScript — the scope guard and the verifier — and runs
from a checkout, writing into the same tables so there is one pass rate:

```sh
cd supabase/functions/ai-gateway
SUPABASE_URL=https://stqirjlqzchcoeegumoq.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=... \
  deno run --allow-net --allow-env eval.ts "pre-release"
```

It exits non-zero on any failure, so it can gate a deploy. Nothing in it calls a
model, so it costs nothing and gives the same answer every time.

**The first run found a real bug, which is the argument for having it.** "ملوخية"
resolved to the raw leaf rather than the cooked dish — someone logging a bowl
would have been priced against a leafy green. Underneath it, the resolver's
ordering was not a total order at all, so the same phrase could resolve
differently between two runs. `0027`–`0029` are the three fixes that forced,
and the suite went 32/33 → 36/36 across them.

**Four families are deliberately empty**: `evidence_grounding`,
`meal_optimization`, `longitudinal_adaptation` and `cost_tokens` need a deployed
gateway and an ingested corpus. Seeding cases nothing can run would teach
everyone to ignore the failures. `eval_coverage` shows the gap on purpose.

## 7. Sign-in: what is actually switched on

Anonymous sign-in works today, and it is the only path that does. Everything
below is a dashboard job. Check the live answer at any time with:

```sh
curl -s https://stqirjlqzchcoeegumoq.supabase.co/auth/v1/settings \
  -H 'apikey: <publishable key>'
```

**Email needs an SMTP provider.** `email` is enabled, but the project is still
on Supabase's built-in sender, which only delivers to project team members and
allows a couple of messages an hour. A real signup gets
`429 over_email_send_rate_limit`, or a confirmation mail that never arrives.
Set a custom SMTP provider under **Authentication → Emails → SMTP Settings**
before treating email signup as working.

`mailer_autoconfirm` is off, so a new account cannot sign in until it has
confirmed. That is the right setting for production, but it means SMTP is a
hard dependency and not a nicety.

**Google, Apple and Facebook are all `false`.** The app ships the buttons and
`SOCIAL_SIGNIN.md` has the per-provider steps, but until the credentials are
pasted in, every one of them reports "not switched on yet on the server".

**A note on the address validator.** Supabase rejects addresses whose domain
has no MX record — `example.com` and unrouted vanity domains come back as
`email_address_invalid`. That is the validator, not the signup flow, so do not
use such an address to test whether signup works.
