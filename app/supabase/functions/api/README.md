# Qamar mobile API (`api` Edge Function)

Implements the internal mobile contract in `project/spec_mvp.txt` §29.6 on
Supabase Edge Functions. Model-backed work stays on `ai-gateway`; this function
owns identity helpers, CRUD domains, billing webhooks, privacy jobs, and founder
ops.

## Deploy

```sh
# after supabase link
supabase db push                                          # includes 0007_api_surface.sql
supabase functions deploy api
supabase secrets set REVENUECAT_WEBHOOK_SECRET=...        # optional
supabase secrets set VERIFY_PURCHASES=trust_client        # non-prod only
```

Create a **private** Storage bucket named `private-media` for meal/label uploads.

Grant founder access:

```sql
insert into public.founder_admins (user_id, role)
values ('<your-auth-user-uuid>', 'founder');
```

## Conventions (§29.7)

| Concern | Behavior |
|---|---|
| Envelope | Success `{ data, request_id }`; error `{ error: { code, message_key, retryable, field_errors? }, request_id }` |
| Auth | Bearer Supabase JWT; server derives `user_id` — never from the body |
| Idempotency | `Idempotency-Key` on confirm / redeem / billing sync / export / deletion |
| Guest | `GET /bootstrap`, `GET /config`, `GET /billing/offering`, `POST /auth/*`, `POST /webhooks/*` |

Base URL: `https://<ref>.supabase.co/functions/v1/api`

## Route map

### Bootstrap / identity
- `GET /bootstrap` — profile, entitlement, wallet, flags, quotas
- `GET /config` — signed config only
- `POST /auth/anonymous` · `/auth/exchange/{apple\|google\|facebook}` · `/auth/otp/start` · `/auth/otp/verify` · `/auth/link` · `/auth/merge`
- `GET\|DELETE /auth/sessions`

### Consent / profile / targets / guidance
- `GET /consents/current` · `POST /consents`
- `GET\|PATCH /profile`
- `POST /targets/calculate` · `POST /targets/new/confirm`
- `GET /guidance/sources/{id}` · `GET /guidance/why/{decision_id}`

### Meals / media
- `POST /media/upload-url`
- `POST /meal-drafts` · `/meal-drafts/{id}/parse` · `/clarify` · `/confirm`
- `GET\|PATCH\|DELETE /meals/{id}`

### Food
- `GET /foods/search?q=` · `/foods/{id}` · `/foods/recent`
- `GET /barcodes/{gtin}` (Open Food Facts + cache)
- `POST /product-label-drafts` · `/product-label-drafts/{id}/confirm`
- `POST /food-corrections`

### Plan / progress / insights
- `GET\|POST /plans` · `POST /plans/{id}/substitute` · `/adjust` · `/mark-eaten`
- `GET /progress` · `GET\|POST\|PATCH\|DELETE /progress/weight` (also `/weight`)
- `GET\|POST /insights` · `POST /insights/{id}/action`

### Chat / memory
- `POST /chat/responses` (proxies grounded reply via `ai-gateway`)
- `POST /chat/{id}/stop` · `POST /messages/{id}/report`
- `POST /actions/{id}/confirm`
- `GET /memory` · `POST /memory/proposals/{id}/confirm` · `PATCH\|DELETE /memory/{id}`

### Journey / wallet
- `GET /journey` · `GET /quests` · `POST /quests/{id}/replace\|skip`
- `GET /achievements` · `POST /cosmetics/{id}/equip`
- `GET /wallet` · `/wallet/catalog` · `POST /wallet/redeem` (no client credit)

### Billing / promo / webhooks
- `GET /billing/offering` · `/billing/entitlement`
- `POST /promo/validate` · `/billing/sync` · `/billing/restore`
- `POST /webhooks/{revenuecat\|apple\|google}`

### Notifications / privacy / analytics
- `POST\|DELETE /devices` · `GET\|PATCH /reminders` · `POST /reminders/test`
- `POST /exports` · `GET /exports/{id}` · `DELETE /conversations/{id}` · `POST /account-deletion`
- `POST /events/batch` · `POST /feedback` · `GET /support-code`

### Founder ops (requires `founder_admins` row)
- `GET\|PATCH /admin/config`
- `GET /admin/nutrition-sources` · `/corrections` · `/safety` · `/billing` · `/usage` · `/evals`
- `GET\|PATCH /admin/provider-routing` · `GET /admin/target-policies`

## Flutter client

`lib/services/api_client.dart` — `QamarApiClient`. Enable with:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=... \
  # optional override:
  --dart-define=QAMAR_API_URL=https://xxx.supabase.co/functions/v1/api
```

## Related

- AI routes: `../ai-gateway/`
- Schema: `../../migrations/0007_api_surface.sql`
- Deploy notes: `../../../DEPLOY.md`
