# Working log — Notification system (Activity feed + APNs push)

Goal: Build the full notification system end-to-end per the design grill + ADR-0002.
One event stream (activity_log) → two channels: in-app global **Activity** tab + APNs push.
Server-side DB triggers write activity_log; Database Webhook/pg_net → edge function → direct APNs.
Per-user single `last_seen_at` cursor for unread. Mute = silence-not-hide. iOS 18 native, clean/scalable.

Hard constraint acknowledged: live APNs delivery (edge fn → Apple → device) cannot be verified in
Simulator or without the Apple Push .p8 key. Everything else is built + tested in the sim; push
*receipt/display/tap* tested via `xcrun simctl push`. Sender built to current APNs spec + documented.

Environment:
- Supabase REMOTE only (project gaseuxsieddlksxtdliq / tab-it, PG 17.6). DB work via Supabase MCP apply_migration.
- App: XcodeGen (project.yml) + supabase-swift 2.46, Swift 6 strict concurrency, iOS 18, mock auth via TAB_MOCK_AUTH=1.
- Branch: feat/notifications (off main).

## Plan (phases)
1. Research current native APIs (APNs-from-Deno, pg_net/webhooks, iOS18 push + TabView badge) — bg workflow.
2. DB: activity_log write_id + triggers + last_seen cursor + RLS + sync publication; rebuild baseline; pgTAP.
3. App models/sync: ActivityEntity + cursor + push_devices + mute; SyncService pull/push.
4. App push: entitlement, AppDelegate registration, UNUserNotificationCenterDelegate, token upsert, permission flow, deep-link.
5. App UI: RootView → 3 tabs (Trips · Activity · Settings) per-tab NavigationStacks; Activity screen; badge; mute toggle.
6. Edge function send-push (APNs JWT ES256) + webhook wiring.
7. Build + simulator verification (mock auth) + simctl push + swift tests + adversarial review.

## Entries

### 2026-06-06 — Codebase fully mapped, DB design locked
- Triggers model: `touch_trip_last_activity` (AFTER ins/upd/del, SECURITY DEFINER) is the template.
- `set_sync_fields` regenerates write_id on EVERY update → can't use write_id for idempotency.
  Instead: AFTER trigger compares user-visible columns OLD vs NEW (IS DISTINCT FROM) → no event on
  no-op re-syncs. Client `pushPending` is dirty-tracked (pushedWriteID != writeID) so unchanged rows
  are never re-pushed anyway; the column-comparison is belt-and-suspenders.
- Actor = auth.uid() (available even inside SECURITY DEFINER RPCs). Null actor (service role) → skip event.
- Expense writes go via create_expense_with_payments_and_splits (INSERT ... ON CONFLICT DO UPDATE):
  create=INSERT trigger, edit=UPDATE trigger, soft-delete=direct UPDATE of deleted_at. All classifiable.
- Membership: member_joined on trip_people INSERT only (skip self-add where invited_by = user_id);
  claim is an UPDATE → no new event (matches "one event at add-time"). member_left on DELETE.
- Cursor: `profiles.activity_last_seen_at` + RPC mark_activity_seen() (monotonic via greatest()).
- Push fan-out: pg_net (0.20) AFTER INSERT on activity_log -> edge fn; URL+secret in private.app_config
  (seeded out-of-band, never committed); function no-ops if unconfigured so in-app side works alone.
- unread_activity_count(user) SECURITY DEFINER for the edge fn to set aps.badge per recipient.

### Verification reality (documented honestly)
- mock auth => hasRealSession=false => sync no-ops. So the Activity FEED can't be driven by real sync
  under mock auth. Plan: (a) verify triggers/RLS/RPCs via SQL with JWT-claim simulation (real);
  (b) verify in-app feed/badge/grouping/deeplink/mute/TabView in sim under mock auth with a DEBUG-only
  ActivityEntity seed; (c) verify push receive/display/tap via `xcrun simctl push`; (d) edge->APNs send
  built to spec + deployed + documented, NOT live-verifiable (no .p8, no device).
- Native TabView (3 tabs) chosen over hand-rolled persistent bar. Cursor as profiles column.

### 2026-06-06 — DB layer DONE + verified
- Files: 02_profiles (cursor col + mark_activity_seen), 09_activity_log (4 trigger fns + triggers +
  snapshot helpers), 17_privileges (revokes/grant), 18_notifications_push (pg_net trigger, app_config,
  unread_activity_count). Baseline rebuilt; assembly contract holds.
- Applied to live remote via MCP apply_migration (additive, non-destructive). pg_net enabled.
- Direct verification on real "Thailand 2026" trip: expense create/update/delete, no-op edit skipped,
  member_joined/left, settlement_created — all correct snapshots; unread 6 (neha) / 0 (rithwik, actor).
  Test data fully cleaned up (activity_log back to 0 rows).
- pgTAP supabase/tests/08_activity_notifications.sql: 15/15 pass (run via MCP in rolled-back txn).
- Finding: trip_people referenced by ledgers are on-delete-restrict -> member_left only for ref-free people.
