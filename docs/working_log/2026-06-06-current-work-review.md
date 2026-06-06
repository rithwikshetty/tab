# Current Work Review

## 2026-06-06 08:25 BST - Goal

Review the current repository work for correctness, architecture fit, dependency breakage, and test coverage. Inspect staged and unstaged changes first, then review the active `feat/notifications` branch against `main` if the worktree is clean. Fix concrete issues directly, check for connected Linear context, and run focused validation without staging or committing local work.

## 2026-06-06 08:25 BST - Initial scope

`git status`, `git diff`, and `git diff --cached` show a clean working tree with no staged or unstaged changes. The active branch is `feat/notifications` at `e503965`, ahead of `main`/`origin/main` (`f272e3d`) by the notification-system commits, so the review scope is the branch diff against `main`.

No Linear issue ID is visible in the branch name, recent commits, or working logs. The notification-system working log describes the intended scope and prior validation.

## 2026-06-06 08:34 BST - Push RPC privilege finding

Found a live push-path issue in the SQL/edge-function contract: `public.push_targets_for_activity(uuid)` was revoked from public/anon/authenticated but not granted to `service_role`, while the `send-push` edge function calls that RPC with the Supabase service-role key after APNs is configured. Service role bypasses RLS, not function `EXECUTE` privilege, so live APNs sends could fail with a permission error. Patched `supabase/sql/18_notifications_push.sql` to grant the RPC to `service_role` and added a pgTAP assertion in `supabase/tests/08_activity_notifications.sql`.

## 2026-06-06 08:41 BST - SQL validation

Rebuilt the generated baseline with `./supabase/scripts/build_schema.sh --write`. `bash supabase/tests/00_sql_assembly.sh` passed and `git diff --check` passed.

Checked the Supabase `tab-it` project via MCP. The current remote already reports `service_role` can execute `push_targets_for_activity`, likely via Supabase's default function grants, so the local patch encodes an existing required contract rather than changing the live remote state during review. Ran the updated `supabase/tests/08_activity_notifications.sql` through MCP in a rolled-back transaction; all 16 assertions passed, including the new service-role privilege assertion.

## 2026-06-06 08:45 BST - UI test prompt finding

Found that the notification permission prompt introduced by the branch can appear during existing UI tests because they only set `TAB_MOCK_AUTH=1`. Patched the UI test app launches to also set `TAB_SKIP_PUSH_PROMPT=1`, matching the app's debug opt-out path and avoiding a blocking system alert in the paid-by flow tests.

## 2026-06-06 08:48 BST - UI test keyboard finding

First `test_sim` run compiled and passed 23 tests but all 4 UI tests failed in `replaceText`: XCTest found the keyboard delete key, then failed to scroll it to a visible tappable point on the iPhone 17 Pro simulator. Patched the helper to type delete keystrokes directly instead of tapping the keyboard key by accessibility, which removes the simulator-keyboard hittability dependency.

## 2026-06-06 08:38 BST - Final validation

Validation passed after the fixes:

- XcodeBuildMCP full `test_sim` result bundle reports 27/27 app tests passed on iPhone 17 Pro (iOS 26.4). The tool call itself timed out at 120 seconds, but the underlying `xcodebuild` completed successfully and the result bundle reports `result: Passed`.
- XcodeBuildMCP UI-only rerun for `TabUITests/PaidByFlowUITests` passed 4/4 after the helper cleanup.
- `swift test` in `Packages/TabCore` passed 85/85 tests.
- `bash supabase/tests/00_sql_assembly.sh` passed.
- Updated `supabase/tests/08_activity_notifications.sql` passed 16/16 via Supabase MCP in a rolled-back transaction.
- `git diff --check` passed.

During final status, additional local FAB-placement changes appeared in `Fab.swift`, `TripListView.swift`, `TripDetailView.swift`, `RootView.swift`, plus `docs/working_log/2026-06-06-fab-placement.md`. These were not part of the initial clean-worktree review scope and were not made by this review pass. A fresh XcodeBuildMCP simulator build after those changes passed with no warnings.

## 2026-06-06 08:36 BST - Trips background fix

While inspecting current git changes, noticed `TripListView` did not apply the locked sage app background at its scroll-view root, unlike `ActivityView` and `SettingsView`. Added `.background(Sage.bg.ignoresSafeArea())` so the Trips tab uses the `#FAF7F0` design-token background across content gaps and safe areas.

## 2026-06-06 08:36 BST - Tab shell background standardisation

Re-checked the notification branch against `main` after the Activity tab addition. The old custom root shell applied `Sage.bg` around all tab content, but the native `TabView` rewrite moved that responsibility into individual child screens and left the native tab bar on its default material. Added the shared app background and sage tab-bar toolbar background to `RootView` so tab-level chrome is standardized again.

## 2026-06-06 08:38 BST - Tab shell build validation

Ran `xcodebuild -project Apps/Tab/Tab.xcodeproj -scheme Tab -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`; the app build succeeded, confirming the root `TabView` background and tab-bar toolbar modifiers compile for the current iOS simulator SDK.
