# roam Supabase contract

`schema.sql` is the readable source of truth. This repo is pre-launch with no real users, so schema iteration is intentionally destructive by default.

Default workflow:

1. Edit `schema.sql` directly.
2. Keep baseline migration files minimal (rewrite/squash aggressively).
3. Agents with Supabase MCP access should apply destructive remote changes through MCP.
4. Humans or sessions without MCP can recreate the target DB with `./scripts/recreate_db.sh`.

Remote DB resets do not clear the app's local SwiftData store. Delete the app
from the simulator/device, or reset simulator content, when validating a truly
empty app state.

Receipt files live in Supabase Storage and are not deleted by SQL teardown.
Use `./scripts/clear_receipts_storage.sh` to empty the `receipts` bucket. To
delete the bucket itself, run it with `SUPABASE_SERVICE_ROLE_KEY` and
`--delete-bucket`.

## Client write paths

- Trip creation: insert into `trips`; the creator is auto-added by trigger.
- Invite creation: call `create_trip_invite(trip_id, expires_at?)`.
- Invite join: call `join_trip_with_invite(trip_id, invite_id, token)`.
- Expense creation/editing: write the expense and all split rows in one transaction/RPC. The database enforces that active split totals equal the expense amount.
- Receipt upload: upload JPEGs to the private `receipts` bucket at `<trip_id>/<expense_id>.jpg`.
- Soft-delete purge: call `purge_soft_deleted_records()` from a service-role scheduled job once the app is ready to enable the 30-day hard-delete policy.

Direct inserts into `trip_members` are not a public client API. RLS intentionally denies them.

## Invariants enforced by Postgres

- Payers, split users, settlement parties, creators, custom categories, and mute prefs must belong to the target trip.
- Expense split totals must equal the expense amount for active expenses.
- Invite tokens are stored only as SHA-256 hashes in the private schema.
- Receipt object access is derived from the trip id in the storage object path and `trip_members`.
- The purge function deletes only soft-deleted rows older than the cutoff and skips trips that still have expense or settlement rows.

## Test workflow

Run pgTAP files in `supabase/tests/` against a disposable database or branch. Each test wraps itself in `BEGIN ... ROLLBACK`.
