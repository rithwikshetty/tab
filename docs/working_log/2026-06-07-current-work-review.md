## 2026-06-07 08:48 BST

Goal: review the current unstaged work for concrete bugs, architecture fit, dependency breakage, and missing validation; fix real issues directly without staging or committing.

Initial state: branch is `main` tracking `origin/main`. There are no staged changes. Unstaged changes cover Swift app screens/models/services/tests, TabCore aggregation logic/tests, Supabase SQL/baseline/tests, design mockups, ADR/context docs, and new friends/non-group expense files.

## 2026-06-07 08:51 BST

Review finding: hidden `non_group` containers reuse `trips`, but the generic trip update/delete policies and activity triggers still treated them as normal trips. That meant a member could directly mutate the hidden trip row, and server-side creation of the hidden container/member rows could leak blank `trip_created` / `member_joined` activity. Direction: keep non-group expenses/settlements visible in Activity, but suppress scaffolding events and make hidden trip rows read-only to clients.

## 2026-06-07 08:52 BST

Review finding: `FriendsPresenter.Context` built friend candidates from every locally stored active container, not only containers containing the current user. With stale local SwiftData from a previous account or inaccessible trip, unrelated people could appear as settled friends. Direction: filter the presenter context to containers where the current user has a claimed `trip_people` row, and add a regression test.

## 2026-06-07 08:53 BST

Review finding: the people-first non-group flow could accept the current user's own email. The real RPC rejects a one-person participant set, but mock auth created a one-person hidden container locally. Direction: filter the current user's email in the picker and enforce the same "at least one other participant" invariant in `SyncService.resolveNonGroupContainer`.

## 2026-06-07 08:59 BST

Validation: `swift test` in `Packages/TabCore` passed (96 tests). `./supabase/scripts/build_schema.sh --check` and `bash supabase/tests/00_sql_assembly.sh` passed. XcodeBuildMCP simulator build for `Tab` on `iPhone 17` passed with no diagnostics. XcodeBuildMCP `test_sim` exceeded the tool's 120s timeout, but the underlying `xcodebuild test-without-building` continued and completed successfully: `TEST EXECUTE SUCCEEDED`, including the `Friends presenter` suite and 5 UI tests. A final simulator compile after dead-code cleanup also passed with no warnings/errors. `git diff --check` passed.

Supabase note: a pgTAP regression test was added in `supabase/tests/09_non_group.sql`, but it was not executed against a recreated database in this session. Supabase MCP branch listing failed with "Project reference is missing when validating permissions"; I did not perform a blind destructive reset of the linked database via CLI.
