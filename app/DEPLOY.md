# Deploying the backend

Two things ship outside the app: the SQL migrations and the `ai-gateway` Edge
Function. Both need credentials that only the project owner has — a Supabase
personal access token, or the database password — so they are run from your
machine rather than from a build agent.

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

## 2. Set the function's secrets

The gateway reads these at runtime. They never enter the repository, and never
go through chat.

```sh
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase secrets set VOYAGE_API_KEY=pa-...        # or OPENAI_API_KEY for embeddings
supabase secrets set USDA_API_KEY=...             # optional, improves whole-food figures
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

`supabase/functions/ai-gateway/ingest.ts` chunks and embeds documents into
`kb_chunks`. It needs actual nutrition and training sources: national dietary
guidelines, protein and energy requirements, training principles. Quality here
sets the ceiling on every answer the app ever gives.

## 5. Turn the assistant on in the app

Only once the function answers. Adding this define while the function is a 404
turns honest "not connected yet" messages into network errors.

```sh
flutter build apk --release --split-per-abi \
  --dart-define=SUPABASE_URL=https://stqirjlqzchcoeegumoq.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key> \
  --dart-define=AI_GATEWAY_URL=https://stqirjlqzchcoeegumoq.supabase.co/functions/v1/ai-gateway
```
