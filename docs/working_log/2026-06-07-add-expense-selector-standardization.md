## 2026-06-07 09:11 BST

Goal: standardize the group selector shown by the global Add expense flow so it uses the same dropdown treatment as the existing expense form controls, and do a quick pass for similar unstandardized menu labels.

Initial finding: the group selector in `NonGroupExpenseFlowView` already uses SwiftUI `Menu`, but its visible label is a hand-built capsule with custom colors and a different chevron. The payment-method selector in `ExpenseEntryView` uses the shared `DropdownPill`, which is the better standard. Other nearby `Menu`s are action menus, currency/filter selectors, or split-mode controls with different semantics, so the direct replacement target is the group selector label.

## 2026-06-07 09:13 BST

Implemented the direct standardization: `DropdownPill` now truncates long labels cleanly, and the global Add expense group selector uses that shared pill. The existing UI route test now also asserts that `newExpense.groupMenu` appears after tapping the Trips Add expense button. Validation: `git diff --check` passed, XcodeBuildMCP simulator compile passed with no warnings or errors, and targeted UI test `TabUITests/FriendsFlowUITests/testTripsAddExpenseOpensPeopleFirstPicker` passed.
