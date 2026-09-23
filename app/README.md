# Qamar — Flutter app

This is the real implementation of `project/Qamar MVP.dc.html`, the Claude
Design prototype exported at the repo root (see `../README.md` and
`../chats/` for the design intent this was built from), built out per
`project/spec_mvp.txt`'s platform choice: **Flutter, Supabase backend**.

## Setup

The `android/`, `ios/`, and `web/` platform folders are committed (generated
by `flutter create`, which did not touch `lib/`). To run:

```bash
cd app
flutter pub get
flutter run
```

Verified against **Flutter 3.47.0 / Dart 3.13.0**: `flutter analyze` is
error-free, `flutter test` passes, and both `flutter build web` and
`flutter build apk --debug` succeed.

`NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` are set in
`ios/Runner/Info.plist`, and the Android manifest declares the camera as
optional hardware. No runtime `CAMERA` permission is declared on purpose:
`image_picker` goes through system intents, and declaring it would oblige us
to request it and would break devices that only have a gallery.

### The moon is drawn, not an asset

`lib/widgets/moon.dart` paints the moon as a lit sphere — spherical shading,
a true elliptical terminator, foreshortened craters, earthshine on the night
side — so it stays sharp at every size from the 34px chat avatar to the
welcome hero. `assets/images/qamar_orb*.png` are no longer referenced by the
app. [LivingOrb] still owns the breathing, halo, wander and spark motion; the
only motion inside the moon itself is a very slow phase drift.

### Fonts need network on first launch

`google_fonts` fetches Cormorant Garamond / Noto Sans Arabic / Inter from
`fonts.gstatic.com` at runtime rather than bundling them. On a device with
no network — or behind a filtered one — Arabic text renders as tofu boxes
while Latin text falls back cleanly. Since Arabic is the default locale,
consider vendoring the font files into `assets/fonts/` and declaring them
in `pubspec.yaml` before shipping.

## What's implemented

Everything in `project/Qamar MVP.dc.html` and its two chat transcripts,
rebuilt as real Flutter screens rather than copying the prototype's DOM:

- **State**: `lib/state/app_state.dart` is a line-for-line Dart port of the
  prototype's `Component` class — the onboarding NLU regex parsing, the
  Mifflin-St Jeor target formula, Su Points economy, confirm-before-write
  meal flow, all of it. It needs no network access; the app is fully
  demoable offline today.
- **Screens**: welcome (chat-direct / scan-InBody), InBody scan mock,
  conversational onboarding (chips/number-stepper/multi/free-text, age +
  safety gates, target card, save-progress prompt), Today, Log, Analyzing,
  Confirm, Plan, Progress, You, Su Points wallet (Spend/History), Why/Source
  sheet.
- **Ask Qamar**: companion overlay (`lib/widgets/ask_qamar_overlay.dart`) —
  backdrop blur, orb docked to the side, messages on a moonbeam.
- **Orb + tree nav**: `lib/widgets/living_orb.dart` (breathing/halo/wander/
  orbiting sparks), `lib/widgets/orb_nav.dart` (drag-anywhere, tap-to-open),
  `lib/widgets/tree_overlay.dart` (radial nav with animated branches).
- **i18n**: `lib/l10n/strings.dart` is the full AR/EN string table from the
  prototype; `main.dart` flips `Directionality` live. The `QLangToggle`
  control sits on the welcome screen, in the onboarding header, on the scan
  header and in You — the You row alone was unreachable until onboarding was
  finished, so a user who does not read Arabic had to complete an Arabic
  conversation before they could switch out of it. Switching mid-conversation
  keeps the answers already given and the current step.
- **System shortcut / Back Tap**: iPhone Settings → Accessibility → Touch →
  Back Tap can run **Ask Qamar** or **Log a meal with Qamar** (Siri Shortcuts).
  Android long-press on the icon exposes the same two shortcuts. Either one
  opens the moon listening immediately instead of walking the in-app menu.
  Deep links: `com.qamar.app://quick/ask` and `com.qamar.app://quick/log`.

## What's stubbed (backend/auth/AI/payments)

The user asked for a full production build per `spec_mvp.txt`'s stack
(Flutter + Supabase + external AI API + Apple/Google/Facebook auth +
store payments). I can't provision real Supabase projects, Apple/Google
developer accounts, or AI-provider keys on your behalf, so `lib/services/`
is a **typed integration seam** — real code, not wired into the UI, ready
for you to connect:

| File | What it is | To activate |
|---|---|---|
| `supabase/migrations/0001_core_schema.sql` | Full Postgres schema (profiles, consents, targets, meal_drafts/logs, wallet + ledger, quests, weight entries) with RLS, scoped to the MVP subset of spec_mvp.txt Part 28 | `supabase db push` (or run in the SQL editor) against a real project |
| `supabase/migrations/0035_water_logs.sql` | Drinking-water log: one row per glass (250 ml) or bottle (500 ml) | same |
| `supabase/migrations/0002_wallet_functions.sql` | Atomic, idempotent `qamar_wallet_credit` / `qamar_wallet_redeem` RPCs (ledger insert + balance update in one transaction) | same |
| `lib/services/repositories.dart` | Abstract `ProfileRepository` / `MealRepository` / `WaterRepository` / `WalletRepository` | — |
| `lib/services/supabase_repositories.dart` | Supabase-backed implementations of the above | Re-check each call against your pinned `supabase_flutter` version's query-builder API before use — it has shifted across majors |
| `lib/services/auth_service.dart` | Anonymous sign-in + Apple/Google identity-linking + email OTP, preserving the anonymous user id | Add `sign_in_with_apple` / `google_sign_in` packages and native config when you wire the sign-in buttons |
| `lib/services/ai_gateway.dart` | `MockAiGateway` (what the app uses today) + `HttpAiGateway` client for meal analysis / chat replies | Stand up a server endpoint (Edge Function or similar) that holds the OpenAI key server-side — **the client never holds a model API key**, per spec_mvp.txt §29.1 |
| `lib/services/payments.dart` | Paymob checkout for Qamar+ (EGP). Su Points are earned only — see `walletTerms` | Open a Paymob Egypt merchant account and follow `PAYMOB.md`. The phone never holds Paymob secrets. |
| `lib/services/config.dart` | `--dart-define` driven flags (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `AI_GATEWAY_URL`) | `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` |

**Wiring — done.** `AppState` now takes optional repositories plus a user id.
With none supplied (the default, and what every test uses) it behaves exactly
as before: entirely in memory, no network, fully demoable offline. Supplied,
the same methods additionally write through — the profile on each answered
onboarding step, the target when it is calculated, a meal as a draft plus a
log on confirm, and redemptions via the wallet RPC. No screen changed and no
method signature moved.

Two rules the wiring keeps:

- **A backend problem never costs the user anything.** Every write is
  fire-and-forget behind `_push`; the local change lands first and the screen
  moves on. Failures set `syncError` rather than being swallowed, and
  `main.dart` falls back to a fully offline `AppState` if Supabase cannot be
  reached or sign-in fails.
- **Su Points are never minted by the client.** `qamar_wallet_credit` is
  EXECUTE-revoked from `anon` and `authenticated`, so the client cannot award
  points even if it tried; `SupabaseWalletRepository.credit` throws to say so
  in a legible place. Balances shown locally reconcile to the server's number
  on the next hydrate. Awarding must move to an Edge Function using the
  service role once earning actions are verified server-side.

Run against the live project with:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key>
```

**Anonymous sign-in must be enabled first** (Authentication → Providers →
Anonymous). Until it is, the app starts, logs the reason, and runs offline.

## Explicitly out of scope here

`spec_mvp.txt` describes a full 30-day production build — App Store Server
API / Google Play Billing reconciliation, RevenueCat or native store-server
notifications, the Egyptian food RAG + pgvector knowledge base, USDA/Open
Food Facts/FatSecret integrations, the founder ops console, the safety
moderation classifier, and reminders/export/delete flows are all real
engineering projects in their own right and are not attempted here. The
data model migration is written so adding them later is additive, not a
rewrite.

## Known simplifications vs. the prototype

- CSS keyframe animations (`qbreath`, `qhalo`, `qfloat`, `qorbit`…) are
  reimplemented with Flutter `AnimationController`s tuned to the same
  durations/easing, not a byte-for-byte port — visually equivalent, not
  pixel-identical on every frame.
  - The weight-trend chart is a simplified `CustomPainter` polyline rather
    than the prototype's inline SVG, matching the same data points.
- The InBody scan screen opens the real device camera (or the photo library)
  via `image_picker` and shows the captured shot in the frame, but the
  *reading* of that photo is still the prototype's canned result — extracting
  real numbers needs the AI gateway. Camera failures (no camera, refused
  permission, unsupported platform) surface on screen and the typed path
  stays available, so a missing camera never dead-ends onboarding.
- The orb is the primary navigation and logging surface. Hold it to open the
  radial menu, sweep to a destination and release; choosing Log swaps the ring
  for its three input methods. All three act in place — speak starts the moon
  listening, type opens the conversation, photo opens the camera — so logging
  never pushes a page. Tapping still opens the menu the sticky way.
- The ring follows the *mangata*, the moon's road on water: one cool white
  light at varying strength rather than a colour per destination.
- The orb's data explanations (`lib/widgets/explain.dart`) are static copy
  keyed by metric, except planned meals, whose explanation is built from the
  meal's own portions. The interaction is real — drag the orb over a value and
  drop it — but the words are written, not generated. Once the AI gateway
  exists they become the fallback and the orb explains the number in the
  user's own context.

## Building a real APK

The app compiles its backend configuration in at build time. Without these
defines it runs entirely offline — no accounts, no persistence, no AI — which
looks like a working build until you try to sign in:

```sh
flutter build apk --release --split-per-abi \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key> \
  --dart-define=AI_GATEWAY_URL=https://<project>.supabase.co/functions/v1/ai-gateway
```

Leave `AI_GATEWAY_URL` out until the Edge Function is actually deployed. With
it set but nothing behind it, every AI call fails with a network error; with
it absent, the app says plainly that the assistant is not connected, which is
the truthful state.

### Analytics (PostHog), behind consent

Add `--dart-define=POSTHOG_API_KEY=<project token>` (and, if not EU,
`--dart-define=POSTHOG_HOST=https://us.i.posthog.com`) to turn analytics on.

**Invitation links.** The shared invitation carries `https://dr-qamar.com/i/<code>`;
the app also answers `qamar://i/<code>`. Opened before there is an account, the
code waits on the phone and is redeemed on the first connected start. For the
https link to open the app rather than the browser, the site must publish
`/.well-known/assetlinks.json` (Android, naming `com.qamar.app` and the signing
certificate's SHA-256) and `/.well-known/apple-app-site-association` (iOS,
team id + bundle id, path `/i/*`), and the Runner target needs the Associated
Domains capability attached in Xcode (`ios/Runner/Runner.entitlements`).

**A nutritionist's code** (O12, migration 0069) comes the same two ways: typed
in Me ("Your nutritionist's code"), or by `https://dr-qamar.com/p/<code>` /
`qamar://p/<code>`. It waits on the phone exactly as an invitation does, and
while it waits the seven-day week is not offered. `qamar_redeem_pro_code` puts
the professional on the account (`pro_code_claims`, which checkout reads when no
code is typed, so their 20% reaches them from the first payment) and, while the
account's one trial is unused, starts `billing_config.pro_trial_days` (14) with
`plus_trials.source = 'pro'`. Only a code the operator has confirmed starts the
trial: every account gets an affiliate code the first time Me loads, so without
the check anyone could hand out fourteen days. To confirm a professional:
`update promo_codes set professional = true where code = '<their code>';`. For
the https link to open the app, the site's `apple-app-site-association` must
list `/p/*` beside `/i/*` (the Android filter is in the manifest).

**Photos** are taken at one setting for the whole app (`lib/services/photos.dart`:
1280 px, JPEG quality 72, roughly 200 KB) and the cached shot is deleted once
its verdict is in. **Offline logging**: a meal, a glass or a walk that fails to
reach the server is kept on the phone (`pending_writes_<user>`) and replayed
when the app returns to the foreground, when the next write succeeds, or on the
next start — oldest first, stopping at the first failure; a write refused six
times is dropped and the reason shown.

**Shop this plan** appears on the Plan screen only when a grocery partner is
configured: `--dart-define=GROCERY_PARTNER_URL=<deep-link template>` (with
`{items}`, `{ref}` and `{lang}` placeholders, or a plain URL that receives
them as query parameters), `--dart-define=GROCERY_PARTNER_NAME=Breadfast` for
the button, and `--dart-define=GROCERY_AFFILIATE_ID=<Qamar's reference>`.
The basket is the day's portions in household units; converting them to the
partner's SKUs is the partner-side half of the integration. Opening the
basket is counted as `basket_opened {items, partner}`.
Without the key the SDK is never initialised. With it, three rules hold:

- **Nothing is sent before consent.** The SDK starts only when the person
  says yes to service improvement in the consultation (or on the You screen),
  and stops when they say no. Until the question has been answered, events
  wait on the phone, in memory: at most 50, with the earliest kept, so
  `intake_started` is never the one pushed out. After a yes they go out,
  marked `pre_consent`. A no throws them away, and from then on nothing
  waits. The answer is remembered on the phone and, on a linked account, in
  the `consents` table (append-only, latest row wins). The first answer is
  recorded whichever way it goes.
- **No person in the events.** Events carry a name, the language, the tier
  and a few small enums or counts (`meal_logged {source, first, items,
  nudged, prompt, orb_waiting}`, `meal_read {source, items, ms}`, `intake_started {via}`,
  `intake_step {step}`,
  `orb_gesture_first {gesture}`, `trial_started`, `checkout_opened {plan,
  promo}`, `review_shared`, …). Never a name, a weight, a food, a photo or an
  email. The account id is the identity — the same opaque id the database
  uses.
- **The kill metrics do not depend on consent.** `qamar_kill_metrics(from, to)`
  (migration 0047, replaced as a whole by 0059) computes them from the rows
  people already write. Day 0 is the install (`auth.users`, created by the
  anonymous sign-in at launch). The rows are:
  - intake completion, from the tap on Start (`intake_starts`), and
    install→Start beside it;
  - day-7 logging (on day 7, as the blueprint pre-committed), and a week-1
    window beside it;
  - day-30 unprompted logging, read from each log's recorded `prompt`
    (`push`, `in_app` or `none`), and a stricter day-30 cold beside it;
  - trial-to-paid by source, read at the trial's end plus 7 days. The
    target and kill line sit on the organic row. The combined row beside it
    is diagnostic: Pro-code trials, expected to convert at about twice the
    organic rate, would lift it over a line that organic fails;
  - month-2 retention, counted on the second paid order.

  pg_cron records them nightly into `kill_metrics_daily` for the last sixty
  days of sign-ups. Service role only. The phone's fourteen-day push window
  counts from the same server day 0 (`qamar_account_day0`).

  Where a trial came from is written when it starts (0069): the free week
  (`qamar_start_trial(uuid)`, reached by the paywall, the lock card and
  onboarding's offer) writes `organic`, a nutritionist's code writes `pro`.
  An invitation's fortnight is still attributed by the metric (0059).

  **A cohort boundary: the day 0065 reaches the live database.** Before
  0065 the free tier's last question, photo and plan rewrite were counted
  and then refused, so the free tier really had two of each and met the
  question wall at the third question; from 0065 it has the three it is
  promised and meets the wall at the fourth. The wall is the organic trial's
  and the Su question's trigger, so `trial_to_paid_organic` and
  `qamar_su_question_conversion` (0066) are only comparable within one side
  of that day. Record the date 0065 is applied, and read either number for
  cohorts that started after it — never a window that spans it — before
  deciding anything about the price or the wall (O13).

- **A refusal that can pass later needs its own SQLSTATE.** The phone keeps
  a waiting invitation or nutritionist's code until the server has answered
  it, and treats the redeem function's own refusal — a plain `raise
  exception`, SQLSTATE P0001 — as final, clearing the code (all except
  "not signed in", which is about the session). Every refusal in
  `qamar_redeem_invitation` and `qamar_redeem_pro_code` is final today. A
  temporary one added later (a rate limit, a maintenance window) must be
  raised with another SQLSTATE, e.g. `raise exception '…' using errcode =
  'QM001'`, or the app will delete a code that would have worked.

Native auto-init is off in `AndroidManifest.xml` and `Info.plist`
(`com.posthog.posthog.AUTO_INIT = false`), so the plugin cannot start itself
at launch.
