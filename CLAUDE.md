# CLAUDE.md — roam

Project guidance for Claude Code. Read this before changing anything.

## What roam is

A Splitwise replacement for tracking expenses on group trips. Private friend-group use, no monetisation, no ads. iOS-first (iOS 18+). Future direction: itinerary, analytics — explicitly out of scope for V1.

Pain points being solved: Splitwise's paywall, ads, and aggressive upsells.

## Architecture at a glance

```
roam/
├── PRD.md                      ← Source of truth for product scope, schema, decisions.
├── design/
│   └── mockups.html            ← Three theme directions (Sage chosen). Source of truth for design tokens.
├── Packages/
│   └── RoamCore/               ← Swift Package — pure-logic modules, fully unit-tested.
│       ├── Package.swift
│       ├── Sources/RoamCore/
│       │   ├── Money.swift
│       │   ├── SplitType.swift
│       │   ├── Models.swift
│       │   ├── SplitCalculator.swift     ← Pure: expense splitting (equal, exact).
│       │   ├── BalanceEngine.swift       ← Pure: per-currency pairwise balances.
│       │   ├── TripStateDeriver.swift    ← Pure: active vs completed derivation.
│       │   └── ConflictResolver.swift    ← Pure: LWW with delete-wins + writeID tiebreaker.
│       └── Tests/RoamCoreTests/
└── supabase/                   ← Postgres schema + RLS + DB tests.
    ├── migrations/
    └── tests/
```

The iOS app target will be added later under `Apps/` (or root) and depends on `RoamCore` via local SwiftPM. Supabase hosts auth + realtime + storage + edge functions; the app is offline-first with sync.

## Tech stack — locked

- **iOS 18+**, SwiftUI, SwiftData, Observation, Swift 6 strict concurrency.
- **Swift Testing** (`@Test`, `#expect`, `@Suite`) — not XCTest.
- **Supabase** (Postgres 17.6, EU-West-1, project `gaseuxsieddlksxtdliq`) for auth (Apple Sign-In + email magic link), realtime, storage, edge functions.
- **Decimal** for all money math. **Never Double.**
- **Multi-currency, no FX conversion** — per-currency pairwise balances only.
- **Last-write-wins** conflict resolution with delete-wins + UUID `writeID` tiebreaker on identical timestamps.
- **Soft delete** on mutable user-visible records (`deleted_at`); 30-day window before hard purge.
- **Invite-link only** trip joining (deep links).
- **Realtime** on the currently-viewed trip only.

## Conventions

- **Pure-logic modules go in `RoamCore`** with no UIKit/SwiftUI/Foundation-app imports beyond what's strictly needed. Everything in `RoamCore` is `Sendable`. Pure modules are `enum` (not `struct`) to make instantiation impossible.
- **Balance computation uses canonical pair-key** (sorted UUIDs, lo/hi): positive amount means `hi` owes `lo`. Always emit both mirrored `UserBalance` rows when surfacing to callers.
- **Equal-split remainders** distribute 1 cent at a time to participants with lexicographically lowest UUIDs (deterministic, not random).
- **Exact-split** validates: sum matches total, no missing participants, no extras. Throws on mismatch.
- **No `XCTest`.** All tests are Swift Testing (`import Testing`).
- **Tests live in `Tests/<TargetName>Tests/`** — canonical SPM layout.
- **`.build/` and `.swiftpm/` are gitignored** — never commit them.

## Database

- Pre-launch default: there are no real users. Prefer destructive schema evolution and full DB recreation/reset over compatibility-preserving migration chains.
- Unless the user explicitly asks to preserve existing data, agents may drop and recreate tables, policies, functions, triggers, and related DB objects.
- Dummy/seed data is disposable. Recreate and reseed freely when validating features.
- Canonical schema lives in `supabase/schema.sql`. Update it directly for schema changes.
- Migration strategy is baseline-first: rewrite/squash baseline files aggressively; do not create incremental migration chains unless the user explicitly asks.
- For agents with Supabase MCP access, use MCP for remote destructive DB work. Prefer `apply_migration` with the current baseline/destructive SQL; use `reset_branch` for disposable Supabase development branches.
- CLI fallback/human reset command: `./supabase/scripts/recreate_db.sh` (uses `supabase db reset` non-interactively).
- Receipt storage objects/buckets cannot be deleted with raw SQL. Use `./supabase/scripts/clear_receipts_storage.sh`; pass `SUPABASE_SERVICE_ROLE_KEY` and `--delete-bucket` to delete the bucket itself.
- Remote DB resets do not clear local SwiftData. If stale trips still appear in the app, uninstall the app from the simulator/device or reset simulator content.
- DB tests live in `supabase/tests/` as pgTAP `.sql` files.
- **RLS is mandatory** on every public table. Every test must verify both the allow and deny path.
- Mutable synced row-tables use `updated_at` + `write_id` (UUID), plus `deleted_at` where the row is soft-deleted.
- Direct `trip_members` insert is forbidden for clients. Trip creation auto-adds the creator; invite joins go through `create_trip_invite` + `join_trip_with_invite`.
- Expense + split writes must be transactional; the DB enforces split totals and trip-member references for payers, participants, settlements, categories, and mute prefs.
- Trip access derives from membership in `trip_members` — RLS policies all read from it.
- Default remote apply path for agents is Supabase MCP. Use `./supabase/scripts/recreate_db.sh` when MCP is unavailable or when a human wants a terminal command.

## What NOT to do

- **No V2 scope creep.** Itinerary, analytics, simplified debts (Splitwise's "balance simplification"), multi-payer per expense, percentage/shares splits, placeholder members, payment-app deep links (Venmo/PayPal links), activity-log UI, currency conversion, Android — all explicitly deferred per PRD. Don't implement them speculatively.
- **No Double for money.** Decimal only. If you see a `Double` near money, fix it.
- **No `XCTest` migrations.** Stay on Swift Testing.
- **No mocking SwiftData or Supabase in unit tests.** RoamCore is pure — it doesn't need mocks. Integration tests use real Supabase (separate test schema or branch).
- **No backwards-compat shims, no feature flags for in-flight work, no deprecated/legacy aliases.** Change the code; we have no prod users yet.
- **No emojis in code or commits** unless the user explicitly asked for them. (Emojis in `mockups.html` are intentional — categories.)

## Running things

```bash
# Swift tests
cd Packages/RoamCore && swift test

# Open mockups
open design/mockups.html

# Supabase — destructive reset/recreate (default for this project)
# Agents: prefer Supabase MCP when available. CLI fallback:
./supabase/scripts/recreate_db.sh
```

## Where to find things

- **Product scope, schema, decisions, out-of-scope list** → `PRD.md` (49 user stories, all decisions recorded).
- **Design tokens (Sage palette)** → `design/mockups.html` — Sage hex values are the locked source of truth; port them to the Asset Catalog when scaffolding the app.
- **Supabase project ID** → `gaseuxsieddlksxtdliq` (EU-West-1, Postgres 17.6).
- **MCP servers** → `.mcp.json` (Supabase MCP is HTTP-typed).
