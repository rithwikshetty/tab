# Context — tab

A multi-user, multi-currency group expense tracker for trips. iOS-first, offline-first, private friend-group use; no monetisation.

The current model covers trips, members, expenses, multi-payer payment ledgers, split ledgers, pairwise balances, settlements, categories, receipt photos, and trip export. The server contract also includes an activity log, push devices, and trip mute preferences. V1 does **not** cover itinerary, analytics, simplified debts, payment-app links, currency conversion, Android, or percentage/share split UI.

This file is the project's domain glossary. Only terms meaningful to a domain expert (someone reasoning about expenses, balances, and trips) belong here — implementation specifics live in code.

## Glossary

### Profile
The account-level identity for a signed-in user: display name plus optional avatar. A Profile is not the ledger identity inside a trip; that role is [[Trip person]].

### Trip
A container of trip people, expenses, settlements, categories, activity, and per-user notification preferences. A user can belong to many trips through one joined [[Trip person]] row per trip. State (`active` vs `completed`) is **derived, not stored** — see [[Active / Completed trip state]].

### Trip person
A trip-scoped ledger identity identified by normalized email and display name. It may already be linked to a [[Profile]], or it may be pending until someone signs in with that email. Expenses, payments, splits, and settlements reference trip people so a trip can be planned before every person has opened the app.

### Trip member
A joined trip person: one whose email has been claimed by a signed-in Profile. Trip access is derived from joined trip people. Pending trip people can still appear in ledgers, but they do not grant app access until claimed.

### Email pre-add
Adding a trip person by email before that person has signed in. If the email already belongs to a Profile, the trip person joins immediately. Otherwise it remains pending and is automatically claimed when someone signs in with the same normalized email. There is no global user search; suggestions are limited to people the current user has already shared trips with.

### Category
The expense classification shown on expense rows and exports. Categories are either built-in defaults (`Food & Drink`, `Transport`, `Lodging`, `Activities`, `Shopping`, `Other`) or custom trip-scoped categories. An Expense can use a default category or a category belonging to the same trip.

### Receipt photo
An optional JPEG attached to one Expense. Receipts are private to trip members and are addressed by trip/expense ownership, not by a public URL.

### Expense
A single shared cost incurred on a trip. Has one positive amount, one ISO currency, one description, one expense date, one category, one payment method, optional receipt photo, and **two ledgers**: [[Payment ledger]] and [[Split ledger]]. Each ledger independently sums to `expense.amount`.

Expense creation/editing is atomic at the domain boundary: the expense row, payment ledger, and split ledger must be saved together so a saved active expense is always balanced.

### Payment method
How the expense was paid at a high level: `cash`, `card`, or `bank_transfer`. This is separate from [[Payment mode / Split mode]], which describes how ledger amounts are allocated across people.

### Payment ledger
Set of [[Payment]]s on one [[Expense]]. Invariant: `sum(payment.amount_paid) = expense.amount`. Records *who actually fronted cash*.

### Payment
A single trip person's contribution toward an Expense. Has trip person, non-negative amount paid, and mode (`equal` or `exact` in the V1 UI).

### Payer
A trip person represented in the Payment ledger for a given Expense. An Expense always has at least one Payer. Multi-payer is V1 behavior, not future scope.

### Split ledger
Set of [[Split]]s on one [[Expense]]. Invariant: `sum(split.amount_owed) = expense.amount`. Records *who is on the hook for the cost*.

### Split
A single trip person's owed share of an Expense. Has trip person, non-negative amount owed, and mode (`equal` or `exact` in the V1 UI).

### Participant
A trip person with ≥ 1 Split on a given Expense. May or may not also be a Payer.

### Payment mode / Split mode
- `equal` — total auto-divided across selected users. 1-cent remainders are distributed to lex-lowest UUIDs (deterministic, see `SplitCalculator` / `PaymentCalculator`).
- `exact` — user enters per-user amount directly. Sum must equal total.
- Future enum values (`percentage`, `shares`, `adjustment`) exist in the schema but are not supported by the V1 UI or TabCore calculators.

### Net per trip person per expense
`net = sum(payments by trip person) - sum(splits owed by trip person)`.
Drives [[Pair balance]] aggregation. Sums to zero across all trip people on a single expense (because both ledgers sum to `expense.amount`).

### Pair balance
Per `(trip_person_pair, currency)` balance derived from all expense nets plus settlements within a trip. Always pairwise — **never simplified across the group** in V1. Computed by `BalanceEngine`.

The canonical pair key sorts the two trip-person UUIDs `(lo, hi)`. Positive canonical amount means `hi` owes `lo`. External presentation uses mirrored [[User balance]] rows.

For a multi-payer expense, each debtor's shortfall is allocated across creditors in proportion to each creditor's surplus. Settlements then subtract from the relevant pair/currency balance.

### User balance
The user-facing mirror of a [[Pair balance]]: `forUser`, `withUser`, `currency`, `amount`. Positive amount means `withUser` owes `forUser`; negative amount means `forUser` owes `withUser`.

### Settlement
A recorded payment of money from one trip person to another outside the app. Has from-person, to-person, positive amount, currency, optional note, and settled-at date. Any trip member can record a settlement between any two trip people in that trip.

Settlements are independent of [[Expense]]s: they do not mutate expenses or ledgers. They only contribute to balance aggregation. A settlement can partially reduce a debt, clear it, overpay it, or move the pair balance in the opposite direction.

### Settle up
The user workflow for creating or editing a Settlement. When suggesting defaults, the app first prefers a debt the current person owes, then a debt another person owes the current person.

### Active / Completed trip state
A trip is **Completed** when all pair balances across all currencies are zero and `lastActivityAt` is at least 30 days old. Otherwise it is **Active**.

The activity clock starts at trip creation and is bumped by expense or settlement writes, including edits/deletes. A new expense or settlement on a Completed trip reactivates it. State is derived from data; never stored.

### Currency
A trip-level concept only in the sense that each expense and settlement carries its own ISO currency code. **No FX conversion in V1**. Totals, balances, and exports are computed and displayed strictly per currency.

### Timeline
The visible trip activity stream, grouped by date, containing active expenses and active settlements in reverse chronological order.

### Activity log
An append-only table for trip actions such as expense changes, settlement changes, membership events, and trip changes. This is separate from the visible Timeline.

### Soft delete
Mutable user-visible records are deleted by setting `deleted_at`, not by immediate hard delete. Active domain calculations ignore soft-deleted expenses and settlements. The server-side purge window is 30 days.

### Trip mute preference
A per-user, per-trip notification preference. Row presence means the trip is muted for that user; absence means unmuted.

### Push device
A user's registered APNs device token. Push devices are account-scoped, not trip-scoped; trip notification behavior is controlled by [[Trip mute preference]].

### Trip export
A spreadsheet-style export for a trip. It includes active expenses, payment rows, split rows, settlements, totals by currency, per-person paid/owed summaries, and pair balances.

## Adopted decisions

Significant decisions live as ADRs under `docs/adr/`. Current set:

- `0001-multi-payer-in-v1.md` — multi-payer expenses promoted to V1 from V2.
