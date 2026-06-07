# ADR-0003: Non-group expense data model

## Status

Accepted — 2026-06-06

## Context

tab is adding [[Non-group expense]]s — shared costs split between people without
creating a [[Trip]] first (the casual dinner) — plus a [[Friends]] tab showing each
person's [[Overall balance]] netted across all trips and non-group expenses.

The whole ledger is keyed on **`trip_person.id`**, a *container-scoped* identity:
`expense_payments.trip_person_id`, `expense_splits.trip_person_id`, and
`settlements.from_person_id/to_person_id` all FK `trip_people.id`, and
`BalanceEngine` works entirely in trip-person-id space. Access control is also
container-scoped: every RLS policy on expenses / payments / splits / settlements /
activity gates on `private.is_trip_member(trip_id)`. There is no per-row, per-expense
visibility path anywhere in the schema.

So a non-group expense needs *some* container to hang its ledger and its access rule
on. The grill landed on "one hidden container per user," but that has a privacy leak:
because access is per-container, every person you split *any* casual expense with
becomes a member of your one bucket and can read *all* of it — including expenses that
don't involve them. The product owner's rule for visibility is explicit: **"if they
are both in the same group, show it to each other; if not, never"** — i.e. a non-group
expense is visible to exactly its participants, no one else.

Three models were designed and judged against the real schema (RLS correctness, reuse,
simplicity, edge cases). The decision is expensive to reverse once non-group data and
balances exist, so it is recorded here.

## Decision

A non-group expense lives in a **hidden, lazily-created `trips` row, deduplicated per
canonical participant set** (a "shadow group"). A pair is just the two-person case.

### Schema

- `trips` gains `kind text not null default 'trip' check (kind in ('trip','non_group'))`
  and `member_signature text` (set only when `kind='non_group'`).
- A partial unique index makes lazy resolution idempotent and **globally** one
  container per participant set:
  `create unique index trips_non_group_signature_uniq on trips(member_signature) where kind='non_group' and deleted_at is null`.
- **`member_signature` is the canonical sort of participants' normalised emails**, not
  their user-ids. Email is the identity key the existing pre-add/claim flow already
  uses, and a `trip_people` row keeps its email after claim — so the signature is
  **stable across sign-in/claim** and needs no repair. `{A,B}` resolves to the same
  container whether A or B creates the expense.
- Everything else is unchanged: `expenses.trip_id` / `settlements.trip_id` /
  `activity_log.trip_id` stay `NOT NULL` and point at the hidden trip; `trip_people` is
  reused verbatim (the shadow group has its own joined/pending rows with
  `UNIQUE(trip_id,email)`); payments/splits/settlements keep their FKs to
  `trip_people.id`.

### Access — zero new RLS

Because a shadow group is a real `trips` row whose participants are real joined
`trip_people` members, **every existing membership policy applies unchanged**: each
participant of `{A,B,C}` is a member of that container and can read/write it; a
non-participant has no `trip_people` row there, so `is_trip_member` is false and both
read and write are denied per the existing rule. This is exactly the product owner's
"same group → see it; else never." `is_trip_person`, `create_expense_with_payments_and_splits`,
the settlement direct-upsert + `validate_settlement_row` path, and
`claim_trip_people_for_current_email` (which already claims across *all* trips) all
apply verbatim.

### New server surface (small)

- `resolve_or_create_non_group_container(participants)` — `SECURITY DEFINER`, mirrors
  `create_trip_with_self` + `add_trip_person_by_email`: computes `member_signature`,
  finds the existing shadow group or creates it with all participants' `trip_people`
  rows (creator joined; others claimed-if-email-matches-a-profile else pending),
  returns the container id + each participant's `trip_person.id`.
- `kind` is made immutable and client-uninsertable: the trips insert policy is
  restricted to `kind='trip'` and a trigger forbids changing `kind`, so shadow groups
  exist only via the definer RPC.
- `suggest_trip_people` intentionally still surfaces people met through non-group
  shadow groups: under the per-set model each such row is a genuine prior split with
  that person (no leakage of unrelated people), so suggesting them — especially in the
  people-first add flow — is correct and useful. (No `kind` filter is applied.)

### Balances — one new pure module

`OverallBalanceAggregator` (pure TabCore) runs the **unchanged** `BalanceEngine` once
per container, then collapses each container's `trip_person.id` to a claim identity
(`user_id` when joined, else `email:<normalised>`), and sums per
`(identityLo, identityHi, currency)` across all containers using `BalanceEngine`'s
existing lo/hi sign convention. No FX — currency stays a partition key. It never
re-implements netting. [[Settle up]] stays per-source; the [[Overall balance]] is
derived.

## Consequences

- One new column + one index + one RPC + two small guards (`kind` immutability,
  suggestion filter). **No RLS rewrite, no nullable `trip_id`, no second ledger-identity
  system.**
- The client treats a `kind='non_group'` container as server-managed: it is created via
  the RPC and pulled read-only; `pushTrips` skips it; `TripListView` filters
  `kind='trip'`.
- One genuinely new pure module (`OverallBalanceAggregator`) + presenter, fully unit-
  tested, plus the Friends tab, friend detail, per-source settle-up, the people-first
  global expense entry, and a `kind` column on `TripEntity`/DTOs.
- Container proliferation: one hidden container per distinct participant set. Acceptable
  — they're hidden, and the per-set model is what gives correct privacy and a single
  shared non-group ledger per set (so settle-up and the per-source breakdown are clean).
- Editing a non-group expense's participant set **re-resolves** the container (moves the
  expense to the `{…}` container for the new set), rather than mutating an existing
  shadow group's membership.

## Alternatives considered

- **One hidden container per user (the grill's literal wording).** Rejected: per-
  container access means every casual counterpart can read your entire personal bucket,
  including expenses that don't involve them — the privacy leak the product owner's rule
  forbids. Per-container RLS cannot express per-expense visibility. Also splits a single
  A↔B debt across A's and B's buckets (two "Non-group" sources).
- **First-class trip-less expenses (`trip_id` nullable + a `peers`/`non_group_participants`
  identity).** Most faithful to the literal "no trip" wording and gives per-expense
  visibility, but the highest blast radius: branches every RLS policy on `trip_id IS NULL`
  with a new per-row helper, makes `trip_id` nullable on three tables, and — because one
  FK column can't reference two identity tables — **drops the hard FKs on the ledger
  columns onto validation triggers**, a real integrity regression. Builds two new
  identity tables against the stated goal of avoiding a second identity system, and
  against CLAUDE.md's "don't overengineer." Rejected.
- **Strictly pairwise non-group expenses.** Would sidestep multi-person visibility
  entirely, but the product owner explicitly wants multi-person casual splits. Rejected.
