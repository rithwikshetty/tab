# Settle Up Feature — Issue #1

## Goal
Implement mid-trip settlement recording: UI to create/edit/delete settlements, compact timeline rows, and detail view. Backend (DB, sync, BalanceEngine) already exists.

## 2026-05-23 — Design grilling + implementation

### Design decisions (from grilling session)
- Entry point: three-dots menu on TripDetailView (alongside Export to Excel)
- Balance-aware form: From defaults to current user, To defaults to highest-balance counterparty
- Amount pre-filled with full owed balance; editable for partial settlement
- Any trip member can record settlements between any two people (independent dropdowns)
- Compact blue-tinted timeline rows inline with expenses (using Sage.Avatar.slate)
- Read-only detail view with Edit and Delete options
- Mockup created at design/settle-up/v1.html

### Implementation
Files created:
- `Apps/Tab/Sources/Tab/Screens/SettleUpFormView.swift` — settlement creation/edit form
- `Apps/Tab/Sources/Tab/Screens/SettlementDetailView.swift` — read-only detail with edit/delete
- `Apps/Tab/Sources/Tab/Components/SettlementRow.swift` — compact timeline row component

Files modified:
- `RootView.swift` — added Route cases (settleUp, editSettlement, settlement) + navigation destinations
- `TripDetailView.swift` — added Settle Up to menu, replaced expensesSection with timelineSection merging expenses + settlements, added settlement deletion flow
- `ViewState.swift` — added SettlementRowItem, TimelineItem enum, TimelineDay
- `EntityViewState.swift` — added TimelinePresenter for merged expense/settlement timeline
- `Deletion.swift` — added softDelete(settlement:)
- `SyncService.swift` — updated pushSettlements() to handle soft-delete push
- `SupabaseDTOs.swift` — added SettlementDeleteUpdateDTO
- `ExpenseEntryView.swift` — changed InlineDatePicker from private to internal (shared with SettleUpFormView)

### Validation
- Build: succeeded
- TabCore tests: all 66 pass
- No new TabCore logic needed; feature is purely UI wiring

## 2026-05-23 18:24 BST — Review current work

Started a review pass over the unstaged settle-up feature changes. Focus areas: route/navigation wiring, SwiftData persistence and sync semantics, timeline presentation, delete/edit behavior, and focused validation after any fixes.

## 2026-05-23 18:28 BST — Review findings

Found two correctness issues to fix: settle-up prepopulation used the current user as payer even when another member owed them, which would record a payment in the wrong direction and increase the debt; TripDetailView also split the merged timeline back into all-expenses-then-settlements, losing the chronological ordering produced by TimelinePresenter. Also found the balance context copy treated opposite-direction payments as if they settled the debt.

## 2026-05-23 18:34 BST — Review fixes + validation

Fixed settlement prepopulation so the debtor is selected as From and the current user as To when someone owes the current user. Updated balance context to distinguish reducing payments, overpayments, and opposite-direction payments. Updated TripDetailView to render timeline items in presenter order, grouping only consecutive expenses so settlements remain inline. Validation: app simulator build passed; `swift test` in Packages/TabCore passed 66 tests; app-level simulator tests initially hit stale SwiftData simulator state, so the app was uninstalled from the simulator and tests were rerun. The 4 UI tests then passed, and the targeted `TabTests` unit invocation passed 1 test.

## 2026-05-23 18:37 BST — TDD scenarios

Started a red-green-refactor pass for heavier dummy trip scenarios. Scope: app-level settlement prefill behavior driven by real BalanceEngine inputs, then database-facing settlement scenarios if the local Supabase test path is available. Preserving the currently staged settle-up changes and layering new work unstaged.

## 2026-05-23 18:43 BST — TDD results

Added app-level Swift Testing coverage for settle-up prefill using dummy trip people, many expenses, and partial settlements. First red introduced the missing `SettleUpPresenter`; green added `SettleUpSuggestion` and the presenter. Second red proved the presenter wrongly preferred collecting a larger amount from someone else over paying the current user's own debt; green made current-user debts the first default. Refactored `SettleUpFormView` to use the tested presenter. Added `supabase/tests/07_settlements.sql`, which seeds dummy users, 12 expenses, 48 splits, 12 payments, settlements involving joined and pending trip people, and denial paths. The DB test first over-specified RLS as the denial layer; adjusted it to assert the observed rejection path without changing product behavior. Validation passed: `TabTests` 3 tests, `TabCore` 66 tests, SQL assembly, pgTAP files `01` through `07` against the linked database, and a final simulator build.

## 2026-05-23 20:05 BST — Land on main

Added requested clarifying comments around settle-up default selection and the settlement stress test fixture. Preparing to recreate the disposable Supabase database, commit the current main worktree, and push directly to `origin/main` as requested.

## 2026-05-23 20:06 BST — Database recreated

Ran `./supabase/scripts/recreate_db.sh` against the linked Supabase database; destructive teardown and generated schema application both completed successfully. Re-ran `supabase/tests/07_settlements.sql` against the freshly recreated database and all 9 pgTAP assertions passed.
