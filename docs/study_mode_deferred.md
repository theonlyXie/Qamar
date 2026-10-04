# Study Mode: parked, and what has to be true before it is unparked

Study Mode lives on `cursor/study-mode-d6e0` — 3,669 lines across 22 files,
based cleanly on `main`. It is **not merged**, and every APK this repository
builds now passes `--dart-define=STUDY_MODE=false`, so it cannot appear on a
tester's phone even if the branch is merged while nobody is looking. Nutrition
ships first.

This file exists so the reasons do not evaporate. The branch looks finished —
it has screens, models, tests, and an edge-function surface — and someone
reading only the diff would merge it.

## What the feature paper asks for versus what is on the branch

The Study Mode Feature Paper §12 defines eight entities: `StudyWorkspace`,
`StudySource`, `StudyUnit`, `StudyGoal`, `StudyPlan`, `StudyTask`,
`StudySession`, `SessionLog`, and `StudyRewardEvent` (with
`idempotency_key`, `owner_id`, `task_or_review_id`, `rule_id`, `points`,
`ledger_event_id`). The branch's only migration,
`0034_study_teacher_mind.sql`, is **five lines** — it widens the
`ai_interactions.kind` check constraint. None of the eight tables exist.
Everything the paper describes as persisted state is held in Dart memory and
dies with the process.

## The four things that must change

### 1. Qamar has to do the planning

`StudyPlanner.schedule()` is pure Dart. It splits the topic string on commas,
increments a counter with `if (dayOffset % 3 == 0) milestone++`, and names the
result `'معلم $milestone'` — "milestone 1", "milestone 2". For a book with no
topic list it invents four Arabic placeholders. No model is consulted. A
student uploading an organic chemistry PDF and one uploading Egyptian history
get the same plan with different nouns.

The split to build: Qamar reads the source and returns the real units and
milestones — the content judgement. Deterministic code slices those into blocks
and dates — the arithmetic. Same division already used on the nutrition side,
where the model decides what a meal means and Postgres does the subtraction.

### 2. The learner model has to live on the server

`flutter analyze` gives this away without anyone reading the code:

```
error[require-await]: Async function 'studyForecast' has no 'await'
error[require-await]: Async function 'studyMasteryUpdate' has no 'await'
```

An async function that never awaits is not talking to anything. The signature
is `studyMasteryUpdate(_userId, …)` — the leading underscore is Dart for "this
parameter is deliberately unused". Mastery is computed from whatever the client
sends and thrown away. Nothing accumulates, and a reinstall is a new student.

### 3. Rewards need a server ledger, not a Set

`studyRewardKeys` is an in-memory `Set<String>`. It suppresses double-crediting
inside one run of the app and forgets everything on restart, so the same task
can be earned again tomorrow, and again the day after. The paper's
`StudyRewardEvent.idempotency_key` is exactly the fix, and it is the same fix
the nutrition side needed — see `0072_server_su_awards.sql`, which moved meal
and onboarding credits onto server triggers keyed by idempotency string. Study
rewards should go through `qamar_wallet_credit_internal` the same way.

### 4. `kind:"study"` is silently dropped today

The live `ai_interactions.kind` constraint is still
`('chat','meal_analysis','plan','body_scan')`. The branch writes
`kind:"study"`, the insert violates the check, and `record()` swallows the
failure — so study interactions are simply not logged, with no error anywhere.
`0034_study_teacher_mind.sql` fixes this, and must be renumbered to follow the
sequence in `app/supabase/migrations/README.md` before it is applied.

## Merging it later

The branch is based on `main`, and `main` has since taken the barcode, label
scan, conversational-prompt and micronutrient work. Expect real conflicts in
`ai-gateway/index.ts`, `ai-gateway/model.ts`, `state/app_state.dart` and
`services/config.dart` — all four were substantially rewritten. Resolve them in
favour of the nutrition versions and re-apply the study additions on top; do
not take the branch's copies wholesale, or the conversational prompt and the
scan routes go back to how they were in August.
