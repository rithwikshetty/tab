# tab Supabase contract

The editable database contract is split across numbered files in `sql/`. `schema.sql` is only a small source map; do not put DDL there. This repo is pre-launch with no real users, so schema iteration is intentionally destructive by default.

Default workflow:

1. Edit the narrowest file in `sql/`.
2. Add/update pgTAP coverage in `tests/` for behavior changes.
3. Run `./scripts/build_schema.sh --write` to refresh the generated baseline migration.
4. Run `bash tests/00_sql_assembly.sh` to verify the baseline matches `sql/*.sql`.
5. Agents with Supabase MCP access should apply destructive remote changes through MCP.
6. Humans or sessions without MCP can recreate the target DB with `./scripts/recreate_db.sh`.

Remote DB resets do not clear the app's local SwiftData store. Delete the app
from the simulator/device, or reset simulator content, when validating a truly
empty app state.

Receipt files live in Supabase Storage and are not deleted by SQL teardown.
Use `./scripts/clear_receipts_storage.sh` to empty the `receipts` bucket. To
delete the bucket itself, run it with `SUPABASE_PROJECT_REF`,
`SUPABASE_SERVICE_ROLE_KEY`, and `--delete-bucket`.

## Client write paths

- Trip creation: call `create_trip_with_self(trip_id, person_id, name)` so the trip and creator person row are transactional and use client-provided UUIDs.
- Add person by email: call `add_trip_person_by_email(trip_id, email, display_name?, person_id?)`. Existing auth users join immediately; otherwise the row remains pending.
- Sign-in claim: call `claim_trip_people_for_current_email()` before pulling trips.
- Suggestions: call `suggest_trip_people(query?, limit?)`; results are limited to people the current user has already shared trips with.
- Expense creation/editing: call `create_expense_with_payments_and_splits(expense, payments, splits)`. It atomically upserts an active expense and replaces both ledgers; edits to soft-deleted expenses are rejected.
- Receipt upload: upload JPEGs to the private `receipts` bucket at `<trip_id>/<expense_id>.jpg`.
- Soft-delete purge: call `purge_soft_deleted_records()` from a service-role scheduled job once the app is ready to enable the 30-day hard-delete policy.

Direct inserts into `trip_people` are not a public client API. RLS intentionally denies them.

## Invariants enforced by Postgres

- Payers, split participants, settlement parties, creators, custom categories, and mute prefs must belong to the target trip.
- Expense payment and split totals must equal the expense amount for active expenses.
- Pending people are matched by normalized email and linked to auth profiles by `claim_trip_people_for_current_email()`.
- Receipt object access is derived from the trip id in the storage object path and joined `trip_people`.
- The purge function deletes only soft-deleted rows older than the cutoff and skips trips that still have expense or settlement rows.

## Test workflow

Run `bash supabase/tests/00_sql_assembly.sh` locally first; it verifies the split SQL sources generate the checked-in baseline. Then run pgTAP files in `supabase/tests/` against a disposable database or branch. Each SQL test wraps itself in `BEGIN ... ROLLBACK`.
