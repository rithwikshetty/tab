# 2026-06-10 — Full-repo correctness bug scan

## Goal

First structured audit of the whole app (built with an older model). Priority order: offline-first sync path, money math, Supabase schema/RLS, app-layer screens/presenters. Evidence-first: every finding validated against a real code path with counterevidence checked. Apple-framework claims verified against developer.apple.com per new working agreement.

## 2026-06-10 — Baseline

- `cd Packages/TabCore && swift test` → 96/96 pass in 9 suites.
- Scan split: orchestrator took `Services/` + `ConflictResolver` (sync seam); three parallel auditors took supabase/sql + pgTAP, TabCore money math + repo-wide Double sweep, and Screens/Models/Components.

## 2026-06-10 — Sync seam findings (orchestrator pass)

- **ConflictResolver is dead code** — zero call sites outside TabCore tests. The documented LWW + delete-wins + writeID-tiebreak policy is not executed anywhere.
- **Client merge is remote-always-wins**: every `upsert*` in SyncService overwrites local rows whenever writeIDs differ, even when `pushedWriteID != writeID` (pending local change). Only `pullMutes` has the dirty guard. Pull-only entry points (scenePhase active in RootView:147, `.refreshable` on 5 screens, realtime → `pullAll`) mean offline edits are silently wiped on foreground, and online edits can be reverted mid-race.
- **Server stomps write_id**: `set_sync_fields()` (00_extensions.sql) regenerates write_id + updated_at on every insert/update, ignoring client values. Net conflict policy is "last to arrive at server wins".
- Expense date: entry stores wall-clock `.now`, push serializes the **UTC** calendar date (SyncService dateOnlyFormatter), pull anchors at UTC noon → ±1 day shift across timezones; confirmed independently by the app-layer auditor with Apple doc citations.
- Trip created offline then soft-deleted resurrects (pushTrip ignores deletedAt on first create).
- Expense saves bump `trip.writeID` for activity ordering → pushes stale trip name, can clobber a concurrent remote rename.
- signOut() leaves all local SwiftData; next account on device sees prior user's data; never-pushed rows are never reconciled away.
- Suppressed after verification: Decimal-via-JSON precision loss (exact on modern Foundation, tested empirically); receipt re-upload loop (no-ops correctly); reconcile cascade assumptions (delete rules verified).

## 2026-06-10 — Money audit (subagent)

- **HIGH**: BalanceEngine multi-payer proportional shares never quantized to minor units → un-settleable dust (e.g. 10×20/30), trips stuck active forever. Existing tests only use divisible ratios. Verified at BalanceEngine.swift:102.
- MEDIUM: `sanitizeAmountInput` corrupts value on currency switch (USD 123.45 → JPY 12345, saves cleanly) and on pasted grouping separators.
- No Double-near-money violations repo-wide. SplitCalculator remainder/UUID-ordering/JPY/KWD all verified correct.

## 2026-06-10 — SQL/RLS audit (subagent)

- **HIGH**: baseline migration cannot apply to a fresh DB — 17_privileges.sql revokes on `resolve_or_create_non_group_container` defined in file 19 (baseline lines 2156 vs 2333, verified). Masked on the dev DB because destructive_teardown.sql doesn't drop that function.
- MEDIUM: claim-steal — `create_trip_with_self` + non-group resolver upserts set `user_id = v_actor` on email conflict without the `user_id is null` guard that `claim_trip_people_for_current_email` has.
- MEDIUM: `|` accepted in participant emails pollutes `member_signature` identity for non-group containers.
- RLS otherwise solid: all 11 tables covered, membership-scoped, WITH CHECK present. pgTAP deny-path gaps: expense_payments/expense_splits/push_devices/trip_mute_prefs.

## 2026-06-10 — App layer audit (subagent; Apple-doc-verified)

- HIGH: expense date shift (same root cause as sync seam finding; merged).
- MEDIUM: TripExporter exports payment *mode* (equal/exact) in the "Payment Method" columns; tests' fixtures mirror the bug. TripDetailView unsubscribes realtime when pushing deeper into the same trip (`.task`/`onDisappear` semantics confirmed against Apple docs). PaymentSplitView exact-payer dead-end when untoggling to one payer after edits. ActivityView unread highlight wiped on pop-back (onAppear re-runs).
- LOW: Overview chart merges same day-number across months (Swift Charts categorical x); CONTEXT.md vs code drift on own-actions in Activity; no double-submit guards; TripPeopleSheet suggestion race; `ExpenseListPresenter` dead code.

## Outcome

Consolidated severity-ranked report delivered in session. Headline: the offline-first conflict layer is not actually implemented end-to-end (dead ConflictResolver, remote-wins client merge, server-regenerated write_ids) — needs a design-true fix pass before any multi-device use. No fixes applied yet; scan was read-only.

## 2026-06-10 — Fix campaign begins (TDD)

User authorized full end-to-end fixes, DB recreation, dead-code deletion, deployment prep. Working test-first.

### TabCore (108 tests green, was 96)
- BalanceEngine: RED (dust reproduction: 6.666… shares, debtor totals 9.99…) → GREEN: minor-unit quantization with largest-remainder distribution, lowest-UUID tiebreak. Pinned settle-to-zero and JPY whole-unit behavior.
- ConflictResolver: new `merge(local:localIsDirty:remote:)` API + `WriteStamp` for sync pulls — clean local always applies remote; dirty local goes through LWW + delete-wins; same writeID converged. 6 new behavior tests.
- SplitCalculator/PaymentCalculator: duplicate-participant guard (`duplicateParticipant`/`duplicatePayer`) — RED showed [A,A,B] exact splits totalling 150.
- TripAnalytics: tie-break now matches doc (uncategorized last).

### SQL layer (12 pgTAP suites green, was 9)
- Baseline fresh-apply RED reproduced live (42883 on revoke at baseline:2156); fixed by moving resolve_or_create_non_group_container revoke/grant into 19_rpc_non_group.sql. Teardown completed with 11 missing function drops (it had been masking the bug). recreate_db.sh verified end-to-end; root cause of its earlier failure was the masked ordering + incomplete teardown.
- Added supabase/scripts/run_db_tests.sh — repo previously had no pgTAP runner.
- New suite 10_claim_guards.sql: RED confirmed the non-group resolver steal (user_id reassigned) and `|` signature injection; create_trip_with_self steal was accidentally blocked by trip_user_uniq (23505 crash, wrong semantics). GREEN: WHERE-guards on both email-conflict upserts + clean 42501 + idempotent same-account retry preserved.
- New suite 11_sync_lww.sql (19 assertions): server now respects client write_id/updated_at, silently skips stale writes (LWW + write_id tiebreak), never resurrects tombstones (delete-wins), stamps fresh for metadata-less writes. set_sync_fields rewritten (jsonb-based deleted_at so tables without the column work); create_expense_with_payments_and_splits carries client metadata and skips ledger replacement when the row write was stale. One real trigger bug caught by tests mid-cycle: equal-timestamp writes were being re-stamped instead of tiebroken.
- New suite 12_rls_deny_gaps.sql: deny paths for expense_payments/splits/push_devices/trip_mute_prefs (policies were correct; now pinned).

## 2026-06-10 — App layer fixes (TDD, Apple-doc-verified)

New pure/testable units, each RED→GREEN with real in-memory SwiftData (no mocks):
- `SyncMerge` (new): every pull upsert now routes through `ConflictResolver.merge` — dirty local rows survive stale pulls, clean rows take remote, delete-wins both directions, orphaned expenses reattach to their trip. Replaced all of SyncService's remote-always-wins upserts. Push side now sends updated_at/write_id (trips/expenses RPC/settlements/deletes); never-pushed trip tombstones are purged instead of pushed live; settlement nil-trip guard; per-row push failures surfaced via phase.
- `ExpenseDates` (new): save anchors the user's local calendar day at UTC noon; push serializes in UTC. Round-trip tests in Sydney/Auckland/LA/Lisbon. Removed the wall-clock→UTC-date push bug.
- `LocalStore.wipe` (new): sign-out clears all SwiftData (object-level deletes to satisfy the mandatory ExpenseSplit→Expense inverse). Wired via AuthService.onSignedOut, covering mock + real + expired-session paths.
- `MoneyFormatter.convertAmountText` (new) + rewritten `sanitizeAmountInput`: currency switch preserves value (USD 123.45 → JPY 123); pasted grouping separators (1,234.56 / 1.234,56) parse correctly; zero-decimal currencies truncate instead of concatenating.
- `EmailValidator` (new, shared): replaces TripPeopleSheet's `.contains("@")` and NonGroupExpenseFlowView's duplicate validator; rejects the `|` delimiter.
- TripExporter: Expense sheet "Payment Method" now reads paymentMethodRaw; payments sheet column renamed "Payment Mode". Added an extractData-level test (the old workbook test fixtures had encoded the bug).
- PaymentSplitView: lone-payer exact-mode dead-end fixed (reseed to full total). Draft-level tests.
- Realtime: `unsubscribe(from:)` scoped — verified against Apple docs that onDisappear fires on child push, so a child screen can't tear down the trip's subscription and a fast trip switch can't kill a newer subscription.
- ActivityView: snapshot the highlight cursor once per visit (guard nil) so pop-back doesn't wipe "unread this visit".
- OverviewView: daily chart plots the unique per-day key (was day-of-month string → May 9 + June 9 collapsed into one bar); axis still shows the day number.
- Double-submit guards (isSaving) on ExpenseEntry/SettleUp/NewTrip.

Dead code removed: `ExpenseListPresenter`, five unused Insert DTOs, NonGroupExpenseFlowView's per-process-Hasher `deterministicID` (avatar tones now stable via `AvatarTone.deterministic(forEmail:)`, shared with FriendsPresenter). Doc drift fixed: CONTEXT.md Activity own-actions, CLAUDE.md recreate_db.sh description + run_db_tests.sh.

## 2026-06-10 — End-to-end verification

- TabCore: 108/108. App (TabTests): 67/67. pgTAP: 12 suites green against a freshly recreated remote DB (build_schema --check clean, recreate_db.sh end-to-end OK).
- App builds with zero warnings; launches in the simulator under TAB_MOCK_AUTH=1 to the Trips tab (native tab bar + FAB render correctly).
- Deployment readiness: secrets gitignored (only .example templates tracked), DEBUG seeds gated behind #if DEBUG, no build artifacts tracked.
- Sim note: repeated "Application failed preflight checks" launch failures cleared only after `simctl shutdown all` + explicit `simctl boot` + `bootstatus` wait. Erase alone wasn't enough.

## Outcome

All validated findings from the scan are fixed test-first. The offline-first conflict layer is now real end-to-end: client-authoritative write_id, server-enforced LWW + delete-wins, dirty-row-protecting pull merge. No fixes left outstanding; no commit made (awaiting user).
