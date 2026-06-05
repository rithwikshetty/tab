# Last Two Commits Review

## 2026-06-05 00:00 UTC - Goal

Review the last two commits on `feat/trip-overview` for correctness, architecture fit, dependency breakage, and test coverage. Include staged and unstaged changes per the review workflow, fix concrete issues directly, and run focused validation.

## 2026-06-05 13:08 UTC - Initial scope

The last two commits are `370a431 fix(sync): decode expense_date date-only column so expenses pull` and `c88362b fix(sync): isolate per-table pulls so one failure can't blank the rest`. `git diff` and `git diff --cached` were empty before creating this review log, so the reviewed product changes are the two requested commits.

## 2026-06-05 13:11 UTC - Date-only decode issue

Found a concrete off-by-one risk in the new `ExpenseDTO` decoder: parsing `expense_date` as UTC midnight makes local date formatters west of UTC render the previous calendar day. Patched the decoder to represent date-only rows at UTC noon, removed the shared DTO `DateFormatter`, and expanded `SyncDecodingTests` with a west-of-UTC regression assertion.

## 2026-06-05 13:12 UTC - Validation

Validation passed after the patch: XcodeBuildMCP `test_sim` for `TabTests` with `TAB_MOCK_AUTH=1` passed 22 tests, `swift test` in `Packages/TabCore` passed 84 tests, and `git diff --check` reported no whitespace errors.
