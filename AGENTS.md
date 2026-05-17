# AGENTS.md — roam

Guidance for AI coding agents (Codex, Cursor, Copilot Workspace, etc.) working in this repo.

This file mirrors [`CLAUDE.md`](CLAUDE.md) — both are kept in sync. If they diverge, `CLAUDE.md` is authoritative.

---

## What roam is

A Splitwise replacement for tracking expenses on group trips. Private friend-group use, no monetisation. iOS-first (iOS 18+). Itinerary and analytics are out of scope for V1.

## Architecture at a glance

```
roam/
├── PRD.md                      ← Source of truth for product scope, schema, decisions.
├── design/mockups.html         ← Three theme directions (Sage chosen). Design-token source.
├── Packages/RoamCore/          ← Swift Package — pure-logic modules.
│   ├── Sources/RoamCore/       ← Money, SplitType, Models, SplitCalculator, BalanceEngine,
│   │                              TripStateDeriver, ConflictResolver.
│   └── Tests/RoamCoreTests/    ← Swift Testing (@Test/#expect), 44 tests.
└── supabase/                   ← Postgres schema + RLS + DB tests.
    ├── migrations/
    └── tests/
```

iOS app target lives at the repo root (or `Apps/`) and depends on `RoamCore` via local SwiftPM. Supabase hosts auth + realtime + storage + edge functions; client is offline-first.

## Tech stack — locked

| Layer       | Choice                                                         |
|-------------|----------------------------------------------------------------|
| Platform    | iOS 18+, Swift 6 strict concurrency                            |
| UI          | SwiftUI + Observation framework                                |
| Persistence | SwiftData (client), Postgres 17.6 via Supabase (server)        |
| Tests       | Swift Testing (`@Test`, `#expect`), pgTAP for DB               |
| Money       | `Decimal` only — never `Double`                                |
| Currency    | Multi-currency, no FX conversion (per-currency balances)       |
| Sync        | Last-write-wins + delete-wins + UUID write-id tiebreaker       |
| Soft delete | `deleted_at` on mutable user-visible records; 30-day purge window |
| Auth        | Apple Sign-In primary + email magic link fallback              |
| Joining     | Invite link only (deep link)                                   |
| Realtime    | Currently-viewed trip only                                     |

## Conventions

- **Pure-logic modules** live in `RoamCore` as `enum` (uninstantiable) with `Sendable` types.
- **Balance pair-key**: sort UUIDs `(lo, hi)`; positive amount means `hi` owes `lo`. Surface both mirrored `UserBalance` rows externally.
- **Equal-split remainder**: distribute 1¢ at a time to participants with lexicographically lowest UUIDs. Deterministic.
- **Exact-split**: validates sum, no missing/extra participants. Throws on mismatch.
- **Tests live in `Tests/<TargetName>Tests/`** (canonical SPM).
- **`.build/` and `.swiftpm/` are gitignored.**

## Database

- Pre-launch default: there are no real users. Prefer destructive schema evolution and full DB recreation/reset over compatibility-preserving migration chains.
- Unless the user explicitly says to preserve existing remote/local data, agents may drop and recreate tables, policies, functions, and related DB objects.
- Dummy/seed data is disposable. Recreate and reseed freely to validate product behavior.
- Canonical schema lives in `supabase/schema.sql`. Update it directly for schema changes.
- Migration strategy is baseline-first: rewrite/squash baseline files aggressively; do not create incremental migration chains unless the user explicitly asks.
- For agents with Supabase MCP access, use MCP for remote destructive DB work. Prefer `apply_migration` with the current baseline/destructive SQL; use `reset_branch` for disposable Supabase development branches.
- CLI fallback/human reset command: `./supabase/scripts/recreate_db.sh` (uses `supabase db reset` non-interactively).
- Receipt storage objects/buckets cannot be deleted with raw SQL. Use `./supabase/scripts/clear_receipts_storage.sh`; pass `SUPABASE_SERVICE_ROLE_KEY` and `--delete-bucket` to delete the bucket itself.
- Remote DB resets do not clear local SwiftData. If stale trips still appear in the app, uninstall the app from the simulator/device or reset simulator content.
- Tests: pgTAP `.sql` files in `supabase/tests/`.
- RLS mandatory on every public table; tests must verify both allow and deny.
- Sync columns on mutable synced row-tables: `updated_at` (timestamptz), `write_id` (uuid), plus `deleted_at` where the row is soft-deleted.
- Trip access derives from `trip_members` — direct member insert is forbidden; joins go through invite RPCs.
- Expense + split writes must be transactional; the DB enforces split totals and trip-member references.

## Don't do these

- No V2 scope creep (itinerary, analytics, simplified debts, multi-payer, %/shares splits, payment-app links, currency conversion, Android).
- No `Double` for money — only `Decimal`.
- No XCTest — Swift Testing only.
- No mocking SwiftData or Supabase in unit tests. RoamCore is pure; it doesn't need mocks.
- No backwards-compat shims, no in-flight feature flags, no deprecated aliases. Change the code — there are no prod users.
- No emojis in code or commits unless the user explicitly asked.

## Running things

```bash
cd Packages/RoamCore && swift test     # Swift tests
open design/mockups.html                # Mockups
# Supabase: destructive reset/recreate (default for this project)
# Agents: prefer Supabase MCP when available. CLI fallback:
./supabase/scripts/recreate_db.sh
```

## Pointers

- **Product scope** → `PRD.md`
- **Design tokens** → `design/mockups.html` (Sage palette is locked)
- **Supabase project ID** → `gaseuxsieddlksxtdliq` (EU-West-1)
- **MCP config** → `.mcp.json`
