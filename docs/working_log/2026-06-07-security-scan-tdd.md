# 2026-06-07 Security Scan and TDD Fixes

## Goal

Run the Codex Security workflows requested by the user, validate any candidate findings, and fix confirmed issues with a test-driven loop. The user explicitly allowed development-environment database manipulation and cleanup.

## 2026-06-07 09:26 BST

Started from a clean `main` worktree at commit `14cf1da46fa2a7bf88f9624231f96f18a3e729a1`.

Loaded the Codex Security and TDD skill instructions. Repo-wide/scoped Codex Security scans require explicit sub-agent authorization for exhaustive coverage, and the runtime sub-agent tool also requires explicit user authorization. I will not claim an exhaustive fanout scan until that authorization exists. Continuing with non-blocking setup, threat-model artifact work, repository inspection, and baseline verification while preserving that proof gap.

## 2026-06-07 09:28 BST

Created Codex Security scan bundle `/tmp/codex-security-scans/tab/14cf1da_20260607T082732Z` and wrote the repository-scoped threat model to `/tmp/codex-security-scans/tab/threat_model.md`, then copied it to the per-scan context path.

Baseline validation passed before any security fixes: `swift test` in `Packages/TabCore` passed 96 Swift Testing tests, and `bash supabase/tests/00_sql_assembly.sh` reported the generated baseline is up to date.

## 2026-06-07 09:32 BST

Ran app-level simulator tests through XcodeBuildMCP with scheme `Tab`, simulator `iPhone 17`, and `TAB_MOCK_AUTH=1`. The MCP call itself timed out at 120 seconds, so I checked process status and the generated result bundle instead of treating the timeout as failure. Result bundle `/Users/rithwikshetty/Library/Developer/XcodeBuildMCP/workspaces/tab-ae6a56a09c0c/result-bundles/test_sim_2026-06-07T08-29-08-900Z_pid23884_035ade9a.xcresult` reports 36 total tests, 36 passed, 0 failed, 0 skipped.

## 2026-06-07 09:33 BST

Continued under the active goal. Explicit sub-agent authorization is still missing, so the official exhaustive repo-wide Codex Security discovery workflow remains unstarted. Proceeding with a local high-risk discovery pass that does not claim exhaustive Codex Security coverage: Supabase RLS/RPCs, receipt storage, push webhook, and client secret/config handling.

## 2026-06-07 09:39 BST

Validated a security finding in the Activity/push path. `public.activity_log` was documented as trigger-owned, but RLS allowed authenticated trip members to insert arbitrary rows directly. Because every insert feeds the Activity stream and push trigger, a client could forge activity rows and increase other members' unread counts.

TDD red: added a pgTAP assertion in `supabase/tests/08_activity_notifications.sql` that direct client `activity_log` inserts must throw `42501`. Running the test through Supabase MCP failed as expected: the insert raised no exception, and Bob's unread count became 7 instead of 6.

Fix: removed `activity_log_insert_member` from `supabase/sql/12_rls.sql`, clarified the trigger-owned table comment in `supabase/sql/09_activity_log.sql`, and regenerated the baseline migration. Applied the same policy drop to the configured development Supabase database for validation.

Green validation: a focused MCP pgTAP proof now passes: trigger-created activity rows still insert, direct client insert is denied, the forged event does not affect unread count, and members can still read trigger-owned activity rows. `bash supabase/tests/00_sql_assembly.sh` also passes.

## 2026-06-07 09:46 BST

Validated a second RLS privacy issue. `profiles_select_authenticated` allowed any authenticated user to read every profile row, including users they do not share a trip with. That conflicts with the no-global-directory model and exposed profile metadata plus each user's Activity read cursor.

TDD red: added `supabase/tests/04_rls.sql` assertions that Alice can see Bob's profile because they share Lisbon, but cannot see Carol's profile because Carol only belongs to Solo. A focused Supabase MCP pgTAP proof failed before the fix: Alice could read Carol's profile.

Fix: replaced the global profile select policy with `profiles_select_self_or_shared_trip`, allowing the caller's own profile plus profiles for joined people in trips the caller can access. Updated the profile table comment and regenerated the baseline migration.

Green validation: a focused MCP pgTAP proof now passes for self, shared-trip, and unrelated-profile denial. `bash supabase/tests/00_sql_assembly.sh` also passes after regenerating the baseline.

## 2026-06-07 09:55 BST

Validated a third RLS/data-integrity issue. Soft-deleted user-visible tables (`trips`, `categories`, `expenses`, `settlements`) still exposed authenticated hard-delete policies. A trip member could permanently delete rows through the Data API, bypassing the `deleted_at` recovery window and, for expenses/settlements, the update-based Activity/push path.

TDD red: added `supabase/tests/04_rls.sql` coverage for direct hard-delete attempts against one row in each soft-delete table. The first focused MCP proof showed deletes were not being blocked by policy. The initial assertion shape expected `42501`, but the remote policy catalog confirmed that RLS-denied deletes are represented as zero affected rows rather than an exception, so I corrected the test to assert the rows remain present after the delete attempt.

Fix: removed `trips_delete_member`, `categories_delete_member_custom`, `expenses_delete_member`, and `settlements_delete_member` from `supabase/sql/12_rls.sql`, then regenerated the baseline migration. Applied the same policy drops to the configured development Supabase database for validation.

Green validation: a focused MCP pgTAP proof now passes for all four rows remaining present after direct delete attempts. `bash supabase/tests/00_sql_assembly.sh` also passes.

## 2026-06-07 09:56 BST

Resumed after the hard-delete policy fix and re-checked the worktree. Only the expected SQL, pgTAP, generated baseline, and working-log files are modified.

Reviewed the client sync paths affected by removing direct DELETE from soft-delete tables. Existing trip, expense, and settlement delete sync already uses `UPDATE deleted_at`; `trip_mute_prefs` still uses DELETE, but that table has no `deleted_at` and row presence is the mute state. The remaining RLS DELETE policies are on self-owned state rows, expense child rows, trip people, receipt storage, or profile deletion rather than the soft-deleted user-visible records fixed above.

## 2026-06-07 09:59 BST

Final verification pass for the implemented fixes:

- `./supabase/scripts/build_schema.sh --write` regenerated the baseline.
- `bash supabase/tests/00_sql_assembly.sh` passed.
- `cd Packages/TabCore && swift test` passed 96 Swift Testing tests.
- XcodeBuildMCP simulator tests timed out at the MCP transport boundary, but the underlying `xcodebuild` process completed and the result bundle reports 36 total app tests, 36 passed, 0 failed, 0 skipped.
- Supabase MCP policy catalog confirms `activity_log` has no INSERT policy, and `trips`, `categories`, `expenses`, and `settlements` have no DELETE policies.
- Supabase MCP execution of the changed pgTAP files passed: `04_rls.sql` 22/22 assertions and `08_activity_notifications.sql` 17/17 assertions.

## 2026-06-07 10:01 BST

Completed a diff-focused security review of the final patch. No regression found in the implemented changes. The baseline migration mirrors the SQL source changes, `git diff --check` is clean, the removed vulnerable policy names no longer appear in `supabase/sql`, `supabase/migrations`, or `supabase/tests`, and the remaining DELETE policies apply outside the fixed soft-delete record classes.

Wrote the fix report artifact to `/tmp/codex-security-scans/tab/14cf1da_20260607T082732Z/artifacts/fix_report.md`. The official exhaustive sub-agent fanout scan remains pending explicit sub-agent authorization.

## 2026-06-07 10:02 BST

Continued the active goal from current state. The worktree still contains only the implemented RLS/security patch and the working log. Since explicit sub-agent authorization is still absent, I am continuing with another local discovery pass rather than claiming the official exhaustive fanout workflow.

## 2026-06-07 10:08 BST

Validated a fourth RLS/data-integrity issue. Direct member updates could rewrite immutable provenance/parent fields: `trips.created_by`, `expenses.trip_id`, `expenses.created_by`, and `settlements.created_by`. The expense trip move was the most serious because it could move an expense into another trip while existing payment/split rows still referenced trip_people from the original trip.

TDD red: added four pgTAP assertions to `supabase/tests/04_rls.sql` and ran a focused Supabase MCP proof before the fix. The proof failed: direct trip creator rewrite, expense trip move, and settlement creator rewrite raised no exception; the expense creator rewrite only failed as a side effect after the trip move had already corrupted the row's parent trip.

Fix: made `trips.created_by`, `expenses.trip_id`, `expenses.created_by`, `settlements.trip_id`, and `settlements.created_by` immutable in the existing trigger functions. Applied the same function replacements to the configured development Supabase DB.

Green validation: the focused Supabase MCP proof now passes 4/4, and full remote execution of the updated `04_rls.sql` passes 26/26. Local `bash supabase/tests/00_sql_assembly.sh` passes and `cd Packages/TabCore && swift test` still passes 96 Swift Testing tests.

## 2026-06-07 10:12 BST

Continued the local discovery pass through receipt storage, edge push, auth/session, realtime, non-group RPC, and function privileges. Receipt storage remains private and trip-scoped; client paths generate canonical `<trip_id>/<expense_id>.jpg` object paths. The edge push function still trusts webhook body details for banner rendering after the shared secret check, but there is no local Deno test runtime, so I am not making an untested refactor under the TDD requirement; treat it as a hardening note rather than a validated finding.

Queried the live DB function privileges. No project function is executable by `anon`. The expected authenticated RPCs are callable, and private helper execution is limited to authenticated sessions for RLS/storage helper use. Found one stale remote-only function, `public.auto_add_creator_as_member()`, absent from source and unused by triggers; dropped it from the development DB as drift cleanup.

## 2026-06-07 10:18 BST

Final verification for this continuation pass:

- `bash supabase/tests/00_sql_assembly.sh` passed after regenerating the baseline.
- `cd Packages/TabCore && swift test` passed 96 Swift Testing tests.
- Full remote Supabase MCP execution of updated `04_rls.sql` passed 26/26.
- `git diff --check` passed.
- XcodeBuildMCP simulator test call timed out at the MCP 120-second boundary, but the underlying `xcodebuild` process completed; result bundle `/Users/rithwikshetty/Library/Developer/XcodeBuildMCP/workspaces/tab-ae6a56a09c0c/result-bundles/test_sim_2026-06-07T08-58-54-362Z_pid23884_bc56bcaf.xcresult` reports 36 total app tests, 36 passed, 0 failed, 0 skipped.

## 2026-06-07 10:04 BST

Continued remote validation around the changed trip guard by running `supabase/tests/09_non_group.sql` through Supabase MCP. The first run failed before assertions because the test had a data-modifying CTE nested inside a scalar `SELECT`, which Postgres rejects with `0A000`.

Fixed the pgTAP harness shape without changing the checked behavior: the attempted hidden non-group trip update now uses a top-level data-modifying CTE feeding the same `is(..., 0, ...)` assertion.

## 2026-06-07 10:07 BST

Remote red/green follow-up for `supabase/tests/09_non_group.sql`: after the harness fix, the test ran and failed 3/25 assertions in the development DB. The failures showed live DB drift from source: non-group container scaffolding emitted Activity rows, clients could update hidden non-group trip rows, and expense Activity then used the client-mutated hidden row name.

Source SQL already had the intended protections (`trips_update_member` restricted to `kind = 'trip'`, `log_trip_activity()` and `log_membership_activity()` skip `kind = 'non_group'`, and `private.trip_name()` returns `Non-group` for hidden containers). Applied a dev DB drift cleanup migration to bring those definitions back to source, then reran the full remote test. Green validation: `09_non_group.sql` passed 25/25 assertions.

## 2026-06-07 10:07 BST

Ran Supabase security advisors after the dev DB DDL. The advisor reported one source-fixable warning: `public.guard_trip_kind()` had a role-mutable `search_path`. Updating the source function to set an explicit `search_path`, then regenerating the baseline and applying the same definition to the dev DB.

## 2026-06-07 10:07 BST

During the advisor-listed SECURITY DEFINER RPC review, found a fifth issue in the non-group path. Group-trip RPCs are intentionally callable by authenticated users, but `add_trip_person_by_email()` and `create_trip_with_self()` did not reject hidden `kind = 'non_group'` containers. A member of a non-group container could use the group-trip add-person RPC to add an extra participant outside the canonical `member_signature`, or use the group-trip creation RPC with an existing non-group `trip_id` to rewrite the hidden row name.

TDD red: added two pgTAP assertions to `supabase/tests/09_non_group.sql` requiring both group-trip RPCs to reject hidden non-group container IDs. The test includes cleanup for the current vulnerable behavior so later assertions remain diagnostic.

## 2026-06-07 10:07 BST

Green for the fifth finding. Updated `create_trip_with_self()` and `add_trip_person_by_email()` so group-trip RPCs reject existing `kind = 'non_group'` IDs before mutating rows. The create-trip conflict path also now refuses to update anything except real `kind = 'trip'` rows.

Applied the same function replacements to the development DB. Focused Supabase MCP proof passed 2/2, then full remote execution of updated `supabase/tests/09_non_group.sql` passed 27/27 assertions.

## 2026-06-07 10:13 BST

Verification after the fifth finding:

- `bash supabase/tests/00_sql_assembly.sh` passed; regenerated baseline is up to date.
- `cd Packages/TabCore && swift test` passed 96 Swift Testing tests.
- `git diff --check` passed.
- Supabase MCP security advisor no longer reports the source-actionable mutable-search-path warning for `public.guard_trip_kind()`. Remaining warnings are the non-relocatable `pg_net` extension placement, intentionally authenticated SECURITY DEFINER RPCs, and an Auth password setting.
- Focused Supabase MCP positive-path proof passed 3/3: `create_trip_with_self()` still creates real group trips, `add_trip_person_by_email()` still adds people to real group trips, and the created group trip contains Alice and Bob.

## 2026-06-07 10:16 BST

Started remote execution of the remaining unmodified pgTAP files. `01_schema.sql` passed 47/47 assertions. The first manual MCP execution of `02_constraints.sql` failed 1/20 because I transcribed the KWD split fixture with the previous expense ID in the MCP query; the checked-in file already uses the correct KWD expense ID, so this is a rerun issue rather than a repo defect. Rerunning with the exact local fixture value.

## 2026-06-07 10:21 BST

Completed remote pgTAP execution for the full current test suite against the development Supabase database. All nine files are green:

- `01_schema.sql`: 47/47
- `02_constraints.sql`: 20/20 after rerunning the exact checked-in fixture
- `03_triggers.sql`: 9/9
- `04_rls.sql`: 26/26
- `05_edge_cases.sql`: 10/10
- `06_expense_payments.sql`: 21/21
- `07_settlements.sql`: 9/9
- `08_activity_notifications.sql`: 17/17
- `09_non_group.sql`: 27/27

Total remote pgTAP coverage in this pass: 186/186 assertions.

## 2026-06-07 10:21 BST

Final local/live checks for this continuation:

- `bash supabase/tests/00_sql_assembly.sh` passed; generated baseline is up to date.
- `cd Packages/TabCore && swift test` passed 96 Swift Testing tests.
- `git diff --check` passed.
- Supabase MCP security advisor remains clean for the fixed mutable-search-path issue. Remaining warnings are unchanged: `pg_net` is installed in `public` but the installed extension version is non-relocatable, the authenticated SECURITY DEFINER RPCs are intentionally exposed and covered by auth checks/tests, and leaked-password protection is an Auth project setting.

## 2026-06-07 13:24 BST

After the goal resumed, ran app-level simulator tests through XcodeBuildMCP with `TAB_MOCK_AUTH=1` on the `Tab` scheme, project `/Users/rithwikshetty/Downloads/dev/tab/Apps/Tab/Tab.xcodeproj`, simulator `iPhone 17` (`AEDDE485-459F-47E0-A5DA-65F3CA770D7D`). The MCP call timed out at 120 seconds, but the underlying `xcodebuild` process completed. Result bundle `/Users/rithwikshetty/Library/Developer/XcodeBuildMCP/workspaces/tab-ae6a56a09c0c/result-bundles/test_sim_2026-06-07T12-20-57-527Z_pid5681_fc03f6cf.xcresult` reports 36 total tests, 36 passed, 0 failed, 0 skipped.

## 2026-06-07 13:25 BST

Ran an additional source/live SQL security consistency audit without delegated workers:

- Source and generated baseline contain none of the removed vulnerable policy names (`activity_log_insert_member`, soft-delete table DELETE policies, or `profiles_select_authenticated`).
- Source inspection shows SECURITY DEFINER functions have explicit `set search_path`.
- Live catalog query returned no SECURITY DEFINER project functions without a fixed search path, no `anon`-executable project functions, and no authenticated execution on internal trigger/helper functions.
- Live policy catalog returned no direct `activity_log` INSERT policy, no DELETE policies on `trips`/`categories`/`expenses`/`settlements`, and no broad authenticated profile select policy.
- `bash supabase/tests/00_sql_assembly.sh` passed and `git diff --check` passed after the audit.

No new finding was identified in this pass.

## 2026-06-07 13:29 BST

User explicitly approved delegated Codex Security fanout and reiterated that the development database can be recreated or cleaned as needed. Resuming the official Deep Security Scan workflow from a fresh scan bundle, with shared repository-wide discovery worklists created before worker dispatch.

## 2026-06-07 13:43 BST

Deep Security Scan round 1 completed with six usable discovery workers over the authoritative 158-row repository worklist. Closed all worker threads before merge. Canonical merge artifacts were written under `/tmp/codex-security-scans/tab/14cf1da_20260607T122838Z/artifacts/`, producing six round-1 candidate clusters and aligned discovery ledgers. Because round 1 added new canonical clusters, the scan must continue to round 2 before centralized validation.

## 2026-06-07 14:00 BST

Deep Security Scan round 2 completed with six usable discovery workers. Closed all worker threads before merge. Round 2 produced 38 upstream worker candidates, all of which merged back into the six existing canonical clusters after remediation-subsumption review. No new canonical clusters were added, so discovery reached terminal state `saturated`. Validation phase is starting from the canonical discovery artifacts in `/tmp/codex-security-scans/tab/14cf1da_20260607T122838Z/artifacts/`.

## 2026-06-07 15:02 BST

Validation and attack-path analysis completed for the six canonical scan candidates. All six survived as reportable: direct `trip_people` hard deletes, same-trip receipt overwrite/delete, group invite account enumeration, non-group invite account enumeration/force-linking, unfiltered auth callback handling, and shared profile reads exposing `activity_last_seen_at`. Starting a TDD fix pass across DB policies/RPCs plus the matching app sync/auth changes.

## 2026-06-07 15:36 BST

Completed the TDD fix pass for the six validated findings:

- Removed direct `trip_people` DELETE access; client hard deletes now have no effect.
- Bound receipt storage reads/writes to a live expense receipt path, with writes limited to the expense creator, and moved app receipt uploads after the expense row is pushed.
- Changed group and non-group email-add flows so registered emails remain pending until that user signs in and claims the row; the RPCs no longer query `auth.users` for other participants.
- Added local auth callback URL validation before handing URLs to Supabase Auth.
- Reworked shared profile display access to use `visible_profiles` as a `security_invoker` view over non-sensitive columns. `activity_last_seen_at` remains on `profiles` but authenticated users only have SELECT on non-cursor profile columns.

Verification:

- App focused red/green: the new auth callback test initially failed before `AuthService.isExpectedAuthCallbackURL` existed, then passed after implementation.
- Remote Supabase focused TAP proof passed 16/16 after applying the DDL through MCP. The proof covered profile cursor denial, pending-only registered invites, direct membership delete denial, receipt creator ownership, non-group pending/claim behavior, storage policy helper use, and absence of `trip_people` DELETE policies.
- Supabase security advisors no longer report the `security_definer_view` error after switching `visible_profiles` to `security_invoker`. Remaining warnings are unchanged/known: `pg_net` in public, intentionally authenticated SECURITY DEFINER RPCs, and Auth leaked-password protection.
- `bash supabase/tests/00_sql_assembly.sh` passed.
- `git diff --check` passed.
- `cd Packages/TabCore && swift test` passed 96/96 after clearing a stale `.build` test-bundle loader hang.
- XcodeBuildMCP simulator test wrapper timed out at 120 seconds, but the underlying result bundle `/Users/rithwikshetty/Library/Developer/XcodeBuildMCP/workspaces/tab-ae6a56a09c0c/result-bundles/test_sim_2026-06-07T13-29-21-742Z_pid5702_4ff7416c.xcresult` completed with 38 total tests, 38 passed, 0 failed, 0 skipped.
