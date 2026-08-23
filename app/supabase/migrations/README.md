# Migration numbering

One sequence, no gaps, no reuse. The number is a position in the order the
migrations were **actually applied to the live database**, not the order anyone
happened to write them.

## Why this file exists

Work happened on five branches at once and each of them started numbering from
wherever its own base ended. The result was three files called `0032_*`, two
called `0031_*`, two called `0033_*`, and — on two other branches — a second,
renumbered copy of migrations that had already run on the live database under
different names. Numbering had stopped meaning anything, and a `supabase db
push` on a fresh project would have applied them in an order the database has
never seen.

## The rule

`supabase_migrations.schema_migrations` on project `stqirjlqzchcoeegumoq` is the
source of truth. To find the next number, take the highest number in this
directory and add one. Never renumber a file that has already been applied, and
never give a new file a number that has ever been used.

## The mapping applied on 2026-08-23

Live applied order → filename. The five files on the right were renamed; nothing
else moved, and no file contents changed.

| Applied (Cairo)        | Live migration name                  | File                                        |
| ---------------------- | ------------------------------------ | ------------------------------------------- |
| 2026-08-17 15:54       | `micronutrient_reference`            | `0031_micronutrient_reference.sql`          |
| 2026-08-17 15:59       | `dri_lookup_and_evals`               | `0032_dri_lookup_and_evals.sql`             |
| 2026-08-17 16:21       | `gap_needs_per_nutrient_coverage`    | `0033_gap_needs_per_nutrient_coverage.sql`  |
| 2026-08-17 16:41–19:12 | `resolver_phrase_coverage` (+3 fixes)| `0034_resolver_phrase_coverage.sql`         |
| 2026-08-17 20:04       | `ai_quota_and_su_economy`            | `0035_ai_quota_and_su_economy.sql` (was 0031) |
| 2026-08-17 20:05       | `water_logs`                         | `0036_water_logs.sql` (was 0032)            |
| 2026-08-17 23:17       | `paymob_billing`                     | `0037_paymob_billing.sql` (was 0032)        |
| 2026-08-17 23:18       | `plus_pricing_affiliates`            | `0038_plus_pricing_affiliates.sql` (was 0033) |
| 2026-08-17 23:19       | `revoke_anon_from_definer_functions` | `0039_revoke_anon_from_definer_functions.sql` (was 0035) |

A handful of live migrations are follow-up fixes applied straight to the
database while iterating (`touch_updated_at_search_path`,
`requirement_engine_array_literal_fix`, `eval_runner_stable_kind`,
`resolver_coverage_evals`, `coverage_modifiers_and_spelling`,
`eval_runner_shared_usability`). They are folded into the file whose number they
sit under, because that file is the finished state of the thing they were
fixing.

## Branches that still carry stale numbers

These are not merged yet. When one is merged, renumber its **new** migrations to
continue after the highest number here, and delete its copies of migrations that
are already applied — a second copy under a new number would run the same DDL
twice on a fresh project.

| Branch                     | Already applied under another name        | Genuinely new           |
| -------------------------- | ----------------------------------------- | ----------------------- |
| `cursor/finish-mvp-d6e0`   | `0035`–`0037` (= `0031`–`0033` here)      | `0038_mvp_closeout.sql` |
| `cursor/test-apk-d6e0`     | `0035`–`0037` (= `0031`–`0033` here)      | `0038_mvp_closeout.sql` |
| `cursor/study-mode-d6e0`   | the duplicated `0031`–`0033` set          | `0034_study_teacher_mind.sql` |
| `cursor/chat-ui-fix-d6e0`  | the duplicated `0031`–`0033` set          | none                    |
