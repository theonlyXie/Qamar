# Deploying the backend

Two things ship outside the app: the SQL migrations and the `ai-gateway` Edge
Function. Both need credentials that only the project owner has — a Supabase
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

`0001`–`0003` are already live. `0004` (the 100-point signup bonus) and `0005`
(the knowledge base, meal plans and AI audit log) are not.

The quickest path is the SQL editor in the dashboard: open each file, paste,
run, in order. Both are idempotent — `create table if not exists`, `create or
replace function` — so re-running one is harmless.

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
-- expect 1 row (the 100-point signup bonus)
```

`0004` also backfills the bonus for users who already exist, so the wallet on
your test account should jump to 100 the moment it runs.

## 2. Set the function's secrets

The gateway reads these at runtime. They never enter the repository, and never
go through chat.

```sh
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase secrets set VOYAGE_API_KEY=pa-...        # or OPENAI_API_KEY for embeddings
supabase secrets set USDA_API_KEY=...             # free from api.data.gov, and worth it
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically —
do not set them yourself.

## 3. Deploy the function

```sh
supabase functions deploy ai-gateway
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
