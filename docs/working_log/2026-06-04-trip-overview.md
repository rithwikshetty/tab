# Trip Overview (spend) — issue #4

Goal: per-trip spend Overview as a third segment alongside Expenses and Balances. Spend-only
(settlements excluded; net-owed stays on Balances), per-currency, Direction A layout (donut-led).

## 2026-06-04 — design + PRD

- Grilled the design (grill-with-docs). Resolved: Overview = spend only; "spend" shown as both
  **paid** (payment ledger) and **share** (split ledger); currency picker scopes the whole tab
  (hidden when single-currency); daily stacked bars by category, bucketed by expense date.
- Confirmed via the model that currency is per-expense/per-settlement (no trip-level currency),
  so multi-currency trips are real and the picker is necessary.
- Decided compute-locally, **no analytics table**: Overview is a pure derivation from local
  SwiftData, mirroring how BalanceEngine/BalancePresenter already work. Offline-first by
  construction; a server table would be worse (staleness, RLS, wrong offline).
- Added `Overview` to CONTEXT.md glossary; removed "analytics" from the out-of-scope line
  (kept "cross-trip analytics" out, per the issue).
- Published PRD as a comment on issue #4, labelled `ready-for-agent`.
- Mockups: `design/overview/v1.html` — three directions (A donut-led, B editorial, C compact) +
  states (currency picker, single-currency, empty). User picked **Direction A** and chose to
  include the per-person paid/share card.

## 2026-06-04 — implementation (TDD)

- `TabCore/TripAnalytics.swift` (pure, deep module mirroring BalanceEngine). `summarize(expenses:)`
  returns one `TripSpendSummary` per currency: total, perPerson (paid+share), perCategory,
  perDay (with per-category breakdown). Settlements are not a parameter — exclusion is structural.
  8 behaviours TDD'd in `TripAnalyticsTests` (empty, total/currency, multi-payer paid-vs-share,
  total==both ledgers, multi-currency partition, category incl. uncategorized, per-day bucketing,
  soft-delete exclusion). TabCore suite: 84 pass.
- `OverviewPresenter` (in app, mirrors BalancePresenter): thin entity glue + pure `resolve` over
  TabCore summaries with name/category lookups → formatted, ratio'd `OverviewState`. 6 behaviours
  TDD'd in `OverviewPresenterTests` over value inputs (no SwiftData mocking), per TripExporterTests
  precedent. App unit suite: 20 pass.
- `OverviewView` (Direction A) with SwiftUI Charts: currency pill (Menu), donut summary
  (SectorMark, your-share vs total), per-person paid/share rows, category bars, daily stacked
  BarMark. Category colours from `DefaultCategories.tone`, shared between category + daily charts.
- Wired into `TripDetailView`: segment is now `["Expenses","Balances","Overview"]`; builds
  `OverviewPresenter.overview(...)` from `trip.expenses`.
- Verified end-to-end in the simulator (mock auth): created a trip, added Food £240 + Lodging £400.
  Overview renders the donut, 33%-of-spend, per-person paid/share, two category bars (Lodging
  purple / Food terracotta), and a stacked daily bar. Empty state ("Nothing to break down yet")
  confirmed before any expense.

Branch: `feat/trip-overview`. Committed `9d54a10` and pushed.

## 2026-06-05 — summary card UI revision (responsive)

User feedback: the summary card felt crammed (donut + three text rows), and large
currency totals (JPY/INR) would crush a fixed side-by-side layout.

- Removed the "33% of trip spend" line from the card. `OverviewPage.yourSharePercent`
  is still computed and tested; it now feeds the donut's VoiceOver label instead of an
  on-screen row (Total + your-share % read aloud), so it isn't dead data.
- Made the summary layout responsive with `ViewThatFits(in: .horizontal)`: donut **beside**
  the You paid / Your share stats when amounts are short, donut **stacked above** them when
  amounts run long. Text only shrinks (minimumScaleFactor) as a last resort within a layout.
- Updated `design/overview/v1.html` Direction A to match and added a "responsive (the
  cramming fix)" comparison (EUR beside vs large JPY stacked).
- App build green; presenter/analytics tests unchanged.

## 2026-06-05 — summary-card currency + overflow fixes

User feedback on the live card: the total was bleeding into the donut ring, and "GBP £640.00"
repeated the currency three times.

- Added `MoneyFormatter.formatSymbol` (symbol only, e.g. `£640.00`; falls back to code when a
  currency has no distinct symbol). `OverviewPresenter` now uses it for every Overview amount —
  the rest of the app keeps the `CODE symbol` convention. Presenter tests updated to match.
- Donut centre: clamped the total's width well inside the inner radius and lowered
  `minimumScaleFactor` to 0.4, so large totals (e.g. £48,000.00) scale down to fit instead of
  overflowing into the ring. Ring `innerRadius` 0.68 → 0.70, donut 112 → 116.
- Fixed the "Per person · paid vs share" card: horizontal padding 16 → 18 so its title lines up
  with the other cards.
- Verified live in the simulator at the £640 trip: symbol-only, no donut overflow, aligned title.
  TabTests 20/20 green. (Could not auto-inject a five-figure expense to eyeball the extreme case —
  synthetic taps on the sim's small fields were unreliable on the off-display window; the clamp is
  proven by its constraints + the JPY donut in the mockup.)
