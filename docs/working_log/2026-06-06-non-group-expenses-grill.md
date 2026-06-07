# Non-group expenses + Friends tab — grill & mockups

Goal: decide whether/how to support expenses that aren't tied to a trip ("non-group"
expenses) so casual one-off outings don't require creating a trip, plus a global
per-person balance view ("how much do I owe each person overall, across all trips").

## 2026-06-06 — grill decisions (so far)

Resolved during the grill-with-docs session:

- **Non-group expense exists.** A shared cost not attached to any trip. Supports
  multiple participants (not just pairwise) and email pre-add, same as trip expenses.
- **Backing store = one global non-group container per user (Option C/A hybrid).**
  Rather than a second ledger identity system, non-group expenses live in a single
  per-user container that reuses the existing trip/trip_person/payment/split machinery.
  RLS filters it so a user only sees non-group rows where they are payer or participant.
  The container is NOT shown in the Trips tab.
- **New Friends tab.** Tab bar goes Trips·Activity·Settings -> Friends·Trips·Activity·Settings.
  Friends tab lists every person you share a balance with; net per person per currency.
- **Friend detail** shows the global net plus a breakdown by source (non-group + each
  trip) and a timeline of shared expenses/settlements across all sources. Mirrors the
  Splitwise friend view the user referenced.
- **Settle-up is per-source, global net is read-only/derived.** You settle the
  non-group balance or a specific trip's balance; the global number updates as a
  consequence. Deliberately avoids Splitwise's confusing cross-group "settle all"
  (which creates synthetic per-group settlements and de-syncs dashboard vs group
  balances — confirmed via their help docs).
- **FAB becomes "Add expense" globally.** "Create trip" moves to the Trips tab nav bar.
  Open question being mocked: the global add-expense entry flow (people-first vs
  single adaptive form vs group-first) — building options to choose from.

## 2026-06-06 — mockups

Building two mockup files (Sage palette, matching shipped app + expense-entry/v3):

- `design/expense-entry/v4.html` — global & group-aware expense entry, 3 flow options.
- `design/friends/v1.html` — Friends tab, friend detail, per-source settle-up, 4-tab bar.

## 2026-06-06 — implementation kickoff

User picked **Option A** (people-first) for the global add path: from the Friends
tab / FAB, "Add expense" -> Step 1 pick people (You pre-checked, suggestions from
shared-trip contacts, add-by-email) -> Step 2 the form with Group = "No group" by
default. From inside a trip, the form opens directly with Group = that trip and all
members pre-included (no people step). (Briefly considered Option B; reverted to A as
simpler for the new-expense case.) Directives: implement end-to-end with TDD,
verify in the simulator, dummy data OK (dev DB is disposable), handle edge cases,
keep it Apple/app-native, don't overengineer.

Deferred architectural fork to resolve before coding: **how is the non-group context
modeled in the existing trips/trip_people schema?** The grill landed on "one global
container per user, RLS-filtered to participants" but did not resolve the multi-person
access + ledger-identity mechanics (trip_person is container-scoped; non-group
expenses span arbitrary people; all participants must see their own balance). Running
an understanding + design pass to nail this down before writing migrations.

## 2026-06-06 — design decision (ADR-0003)

Ran a 15-agent understanding + judged-design workflow. The judge ranked the
per-creator container first only because it matched the grill's literal words — but
flagged that it leaks: with container-scoped RLS, every casual counterpart becomes a
member and can read your whole bucket. Asked the product owner the privacy question
directly. Answer: **"if they are both in the same group, show it to each other; if
not, never"** — i.e. visible to exactly the expense's participants.

That eliminates the per-creator bucket and selects the **per-set hidden shadow-group**
model, recorded in `docs/adr/0003-non-group-expense-model.md`. Key simplification over
the judge's worry: key the shadow group on the canonical sort of participants'
**normalised emails** (not user-ids) — stable across claim, so no signature-repair, and
`{A,B}` is one globally-shared container regardless of who creates the expense. Net new
server surface: `trips.kind` + `member_signature` + partial unique index +
`resolve_or_create_non_group_container()` RPC + kind-immutability guard + suggestion
filter. No RLS rewrite, no nullable trip_id, no 2nd identity system.

Baseline before build: TabCore 85 tests green; app compiles clean (iPhone 17 / iOS 26.5);
sim defaults set with TAB_MOCK_AUTH=1.

### Build plan (TDD, phased)
1. TabCore `OverallBalanceAggregator` (pure; tests first).
2. DB: `kind`/`member_signature`/index/RPC/guards + pgTAP; rebuild baseline; apply to dev.
3. App sync/entities: `TripEntity.kind`, DTOs, skip non_group in pushTrips, RPC wrapper.
4. App Friends tab + presenter (TDD) + friend detail + per-source settle-up.
5. App global expense entry (Option A people-first) + Group selector row.
6. Dummy data + simulator verification of every flow + edge cases.
7. All tests green (TabCore + app + pgTAP + a UI test); finalise docs.

## 2026-06-06 — Phase 1 done
`OverallBalanceAggregator` + `ClaimIdentity`/`ContainerBalances`/`OverallBalance`/
`SourceBalance` added to TabCore (pure). 11 tests written first (red), then green.
Full TabCore suite 96 green. Aggregate collapses container-scoped trip_person.id ->
claim identity (user_id else email surrogate), nets per (identity-pair, currency)
reusing BalanceEngine's lo/hi convention; `breakdown` gives per-source amounts.

## 2026-06-06 — Phase 2 done (DB)
Decision refinement while implementing the RPC: chose **online-resolve** for the
shared container (client calls `resolve_or_create_non_group_container` at save time;
idempotent by signature). Full offline-first creation of a brand-new participant set
is out of scope for now (would need deterministic ids / convergence); editing an
existing non-group expense is offline-capable. Documented as a known constraint.

Edited `supabase/sql`: 03 (trips.kind + member_signature + partial unique index +
name-check now kind-aware + kind-immutability trigger), 12 (trips insert policy
restricted to kind='trip'), 17 (grants), new 19 (resolve_or_create RPC). Regenerated
baseline; `00_sql_assembly.sh` green. Applied incrementally to dev DB `tab-it` via
Supabase MCP `apply_migration` (additive; dropped old auto-named `trips_name_check`,
added kind-aware constraints — existing trip rows satisfy them). New pgTAP
`09_non_group.sql`: **22/22 green** incl. the privacy cases (Bob can't see
{Alice,Carol}; Carol can't see {Alice,Bob}), idempotency, per-set uniqueness, kind
immutability, client-insert denial, pending->claim. `02_constraints` re-run 20/20
(no regression).

## 2026-06-06 — Phases 3-6 done (app)
- **Phase 3 (sync/entities):** `TripEntity.kind` + `memberSignature`; `TripDTO` carries
  both; `upsertTrip` maps them; `pushTrips` skips `kind=='non_group'` (server-managed);
  `resolveNonGroupContainer(participants:)` added to SyncService; `TripListView` query
  filters `kind=='trip'`.
- **Phase 4 (Friends):** `FriendsPresenter` (list + detail + per-source breakdown +
  shared timeline) over `OverallBalanceAggregator`; `FriendsView`, `FriendDetailView`;
  RootView gains a first **Friends** tab + `.friend` route; friend-detail source rows
  navigate to per-source settle-up (reusing `SettleUpFormView` scoped to the container).
  6 `FriendsPresenterTests` green.
- **Phase 5 (people-first entry):** `NonGroupExpenseFlowView` = step-1 people picker
  (search/suggest + add-by-email) with a Group selector (No group / a trip). On Next it
  resolves the container and **replaces itself** in the nav path with the existing
  `ExpenseEntryView` (so the form + save are 100% reused; post-save returns to Friends).
  Group choice lives on the picker because the ledger needs real trip_person ids before
  the form. "Create trip" moved from the Trips FAB to the Trips nav bar; the FAB is now
  "Add expense" on Friends.
- **Decision (mock/offline):** `resolveNonGroupContainer` uses the RPC when a real
  session exists, else creates the container **locally** by signature (mock auth has no
  session; mirrors how trips/expenses already work offline). The local path is mock-only
  (a cached real session offline still takes the RPC path and surfaces an error), so there
  is no local-vs-server container fork in real use.
- **Phase 6 (sim):** Added `DebugFriendsSeed` (TAB_SEED_FRIENDS=1) — multi-trip +
  non-group, multi-currency, a pending friend. Verified in the iPhone 17 simulator under
  mock auth: Friends tab renders correct cross-source per-currency nets (Sam: owes you
  €30 AND you owe £14 = Tokyo −£20 + non-group +£6; Jamie pending owes £4; Alex €30);
  Trips list shows only real trips; new-trip button in nav bar. Registered new files in
  the Xcode project (classic pbxproj, no synchronized groups).

## 2026-06-06 — Phase 7 (verify + review)
Full green: TabCore 96, app unit 29, app UI 5 (incl. a new `FriendsFlowUITests`
end-to-end: Friends -> Add expense -> invite by email -> form -> Save -> friend appears
owing £10 -> friend detail shows per-source breakdown; all 4 pre-existing PaidBy UI
tests still pass), pgTAP 22+20. Ran an adversarial multi-agent review of the whole
change (DB/RLS, TabCore, sync, SwiftUI) with per-finding verification; 8 confirmed.

### Review fixes applied
- **(critical) Orphaned non-group container for a real user with an expired session.**
  The local-create path was gated on `hasRealSession` (also false when a real session
  merely expired), so such a user would create a local-only container the server never
  learns about → its expense could never push. Re-gated the local path to **mock auth
  only**; a real user with no/expired session now gets `signInRequired` instead. Mock
  never syncs, so this also moots the "clean local rows get reconciled away" concern.
- **(med) Signature divergence on un-normalized emails.** `resolveNonGroupContainer`
  now normalizes participant emails internally before computing the signature (matches
  the server RPC's normalization); idempotent regardless of caller casing.
- **(med) trip relationship not reassigned on sync update.** Added `entity.trip = trip`
  to the `upsertExpense` and `upsertSettlement` update paths so the FK can't silently
  drop to nil on a re-sync (which would have stranded the expense from pushing).
- **(med) RPC race on concurrent same-signature creation.** Wrapped the container
  INSERT in `exception when unique_violation then re-select`, so two clients resolving
  the same brand-new participant set converge instead of one erroring. Re-applied to dev.
- **(low) suggestions vs ADR.** Kept non-group counterparts in `suggest_trip_people`
  (correct + useful under the per-set model — they're real prior splits, no leakage) and
  corrected ADR-0003's text to match (it had said "exclude").

### Review findings deliberately NOT changed
- Adding an explicit `tripID` column to `ExpenseEntity`: a NOT-NULL SwiftData migration
  whose practical failure mode is already closed by the `entity.trip = trip` fix above.
- Forcing ≥2 participants on a non-group expense edit: a self-only expense nets to zero
  (harmless), and single-participant expenses are valid in the model generally.

Re-verified after fixes: SQL baseline regenerated + assembly green; RPC re-applied to dev
and re-checked (5/5 incl. mixed-case normalization); app rebuilt clean; TabTests 29 +
people-first UI test green (30/30); TabCore unchanged (96).

## 2026-06-06 — text-placement / overflow pass
Per request, hardened the new screens against truncation/clipping and verified each in
the simulator with a stress seed (a long name "Bartholomew Featherstonehaugh-Wellington"
+ a large THB 5,631.15 amount + multi-currency):
- Friends list: name `lineLimit(1)`+tail truncation; the overall banner rebuilt as one
  wrapping `Text` per currency (was an HStack of Texts that could clip) — confirmed the
  THB line wraps and stacked multi-currency amounts fit.
- Friend detail: hero name centered + `lineLimit(2)` (wraps over two lines, not cut);
  net lines centered/wrapping; source names `lineLimit(1)`.
- Picker: removed a redundant "Cancel" (the pushed view already has a system back
  chevron), capped the group-pill trip name + participant name/email, and hid the
  "People you split with" header when empty (mock has no server suggestions) in favour
  of a centered hint.
Screenshots confirmed no text outside its box on Friends list, friend detail, and the
picker. Removed the temporary screenshot-only deep-link envs (kept `TAB_START_TAB`).
Rebuild clean (no warnings); FriendsPresenter + people-first UI test still green (7/7).

**Feature complete.** Nothing committed (left staged for review).
