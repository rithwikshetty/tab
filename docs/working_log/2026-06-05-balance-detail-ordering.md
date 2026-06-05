# Balance Detail Ordering

## Goal

Fix the reported trip detail issue where balance summary detail names can swap order when moving between Overview, Balances, and Expenses tabs, especially tied owed amounts in the demo trips.

## 2026-06-05 15:27:45 BST

Started diagnosis against the recent overview-related commits. The active worktree already has unrelated uncommitted sync decoding changes and an existing working log from a prior review, so those will be preserved.

## 2026-06-05 15:29:00 BST

Found a likely deterministic-ordering bug in the balance detail path. `BalancePresenter.summaries` sorts rows only by `abs(amount)`, leaving equal amounts unordered, and `BalanceEngine.compute` builds its result from dictionary iteration. Equal balances such as Diego/Chloe or Sam/Alex can therefore render in different orders after tab-driven recomputation.

## 2026-06-05 15:30:00 BST

Added a focused `BalancePresenterTests` regression for tied balance detail rows. The first simulator attempt failed before tests because `iPhone 16` was not installed; after switching XcodeBuildMCP to the booted `iPhone 17 Pro`, the focused test compiled and passed on this hash seed. That does not disprove the bug because the defect is nondeterministic ordering, not incorrect arithmetic.

## 2026-06-05 15:31:00 BST

Applied the fix at two levels: `BalancePresenter` now breaks tied absolute amounts by display name and then UUID, and `BalanceEngine.compute` now emits balances by sorted pair key and sorted currency instead of exposing dictionary iteration order. Added a TabCore test for deterministic engine output order.

## 2026-06-05 15:32:00 BST

Validation passed. Focused simulator unit test `TabTests/BalancePresenterTests` succeeded on the booted iPhone 17 Pro simulator. `swift test` in `Packages/TabCore` passed 85 Swift Testing tests, including the new engine ordering case. Full app unit test run `-only-testing:TabTests` passed 22 tests on the simulator. A final source pass confirmed the top trip balance card and the Balances tab both consume `BalancePresenter.summaries`, so the shared ordering fix covers both visible locations.
