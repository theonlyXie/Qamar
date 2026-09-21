# Qamar AI gateway

The app never holds a model key. It calls this with the user's Supabase JWT;
this decides whether the question may be answered at all, gathers evidence,
calls the model, and records what happened.

```
POST /ai-gateway/chat/reply     { message, lang, imageBase64?, imageMediaType? }   # a photo (a menu) is metered as a photo
POST /ai-gateway/meal/analyze   { inputType, text?, mediaPath?, lang? }
POST /ai-gateway/plan/generate  { date?, lang? }
```

## Deploy

```bash
supabase functions deploy ai-gateway --project-ref <ref>

supabase secrets set ANTHROPIC_API_KEY=sk-ant-...   # required
supabase secrets set VOYAGE_API_KEY=pa-...          # required for retrieval
# supabase secrets set OPENAI_API_KEY=sk-...        # alternative to Voyage
# supabase secrets set USDA_API_KEY=...             # optional, better whole-food data
# supabase secrets set QAMAR_MODEL=claude-sonnet-5  # optional
```

Then point the app at it:

```bash
flutter run --dart-define=AI_GATEWAY_URL=https://<ref>.supabase.co/functions/v1/ai-gateway
```

## The night plan, and the night sentence

At 22:00 Cairo the gateway writes tomorrow's plan for every Qamar+ member who
does not have one yet, then for every free-tier account that logged today, and
with each plan **one sentence about tomorrow** (`night_notes`, migration
`0048`): tomorrow against today, no dish named. The phone shows the sentence
next morning; a member taps through to the plan, the free tier finds the plan
locked — the blueprint's "tomorrow as the wall". `/plan/generate` refuses a
future date to a free account (403, `reason: tomorrow_locked`), and the
`meal_plans` policy in `0048` hides future rows from them the same way.

`POST /plan/nightly` is called by pg_cron (migration `0044_nightly_plan_cron.sql`)
with a shared secret, not a user token, and does nothing outside the
22:00–23:59 Cairo window unless the body says `{"force": true}` for a manual
run. It never spends anyone's own plan bucket; members come first, and anyone
who already has tomorrow's plan is skipped (but still gets the sentence if it
is missing).

Three secrets, once:

```bash
supabase secrets set QAMAR_CRON_SECRET=<long random>
```

and in SQL (Vault, so nothing sits in a migration):

```sql
select vault.create_secret('https://<ref>.supabase.co/functions/v1/ai-gateway', 'qamar_gateway_url');
select vault.create_secret('<anon key>',    'qamar_anon_key');
select vault.create_secret('<long random>', 'qamar_cron_secret');  -- the same value as above
```

Until all three exist the job logs a notice and does nothing. The run
returns a report (`plus`, `lite`, `written`, `noted`, `skipped`, `failed`,
`remaining`, and each failure's reason); `remaining > 0` means the second cron slot an hour later
picks up the rest, or the user base has outgrown one slot and
`0044` needs more.

## The three rules this enforces

**1. Nutrition and training only.** `scope.ts` classifies every question
*before* the model is called, so an out-of-scope question costs nothing and
cannot be argued around by the question itself. It refuses six ways — medical,
disordered eating, pregnancy, minors, off-topic, and attempts to rewrite the
assistant's job — each with real copy in Arabic and English rather than a bare
"I can't". Refusal checks run before the topic match, so "what should I eat
while pregnant" refuses on pregnancy rather than passing as a food question.

**2. Grounded or silent.** The model answers from retrieved passages plus
looked-up food data. If retrieval returns nothing, the endpoint refuses rather
than letting the model answer from memory — that is the rule that stops this
becoming a general chatbot the moment the knowledge base is thin.

**3. Numbers come from databases, not the model.** Food figures are looked up
in USDA FoodData Central and Open Food Facts and handed to the model as
per-100g facts to divide. Anything unresolved is marked low confidence so the
user can see which numbers are measured and which are estimates.

Eligibility is re-checked here too: a blocked or under-18 profile is refused at
the gateway, so calling the API directly does not get around what the app shows.

## The knowledge base is empty until you fill it

`kb_documents` / `kb_chunks` (migration 0005) hold the guidance the assistant
reasons from. **Until they have content, every chat call refuses with
`no_grounding`** — by design, not a bug.

To ingest: chunk each source to roughly 500–800 tokens, embed with the same
model as `EMBEDDING_MODEL` (default `voyage-3`, 1024 dims — it must match
`kb_chunks.embedding`), and insert with the service role. Sensible starting
sources, licence permitting:

| Domain | Source |
|---|---|
| nutrition | WHO healthy-diet guidance, EFSA dietary reference values |
| nutrition | NIH Office of Dietary Supplements fact sheets |
| nutrition | Egyptian food composition tables (for local dishes) |
| training | ACSM physical-activity guidelines, WHO activity guidelines |

Check each licence before storing text verbatim; `kb_documents.licence` is
there to record what you may quote.

## Costs and limits, before this goes live

Nothing here rate-limits per user yet. `ai_interactions` records every call and
is the table to meter against. Decide a per-day cap before launch, or a single
user can run up the model bill on your behalf.
