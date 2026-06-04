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

Branch: `feat/trip-overview`. Not yet committed.
