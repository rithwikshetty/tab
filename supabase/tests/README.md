# tab — Database tests

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
| Alice | `00000000-0000-0000-0000-000000000001` | Trip creator + joined person in "Lisbon"              |
| Bob   | `00000000-0000-0000-0000-000000000002` | Joined person in "Lisbon"                             |
| Carol | `00000000-0000-0000-0000-000000000003` | Non-member (used to assert RLS denial paths)          |
| Dave  | `00000000-0000-0000-0000-000000000004` | Non-member, owns their own trip "Solo"                |

## Files

| File                      | Tests | Concern                                                |
|---------------------------|-------|--------------------------------------------------------|
| `01_schema.sql`           | 42    | Tables/PKs/FKs/RLS-enabled existence and email-person RPCs |
| `02_constraints.sql`      | 18    | CHECK / UNIQUE / FK constraints plus trip-person ledger invariants |
| `03_triggers.sql`         | 9     | `handle_new_user`, sync/touch triggers, transactional trip creation |
| `04_rls.sql`              | 16    | RLS allow + deny paths and email-claim joining          |
| `05_edge_cases.sql`       | 10    | Soft-delete purge, cascade vs restrict, helper-fn behavior |
| `06_expense_payments.sql` | 10    | Transactional expense RPC with trip-person payments/splits |
