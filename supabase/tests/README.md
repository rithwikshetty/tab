# roam — Database tests

pgTAP-based assertions covering schema integrity, constraints, triggers, RLS,
and edge cases. Each `.sql` file is self-contained:

- Wraps everything in `BEGIN ... ROLLBACK` so the DB stays clean.
- Declares a `plan(N)` of expected assertions.
- Uses a `_results` temp table to collect every assertion's TAP line, so
  `mcp__supabase__execute_sql` returns all rows (not just the last one).

## Running

Via Supabase MCP — paste a test file's body into `execute_sql`. Read the
returned rows; any line starting with `not ok` is a failure.

```sql
-- Returns one row per assertion plus a final "1..N" / "# Looks like ..." line.
```

## Test fixture

Tests that need users insert into `auth.users` directly (the `handle_new_user`
trigger then auto-creates `public.profiles`). Fixture UUIDs:

| Role  | UUID                                   | Role in fixture                                       |
|-------|----------------------------------------|-------------------------------------------------------|
| Alice | `00000000-0000-0000-0000-000000000001` | Trip creator + member of "Lisbon"                     |
| Bob   | `00000000-0000-0000-0000-000000000002` | Member of "Lisbon" (added)                            |
| Carol | `00000000-0000-0000-0000-000000000003` | Non-member (used to assert RLS denial paths)          |
| Dave  | `00000000-0000-0000-0000-000000000004` | Non-member, owns their own trip "Solo"                |

## Files

| File                      | Tests | Concern                                                |
|---------------------------|-------|--------------------------------------------------------|
| `01_schema.sql`           | ~50   | Tables/columns/PKs/FKs/RLS-enabled existence, invite/storage primitives |
| `02_constraints.sql`      | ~40   | CHECK / UNIQUE / FK constraints plus cross-table money/trip invariants |
| `03_triggers.sql`         | ~12   | set_sync_fields, handle_new_user, auto_add_creator, touch_trip_last_activity |
| `04_rls.sql`              | ~40   | RLS allow + deny per table, invite-only joining, per role (member/non/anon) |
| `05_edge_cases.sql`       | ~15   | Soft-delete, cascade vs restrict, helper-fn behavior   |
