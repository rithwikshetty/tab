# Context — tab

A multi-user, multi-currency, group expense tracker for trips. iOS-first, offline-first, private friend-group use (no monetisation).

This file is the project's domain glossary. Only terms meaningful to a domain expert (someone reasoning about expenses, balances, and trips) belong here — implementation specifics live in code.

## Glossary

### Trip
A container of members, expenses, and settlements. A user can belong to many trips. State (`active` vs `completed`) is **derived, not stored** — see `TripStateDeriver`.

### Trip member
A user who has joined a specific trip. Membership is set-membership only (no roles). Created at trip creation (for the creator) or via invite link.

### Expense
A single shared cost incurred on a trip. Has one currency, one amount, one description, one date, one category, optional receipt photo, and **two ledgers**: Payment ledger and Split ledger. Each ledger independently sums to `expense.amount`.

### Payment ledger
Set of [[Payment]]s on one [[Expense]]. Invariant: `sum(payment.amount_paid) = expense.amount`. Records *who actually fronted cash*.

### Payment
A single user's contribution toward an Expense. Has user, amount paid, and mode (Equal | Exact).

### Payer
A user with ≥ 1 Payment on a given Expense. An Expense always has ≥ 1 Payer.

### Split ledger
Set of [[Split]]s on one [[Expense]]. Invariant: `sum(split.amount_owed) = expense.amount`. Records *who is on the hook for the cost*.

### Split
A single user's owed share of an Expense. Has user, amount owed, and mode (Equal | Exact).

### Participant
A user with ≥ 1 Split on a given Expense. May or may not also be a Payer.

### Payment mode / Split mode
- `equal` — total auto-divided across selected users. 1-cent remainders distributed to lex-lowest UUIDs (deterministic, see `SplitCalculator`).
- `exact` — user enters per-user amount directly. Sum must equal total.
- Future modes (`percentage`, `shares`, `adjustment`) exist in the schema but are not surfaced in V1 UI.

### Net per user per expense
`net = sum(payments by user) - sum(splits owed by user)`.
Drives [[Pair balance]] aggregation. Sums to zero across all users on a single expense (because both ledgers sum to `expense.amount`).

### Pair balance
Per `(user_pair, currency)` balance derived from all expense nets + settlements within a trip. Always pairwise — **never simplified across the group** in V1. Computed by `BalanceEngine`.

### Settlement
A recorded payment of money from one user to another outside the app, zeroing some of a Pair balance. Has from-user, to-user, amount, currency, optional note, settled-at date. Independent of [[Expense]]s — does not mutate any Expense, only contributes to balance aggregation.

### Active / Completed trip state
A trip is **Completed** when all pair balances across all currencies are zero AND no expense or settlement activity has occurred for 30 days. Otherwise **Active**. A new expense or settlement on a Completed trip reactivates it. State is derived from data; never stored.

### Currency
A trip-level concept only in the sense that each expense carries its own ISO code. **No FX conversion in V1**. Balances are computed and displayed strictly per-currency.

### Trip invite
A one-shot deep-link token allowing a non-member to join a Trip. Tokens are hashed server-side, expire after ~7 days, and joins are idempotent.

## Adopted decisions

Significant decisions live as ADRs under `docs/adr/`. Current set:

- `0001-multi-payer-in-v1.md` — multi-payer expenses promoted to V1 from V2.
