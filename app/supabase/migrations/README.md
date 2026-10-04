# Migration numbering

One sequence, no reuse. A file keeps its number once it has run on the live
database, and a new file takes the highest number here plus one.

`supabase_migrations.schema_migrations` on project `stqirjlqzchcoeegumoq` is
the record of what ran and when. Its versions are timestamps, not these
numbers, because the migrations were applied with the Supabase connector
(`apply_migration`), which stamps each one with the time it ran. So
`supabase db push` refuses to run against the live project: it cannot find any
of these files in that history. Apply a new migration with `apply_migration`
(or paste it into the SQL editor, which records nothing), named
`<number>_<name>` as `0038` onwards are, so the history and the files say the
same thing.

## Why the numbers and the live order differ

Two lines of work reached the live database at the same time. One is
`claude/connector-status-check-xsmlnq` (August: the food resolver, the Su
awards, the grant fixes, the catalogue corrections). The other is PR #18
(`xie/peaceful-ptolemy-7m9zgm`), which carries `0038`–`0069` and is where the
two now meet. Both started numbering from the same base, so the same numbers
meant different files.

`0038`–`0069` appear by number in the live history (applied on 22 and 24
September), so they keep their numbers. The August migrations that only the
other line had ran first, but their numbers there (`0034`, `0039`–`0044`) are
taken here, so they are `0070`–`0076`. That is the only renumbering, and none
of them had a number in the live history to disagree with. The migrations
both lines shared (`0030`–`0037`) are identical apart from comments, and keep
this line's numbers.

`0054`–`0056` belong to PR #19 (`xie/laughing-turing-jsvewe`), live since 21
and 22 September; the files arrive with that PR.

## Live history → file

`0001`–`0029` match the live names one to one, apart from a few follow-up
fixes applied straight to the database while iterating
(`touch_updated_at_search_path`, `rule_applies_search_path`,
`requirement_engine_array_literal_fix`, `requirement_policy_fail_closed`,
`eval_runner_stable_kind`), which sit in the live history between the
migrations they followed. From `0030`:

| Applied (UTC)      | Live migration name                  | File                                          |
| ------------------ | ------------------------------------ | --------------------------------------------- |
| 2026-08-17 01:35   | `embedding_provenance`               | `0030_embedding_provenance.sql`               |
| 2026-08-17 15:54   | `micronutrient_reference`            | `0032_micronutrient_reference.sql`            |
| 2026-08-17 15:59   | `dri_lookup_and_evals`               | `0033_dri_lookup_and_evals.sql`               |
| 2026-08-17 16:21   | `gap_needs_per_nutrient_coverage`    | `0036_gap_needs_per_nutrient_coverage.sql`    |
| 2026-08-17 16:41–19:12 | `resolver_phrase_coverage` and three fixes (`resolver_coverage_evals`, `coverage_modifiers_and_spelling`, `eval_runner_shared_usability`) | `0070_resolver_phrase_coverage.sql` |
| 2026-08-17 20:04   | `ai_quota_and_su_economy`            | `0031_ai_quota_and_su_economy.sql`            |
| 2026-08-17 20:05   | `water_logs`                         | `0035_water_logs.sql`                         |
| 2026-08-17 23:17   | `paymob_billing`                     | `0034_paymob_billing.sql`                     |
| 2026-08-17 23:18   | `plus_pricing_affiliates`            | `0037_plus_pricing_affiliates.sql`            |
| 2026-08-17 23:19   | `revoke_anon_from_definer_functions` | `0071_revoke_anon_from_definer_functions.sql` |
| 2026-08-23 00:48   | `server_su_awards`                   | `0072_server_su_awards.sql`                   |
| 2026-08-23 00:57   | `revoke_public_execute`              | `0073_revoke_public_execute.sql`              |
| 2026-08-23 05:33   | `fix_miscited_curated_foods`         | `0074_fix_miscited_foods.sql`                 |
| 2026-08-23 05:34   | `store_and_check_cited_titles`       | `0075_cited_titles_and_check.sql`             |
| 2026-08-23 05:38   | `strip_false_citations_from_dishes`  | `0076_provisional_dish_values.sql`            |
| 2026-09-21 17:50   | `0055_usda_hand_mapped_ids`          | PR #19                                        |
| 2026-09-21 17:50   | `0054_egyptian_dishes_top200`        | PR #19                                        |
| 2026-09-22 14:06–14:23 | `0038_wallet_rls_hardening` … `0053_pro_adherence` | the files of the same names |
| 2026-09-22 14:31   | `0056_clinical_rules_seed`           | PR #19                                        |
| 2026-09-24 18:44–18:51 | `0057_intake_starts` … `0069_pro_code_trial` | the files of the same names |

The live copies of `0072`–`0076` were applied without their long header
comments, and some point at the old file names (`0040_server_su_awards.sql`,
"see 0042"); this table is how to follow them.

## A fresh project

Applied in file order, a new project gets the same schema by a slightly
different path: `0031` runs before `0032`, and `0070`–`0076` run after `0069`
instead of before `0038`. Nothing in `0038`–`0069` reads anything `0070`–`0076`
create. The two grant migrations, `0071` and `0073`, name the functions they
close, so running later closes the same ones. One interaction is worth
knowing: each line pays Su through its own path. `0072` adds an award trigger
on `meal_logs` beside `0046`'s. Both credit a meal under the ledger key
`meal:<id>`, and the ledger refuses a key it already holds
(`qamar_wallet_credit_internal`, `0006`), so a meal is paid once whichever
trigger fires first. The day's quest shares `quest:<user>:<day>` the same way.
Onboarding did not: `0072`'s trigger used `onboarding:<user>` and `0046`'s
function `onboarding_<user>`, which `0077` fixes by moving the function to the
trigger's key.

## Branches that still carry other numbers

When one of these is merged, give its new migrations the next numbers here and
drop its copies of migrations that already ran.

| Branch                               | Already applied under another name       | Genuinely new                  |
| ------------------------------------ | ---------------------------------------- | ------------------------------ |
| `xie/laughing-turing-jsvewe` (PR #19)| `0054`–`0056` (live under those numbers) | none                           |
| `xie/gallant-ritchie-tvv4m8` (PR #20)| —                                        | `0034_food_catalog.sql`        |
| `cursor/finish-mvp-d6e0`             | its `0035`–`0037` (= `0031`, `0032`, `0033` on `main`) | `0038_mvp_closeout.sql` |
| `cursor/test-apk-d6e0`               | its `0035`–`0037` (= `0031`, `0032`, `0033` on `main`) | `0038_mvp_closeout.sql` |
| `cursor/study-mode-d6e0`             | the duplicated `0031`–`0033` set         | `0034_study_teacher_mind.sql`  |
| `cursor/chat-ui-fix-d6e0`            | the duplicated `0031`–`0033` set         | none                           |
