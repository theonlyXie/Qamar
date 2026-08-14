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
  prototype; `main.dart` flips `Directionality` live, matching the
  prototype's AR/EN toggle (now surfaced as a row on the You screen, since
  that toggle was prototype-preview chrome, not part of any real screen).

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
| `supabase/migrations/0002_wallet_functions.sql` | Atomic, idempotent `qamar_wallet_credit` / `qamar_wallet_redeem` RPCs (ledger insert + balance update in one transaction) | same |
| `lib/services/repositories.dart` | Abstract `ProfileRepository` / `MealRepository` / `WalletRepository` | — |
| `lib/services/supabase_repositories.dart` | Supabase-backed implementations of the above | Re-check each call against your pinned `supabase_flutter` version's query-builder API before use — it has shifted across majors |
| `lib/services/auth_service.dart` | Anonymous sign-in + Apple/Google identity-linking + email OTP, preserving the anonymous user id | Add `sign_in_with_apple` / `google_sign_in` packages and native config when you wire the sign-in buttons |
| `lib/services/ai_gateway.dart` | `MockAiGateway` (what the app uses today) + `HttpAiGateway` client for meal analysis / chat replies | Stand up a server endpoint (Edge Function or similar) that holds the OpenAI key server-side — **the client never holds a model API key**, per spec_mvp.txt §29.1 |
| `lib/services/payments.dart` | `in_app_purchase` wrapper for the Qamar+ subscription (Su Points are earned only — see `walletTerms` copy — never a paid product) | Create `qamar_plus_monthly`/`qamar_plus_annual` in App Store Connect / Play Console, and a server endpoint to verify receipts before flipping entitlement |
| `lib/services/config.dart` | `--dart-define` driven flags (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `AI_GATEWAY_URL`) | `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` |

**Wiring plan**: once you have real credentials, the natural next step is to
make `AppState` accept the repositories via constructor injection and swap
its in-memory mutations (`meals.add(...)`, `suAvailable += ...`, etc.) for
repository calls, while keeping every method's external signature the same
so the screens don't change. I left `AppState` untouched (rather than
half-wiring it) so the fully-offline demo stays correct and testable while
you do that migration deliberately, with a compiler available to check it.

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
- The orb's data explanations (`lib/widgets/explain.dart`) are static copy
  keyed by metric. The interaction is real — drag the orb over a value and
  drop it — but the words are written, not generated. Once the AI gateway
  exists they become the fallback and the orb explains the number in the
  user's own context.
