# tab — PRD (v1)

> Status: greenfield project, no issue tracker set up yet. This PRD lives in-repo until project tooling exists.

## Problem Statement

Our friend group uses Splitwise to track shared expenses on trips. Over time, Splitwise has become increasingly ad-supported, capped behind a pro tier, and pushy about upgrades. We don't want ads, we don't want monetization pressure, and we don't want a third party rate-limiting how many expenses we log on a vacation. We just want a clean, fast, mobile-only way to track who paid for what during a trip and who owes whom at the end.

## Solution

**tab** is an iOS-first, offline-first group expense tracker built for trips. Each Trip is a container for members and expenses. Anyone in the trip can log an expense (with payer, participants, amount, currency, category, optional receipt photo). The app computes per-currency pairwise balances and lets members record settlements when they pay each other back. Designed for a small private friend group: invite-only via deep link, distributed via TestFlight, free forever for us.

V1 is intentionally minimal: trip + expenses + splits + settlement. Future versions will add itinerary, analytics, simplified debts, and richer split types — but the data model is shaped to absorb those without rewrite.

## User Stories

### Onboarding & identity
1. As a new user, I want to sign in with my Apple ID, so that I can start using the app without creating yet another password.
2. As a new user, I want to fall back to email magic link, so that I can still access tab if I don't want to use Apple Sign-In.
3. As a user, I want to set my display name and optional avatar, so that other trip members recognize me.
4. As a user, I want to sign out of the app, so that I can switch accounts or hand off the device.

### Trip creation & membership
5. As a trip organizer, I want to create a new trip with just a name, so that I can start logging expenses immediately without filling out a form.
6. As a trip organizer, I want to generate a shareable invite link, so that I can send it to friends via iMessage / WhatsApp / AirDrop.
7. As an invited user, I want to tap an invite link, so that I'm taken into the app and joined to the trip in one step.
8. As a user, I want to see all my trips on the home screen separated into Active and Completed sections, so that I can find what I need.
9. As a user, I want to see who's in a trip, so that I know who I can split expenses with.
10. As a user, I want to leave a trip (with confirmation), so that I can exit a trip I'm no longer part of.

### Expense entry
11. As a user, I want to add an expense with amount, currency, description, category, payer, participants, and date, so that I can record what happened on the trip.
12. As a user, I want the expense date to default to today, so that I don't have to set it for every entry.
13. As a user, I want to pick the currency from a searchable list, so that I can quickly find the one I used.
14. As a user, I want to pick the payer (myself or another trip member), so that the right person gets credit.
15. As a user, I want to pick which trip members participated in this expense, so that absent members aren't charged for things they didn't do.
16. As a user, I want to choose Equal or Exact split type per expense, so that I can split bills accurately.
17. As a user adding an Exact split, I want to enter per-participant amounts and have them validate against the total, so that I don't accidentally over- or under-charge.
18. As a user, I want to attach a receipt photo from camera or library, so that I can refer back to it later.
19. As a user, I want to select a category from a fixed default set (Food & Drink, Transport, Lodging, Activities, Shopping, Other), so that expenses are consistently categorized.
20. As a user, I want to create a custom category scoped to a trip, so that I can categorize unusual expenses without polluting other trips.
21. As a user, I want my expense to save immediately offline, so that I'm not blocked by lack of signal in a restaurant or on a mountain.

### Expense viewing & editing
22. As a user, I want to see all expenses for a trip in reverse-chronological order, so that I can scan recent activity at a glance.
23. As a user, I want each expense row to show who paid and how much I owe (or am owed), so that I don't have to compute it mentally.
24. As a user, I want to tap an expense to see full details (all participants, individual shares, receipt, history), so that I can understand it fully.
25. As a user, I want to edit any expense in the trip (not just mine), so that typos can be fixed by whoever is available.
26. As a user, I want to soft-delete any expense in the trip, so that mistakes can be removed.
27. As a user, I want a deleted expense to be recoverable for 30 days, so that accidental deletes don't lose data permanently.
28. As a user, I want to see when and by whom an expense was last edited, so that I have context for any changes.

### Balances & settlement
29. As a user, I want to see my balance with each other trip member per-currency, so that I know who owes whom and in what currency.
30. As a user, I want to see a trip-wide summary showing all pairwise balances, so that I can understand the full picture before settling up.
31. As a user, I want to record a settlement payment (from-user, to-user, amount, currency, optional note, date), so that balances zero out after I send money outside the app.
32. As a user, I want settlements to persist forever and remain visible in trip history, so that I can audit who paid whom and when.

### Trip lifecycle
33. As a user, I want a trip to auto-move to "Completed" once all balances are zero AND no activity has occurred for 30 days, so that I don't have to remember to archive.
34. As a user, I want a Completed trip to automatically reactivate if someone adds a new expense, so that nothing falls through the cracks.
35. As a user, I want Completed trips in a separate section on the home screen, so that they don't clutter the active list.

### Notifications
36. As a user, I want to receive a push notification when someone adds, edits, or deletes an expense in a trip I'm in, so that I'm aware of changes.
37. As a user, I want to receive a push when someone records a settlement involving me, so that I know my balance changed.
38. As a user, I want notifications to deep-link into the relevant expense or trip, so that I can act on them in one tap.
39. As a user, I want to mute notifications per-trip, so that a noisy trip doesn't spam me.
40. As a user, I want notifications to be batched on the server side during high-activity periods, so that I get one digest instead of ten buzzes during a dinner.

### Real-time & offline
41. As a user viewing a trip detail screen, I want new expenses by others to appear in real-time without pulling to refresh, so that the app feels live and social.
42. As a user offline, I want to add, edit, delete expenses and record settlements as if I were online, so that bad signal never blocks the app.
43. As a user reconnecting after being offline, I want my pending changes to sync automatically, so that I don't have to manually trigger anything.
44. As a user, I want sync conflicts to resolve via last-write-wins (with deletes taking precedence), so that the app reaches a sensible state without prompting me to choose.

### Receipts
45. As a user, I want to attach a receipt photo when entering an expense, so that I can review it later.
46. As a user, I want to view a receipt photo full-screen, so that I can read the details.
47. As a user, I want receipt images prepared client-side and downscaled only when needed before upload, so that large phone photos fit the storage limit without unnecessary quality loss.

### Settings & utility
48. As a user, I want to update my display name and avatar from settings, so that my identity stays current across trips.
49. As a user, I want to see app version and basic credits, so that I can report bugs accurately.

## Implementation Decisions

### Platform & stack
- **Target:** iOS 18+ native, SwiftUI, SwiftData (local persistence), Observation framework. No backward-compat to older iOS.
- **Backend:** Supabase (Postgres + Auth + Realtime + Storage + Edge Functions). Free tier covers the friend-group scale.
- **Distribution:** TestFlight only for v1. No App Store submission. Apple Developer account required ($99/yr) for TestFlight and APNs.
- **Android:** explicitly out of scope; acceptable that a future port would require backend work to remain Supabase-compatible.

### Module structure

**Core logic (pure, no I/O, testable in isolation)**
- **SplitCalculator** — input: expense amount + split type + participants; output: per-participant amounts owed. Pure function. Encapsulates Equal and Exact rules; interface designed to absorb Percentage / Shares / Adjustment later.
- **BalanceEngine** — input: a trip's expenses + settlements; output: pairwise per-currency balances. Pure function.
- **TripStateDeriver** — input: trip's last activity timestamp + all balances; output: `.active` or `.completed`. Encapsulates the "settled + 30 days inactive" rule.
- **ConflictResolver** — input: two record versions + timestamps + tombstones; output: winning version. Policy: last-write-wins by `updated_at`; deletes (non-null `deleted_at`) always win over edits.

**Service modules (I/O, deep, mockable interfaces)**
- **SyncEngine** — orchestrates offline-first sync. Interface: `enqueue(change)`, `sync()`, `subscribe(tripId)`. Internals: pending-changes queue, push-then-pull, conflict resolution, Realtime subscription lifecycle.
- **AuthService** — wraps Supabase Auth + Apple Sign-In + email magic link. Interface: `signIn()`, `signOut()`, `currentUser`.
- **MediaStore** — receipt photo lifecycle. Client-side JPEG preparation, downsize only when needed to stay under the 10 MiB Supabase Storage limit, lazy download, local cache.
- **PushNotificationService** — APNs registration, device-token sync with Supabase, payload parsing, deep-link routing.
- **InviteLinkService** — call invite RPCs, generate deep links with trip/invite/token values, parse incoming links, validate, perform idempotent join.
- **ActivityLogger** — append-only event recording (actor, action, entity, timestamp, optional snapshot). Stored, not surfaced in UI for v1.

**Data layer**
- **LocalStore** — thin SwiftData wrapper.
- **RemoteStore** — thin Supabase REST + Realtime wrapper.
- **Repositories** (Trip, Expense, Settlement, Member, Category) — CRUD over LocalStore, route mutations through SyncEngine.

**UI layer (SwiftUI)**
- Screens: SignIn, TripList, TripDetail, ExpenseEntry, ExpenseDetail, SettleUp, MemberList, Settings.
- Reusable components: CurrencyField, MemberPicker, SplitEditor, CategoryPicker, ReceiptThumbnail.

### Schema (conceptual — exact column names refined during implementation)

```
users             (id, apple_user_id?, email?, display_name, avatar_url?)
trips             (id, name, created_by, created_at, last_activity_at)
trip_members      (trip_id, user_id, joined_at)
private.trip_invites (id, trip_id, token_hash, created_by, expires_at,
                   revoked_at?, used_at?, created_at, updated_at, deleted_at?)
categories        (id, trip_id?, name, icon, is_default)
expenses          (id, trip_id, payer_id, amount, currency, category_id,
                   description, expense_date, receipt_storage_path?,
                   created_by, created_at, updated_at, deleted_at?)
expense_splits    (expense_id, user_id, amount_owed, split_type)
settlements       (id, trip_id, from_user, to_user, amount, currency,
                   note?, settled_at, created_by, created_at, deleted_at?)
activity_log      (id, trip_id, actor_id, action, entity_type, entity_id,
                   timestamp, snapshot_json?)
push_devices      (user_id, apns_token, last_seen_at)
trip_mute_prefs   (trip_id, user_id, muted_at)
```

Notes:
- `categories.trip_id` is nullable to support the global default set (Food & Drink, Transport, Lodging, Activities, Shopping, Other).
- `expense_splits.split_type` is an enum supporting `equal | exact | percentage | shares | adjustment`. V1 writes only `equal` and `exact`; the others remain available for v2.
- Expense writes are transactional: an expense and all `expense_splits` must be written together, and the DB enforces `sum(expense_splits.amount_owed) = expenses.amount` for active expenses.
- Payers, split participants, settlement parties, creators, custom categories, and mute prefs must belong to the target trip at the DB boundary, not just in the app.
- Soft-delete on user-visible mutable records (`trips`, `categories`, `expenses`, `settlements`, and invite records) via nullable `deleted_at`. Membership/mute/device rows use row presence because they are preference or join rows; `activity_log` is append-only.
- `trips.last_activity_at` is updated by Postgres triggers on expense/settlement writes (used by TripStateDeriver).
- Receipt photos live in the private Supabase Storage bucket `receipts`; object paths are `<trip_id>/<expense_id>.jpg` and storage RLS derives access from trip membership.

### Sync architecture
- SwiftData is the source of truth on-device. All reads come from local; all writes go local first, then enqueue to SyncEngine.
- SyncEngine pushes pending changes to Supabase when online, then pulls remote deltas since `last_synced_at` per table.
- Multi-row mutations that must be atomic, especially expense + splits and invite joins, go through Supabase RPCs or another transactional server path. The app should not issue independent REST writes that can leave partial split state.
- Realtime subscription opens only on the currently-viewed trip detail screen; unsubscribes on navigation away.
- Conflict resolution is delegated to ConflictResolver. Policy: deletes win; otherwise highest `updated_at` wins.

### Auth & joining
- Apple Sign-In is the primary path. Email magic link is the fallback.
- A new user becomes a `users` row on first sign-in; identity is keyed by Apple user ID (preferred) or email.
- Invite links are deep links: `tab://join/<trip_id>?invite=<invite_id>&token=<secret>`. Raw invite tokens are returned once by `create_trip_invite`, stored only as SHA-256 hashes in the private schema, expire after ~7 days by default, and are validated by `join_trip_with_invite`.
- Joining a trip is idempotent (re-tapping the link does not duplicate membership).

### Currency model
- No automatic conversion. Each expense stores its own amount + currency.
- Balances computed per-(member pair × currency). Display: "Bob owes you EUR 30 and USD 15."
- No FX rate fetching, no rate caching, no conversion math. Simplifies offline behavior.

### Notifications
- APNs payloads dispatched by a Supabase Edge Function triggered by inserts on `expenses` and `settlements`, and by updates on `expenses` (with `deleted_at` set or otherwise).
- Server-side batching: if a user would receive > N notifications for the same trip within a short window, collapse into a single digest ("3 new expenses in Italy Trip"). Exact thresholds tuned post-launch.
- Deep links route to the specific expense detail or trip detail screen.

### Activity log
- Recorded on every mutation. Not surfaced in UI for v1 (no activity feed screen). Purely a data-integrity / audit / future-feature substrate.

## Testing Decisions

### What makes a good test here
- Test **external behavior**, not internal implementation. Given inputs → assert outputs / observable side effects.
- Pure-logic modules (SplitCalculator, BalanceEngine, TripStateDeriver, ConflictResolver) are the prime targets: they have rich behavior, simple interfaces, no I/O, and high correctness stakes (money math, sync correctness, lifecycle rules).
- Tests should read like specifications of the rule (e.g., "given two participants and a $30 expense split equally, each owes $15"). If a test starts mocking internals, the module is probably too shallow or being tested wrong.

### Modules with tests in v1
- **SplitCalculator** — exhaustive coverage of Equal and Exact split types: simple cases, rounding (e.g., $10 / 3 = 3.33 / 3.33 / 3.34), single participant, all-participants-excluded edge cases, zero-amount, large amounts.
- **BalanceEngine** — multi-expense, multi-currency, before/after settlements, member who only paid, member who only owed, settlements that overshoot, deleted expenses (must be excluded).
- **TripStateDeriver** — settled-and-stale → completed, settled-but-recent → active, unsettled-and-stale → active, completed → reactivates when a new expense lands.
- **ConflictResolver** — LWW for concurrent edits, delete-wins regardless of timestamps, identical timestamps tiebreaker, missing tombstone fields.

### Prior art
- None — this is a greenfield repo. The four modules above will set the testing pattern for the rest of the project. Subsequent modules (SyncEngine integration tests, InviteLinkService unit tests) will inherit the same "test external behavior" discipline.

## Out of Scope

Explicitly NOT in v1 (deferred to v2 or later):
- Itinerary feature (mentioned as a long-term goal — separate scope).
- Spending analytics / category breakdowns / per-trip dashboards.
- Simplified-debt computation (always-pairwise in v1).
- Multiple payers per expense.
- Percentage, shares, and adjustment split types (data model supports them; UI does not).
- Placeholder / ghost members (everyone in a trip must be a signed-in app user).
- Real payment integration or deep-links to Venmo / Apple Cash / etc.
- Activity log UI (data is captured, no screen for it).
- Currency conversion / FX rate fetching.
- Android port.
- Public App Store submission.
- Trip-level dates (start / end). Only expenses have dates.
- Roles / admin permissions (every member is equal in v1).
- Recurring expenses, budgets, reminders.
- Widgets, lock-screen, Shortcuts, Apple Watch.
- Exporting trip data (CSV, PDF).

## Further Notes

- **Reference, don't fork:** [Dime](https://github.com/rafsoh/dimeApp) is licensed GPL-3.0 and is a personal (single-user) finance tracker. Tab is a multi-user group expense splitter — the domain model is fundamentally different. Browse Dime locally for SwiftUI UI inspiration only; do not fork or copy code.
- **No issue tracker yet:** this PRD lives as `PRD.md` until project management tooling (GitHub Issues, Linear, etc.) is set up.
- **Apple Developer account is a hard dependency** for TestFlight distribution and APNs ($99/yr).
- **Auto-archive rule recap:** a trip is "Completed" when all pairwise balances across all currencies are zero AND no expense / settlement activity for 30 days. Any new expense or settlement reactivates it. State is derived, not stored.
- **Conflict resolution recap:** last-write-wins by `updated_at`; non-null `deleted_at` always wins over edits.
- **Receipts:** stored in the private Supabase Storage bucket `receipts` at `<trip_id>/<expense_id>.jpg`. Prepared as JPEG client-side and kept under the 10 MiB bucket limit. Lazy-downloaded on view; cached locally.
