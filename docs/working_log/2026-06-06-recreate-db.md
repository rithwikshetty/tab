# Recreate Database

## 2026-06-06 08:39 BST - Goal

Recreate the linked Supabase database for the `tab` project using the current local baseline schema. This is destructive for SQL-owned app data and objects; receipt Storage objects are not cleared by the SQL reset.

## 2026-06-06 08:39 BST - Plan

Use the repo reset flow: build the generated schema from `supabase/sql/*.sql`, apply `supabase/scripts/destructive_teardown.sql`, then apply the generated baseline to the linked Supabase database. Validate with SQL assembly and pgTAP after the reset.

## 2026-06-06 08:40 BST - CLI fallback unavailable

Ran `./supabase/scripts/recreate_db.sh`. It built the generated schema but failed to apply SQL because this checkout is not linked for Supabase CLI (`Cannot find project ref. Have you run supabase link?`). Switching to Supabase MCP against project `gaseuxsieddlksxtdliq` (`tab-it`) to apply the teardown and generated schema remotely.

## 2026-06-06 08:43 BST - Remote recreate applied

Applied `supabase/scripts/destructive_teardown.sql` through Supabase MCP as migration `recreate_db_20260606_teardown`. Then applied the freshly built `supabase/.temp/generated_schema.sql` through the Supabase Management API migration endpoint using local `.env.local` credentials, as migration `recreate_db_20260606_schema`. The schema apply returned success.

## 2026-06-06 08:47 BST - Validation and cleanup

Validation passed:

- `bash supabase/tests/00_sql_assembly.sh` passed.
- Remote sanity checks show all 11 public app tables exist with RLS enabled.
- Default categories are seeded: 6 rows.
- pgTAP files `01_schema.sql` through `08_activity_notifications.sql` passed through the Supabase Management API query endpoint.

After pgTAP, a row-count check showed one mutable app-data row in several tables. Deleted mutable app data from `activity_log`, `push_devices`, `trip_mute_prefs`, `settlements`, `expense_payments`, `expense_splits`, `expenses`, `trip_people`, `trips`, and `profiles`. Final row-count check shows all mutable app tables at 0 rows and the six default categories intact.

Advisor pass:

- Security: expected warnings remain for authenticated `SECURITY DEFINER` RPCs, leaked-password protection disabled, and `pg_net` installed in `public`.
- Performance: fresh-db informational warnings for unused indexes, plus one unindexed FK warning on `expenses.last_edited_by`.

Note: SQL recreate does not clear Supabase Storage receipt objects and does not clear local SwiftData on simulators/devices. The reset also leaves `private.app_config` empty, so push webhook URL/secret must be reseeded if live push fan-out should stay wired.
