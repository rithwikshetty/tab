# 2026-06-11 — App-wide snappiness audit and fixes

## Goal

User asked: "is there any part in this app that is making it not snappy in general?
… go through each and every part … you can make changes if needed. snappy, not abrupt, keep things native."

Full sweep of `Apps/Tab/Sources` (+ TabCore where called per-render) for anything hurting
perceived snappiness: main-thread blocking, per-render formatter creation, redundant
recomputation, sync stalls, artificial delays.

## 2026-06-11 — Audit fan-out complete

Ran four parallel read-only audits (data/sync layer, main screens, entry flows,
components/utilities). Candidate findings, to be verified against actual code before fixing:

- NumberFormatter created per call in `MoneyFormatter` (called per row in lists).
- DateFormatter created per row/section in `ActivityPresenter`; ISO8601DateFormatter per day in `OverviewPresenter`.
- `CurrencyCatalog.search` re-folds every currency name per keystroke; `CurrencyPickerSheet` normalizes selection per row.
- `RealtimeService.handleChange` triggers a full `pullAll()` on every single table change — no coalescing.
- `RootView` re-pulls everything on every foreground with no throttle.
- `SyncService.pullActivity` does a per-row existence fetch (up to 300 sequential fetches).
- `SyncService.pushPendingReceiptUploads` fetches all expenses to find the few with receipts.
- `TripListView.cards` / `TripDetailView` presenters recomputed every body evaluation (BalanceEngine per trip per render).
- `SettleUpFormView.currentBalances` re-runs BalanceEngine per keystroke.
- `TripExporter` creates a NumberFormatter per spreadsheet cell.
- Possible splash-screen artificial delay to check in `SplashView`/`RootView`.

Next: read each site, confirm, fix the high-confidence ones.

## 2026-06-11 — Findings verified, fixes applied

Verified each candidate against the code. Confirmed and fixed:

1. **Splash gated every launch ~2.4s** (`SplashView.runAnimation`) — compressed the same
   word→dot→curve→dot choreography to ~1.5s to handoff. Biggest single perceived-speed win.
2. **`MoneyFormatter` built a fresh `NumberFormatter` per call** (`plainAmountString`,
   `format`, `formatSymbol`) — called per row in every list. Now cached per fraction-digit
   count (plain/posix + grouped variants).
3. **`ActivityPresenter` built a `DateFormatter` per feed row/section** — now three static
   cached formatters (time, same-year day, other-year day).
4. **`OverviewPresenter` built `ISO8601DateFormatter` per day bar + `DateFormatter` per day
   label** — now static.
5. **`TimelinePresenter` built `ISO8601DateFormatter` per day + label formatter per call;
   `TripPresenter.monthYear` per call** — now static.
6. **`TripExporter.formatDecimalForXML` built a `NumberFormatter` per spreadsheet cell** — now static.
7. **`TripListView` recomputed `cards` (BalanceEngine per trip) ~4× per render** via
   `activeCards`/`completedCards` chained computed properties — hoisted into body locals.
8. **`TripDetailView` ran all three tab presenters (timeline/balances/overview) on every
   body eval** regardless of visible segment — timeline/overview now computed only inside
   their active segment branch.
9. **`ActivityView.sections` evaluated twice per render** (isEmpty + ForEach) — hoisted.
10. **`CurrencyCatalog.search` re-folded all ~170 currency names per keystroke** — folded
    names precomputed once; `CurrencyPickerSheet` also normalized selection per row → once per render.
11. **`SyncService.pullAll` had no reentrancy guard** — launch fired it twice (.task +
    scenePhase), realtime/refresh could stack overlapping full pulls. Added coalescing:
    in-flight pull + one queued trailing pull.
12. **`RealtimeService.handleChange` ran a full `pullAll` per realtime event** — now debounced 400ms.
13. **`RootView` pulled everything on every scenePhase activation** — now only on a real
    background→active transition (cold launch covered by `.task`).
14. **`pullActivity` did up to 300 per-row existence fetches** — one batched ID fetch.
15. **Receipt-upload scan fetched all expenses** — now predicate-filtered to rows with a receipt path.

Deliberately NOT changed (verified fine or out of scope):
- `SyncMerge` per-DTO fetch pattern and reconcile full-table fetches: needed for
  "local rows missing from remote set" semantics; fine at this app's scale. Revisit only
  if pulls measurably stall with large datasets.
- `ExpenseEntryView` per-keystroke split recomputation: pure Decimal math is microseconds;
  the real per-keystroke cost was formatter creation (fixed in MoneyFormatter).
- `SettleUpFormView.currentBalances` per render: one BalanceEngine run per keystroke is
  sub-ms at realistic trip sizes after the formatter fix.
- Static formatter caching already correct in ExpenseEntryView/ExpenseDetailView/
  SettleUpFormView date rows; Haptics, Avatar tones, ExpenseDates all fine.

Next: TabCore swift test, app build + unit tests.

## 2026-06-11 — Validation complete

- `Packages/TabCore` `swift test`: 108 tests, all passing (covers the CurrencyCatalog search index change).
- App unit tests (`TabTests` on iPhone 17 Pro sim): 67 tests, all passing — includes
  MoneyFormatter, ActivityPresenter, OverviewPresenter, BalancePresenter, TripExporter suites
  that exercise every cached-formatter change.
- Smoke run on simulator with mock auth: splash completes on the tightened timeline and
  hands off to the signed-in Trips tab normally.

Changes left uncommitted for review.

## 2026-06-11 — Critical bug found in own change during pre-deploy re-review

Adversarial re-check of the three untested sync-trigger changes before sign-off:

- **`RootView` foreground pull condition was broken.** iOS foregrounds via
  background → inactive → active, so `previous == .background && phase == .active`
  never matched — the catch-up pull would silently never fire and the app would only
  sync on launch, realtime, or manual refresh. Fixed with a `wasBackgrounded` flag set
  on `.background` and consumed on `.active`.
- `pullAll` coalescing and the realtime debounce re-traced: reentrancy, cancellation,
  and stream-blocking all check out. Only soft consequence: pull-to-refresh's spinner
  can end early when a pull is already in flight.

Re-ran TabTests after the fix: 67/67 passing.

## 2026-06-11 — Tab bar pop-in fix

User report: after pushing Add Expense and going back, the tab bar was missing for a beat,
then blinked in. Root cause confirmed as a known SwiftUI limitation (Apple dev forums
thread 711128): `.toolbar(.hidden, for: .tabBar)` attached to the pushed screen ties bar
visibility to that screen's lifecycle, so on pop the bar is only restored after the
transition completes. Present in release builds too — not a debug artifact.

Fix: removed the per-destination `.toolbar(.hidden, for: .tabBar)` modifiers in
`RootView.destination()` and replaced them with path-driven visibility — each tab's
NavigationStack gets `.toolbar(tabBarVisibility(for: path), for: .tabBar)`, where the
helper keeps the bar for root lists + trip/friend detail and hides it for deeper routes
(same visibility matrix as before, now keyed to the path change so the restore coincides
with the pop instead of trailing it).

Validation: all 6 TabUITests pass (they tap through Trips → add expense → back → detail
flows and tap tab-bar buttons, which would fail if the bar were wrongly hidden).
Visual feel on device still needs a human eyeball.
