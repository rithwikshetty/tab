## Goal

Seed the Supabase database with broad dummy data for `rithwikshetty96@gmail.com` so the iOS app has rich trips, people, expenses, settlements, notifications, and edge cases to inspect manually.

## 2026-06-08 22:19 BST

Started by reading the local Supabase schema and RPC definitions. Key constraints: app visibility is driven by joined `trip_people.user_id`; pending email rows can be claimed on sign-in; expense payments and splits have deferred totals that must exactly match the parent expense amount.

## 2026-06-08 22:21 BST

Checked the remote Supabase project `gaseuxsieddlksxtdliq`. The target auth user already exists for `rithwikshetty96@gmail.com` with id `654067a4-75cc-4c76-953f-7059cb91fc91`, so the seed can attach joined trip membership directly to the real user.

## 2026-06-08 22:28 BST

Applied a repeatable seed transaction through `npx supabase db query --linked`. The seed creates rich data attached to the target user: visible group trips, hidden non-group containers, custom categories, pending ledger people, multi-currency expenses, multi-payer expenses, zero-share participants, penny remainders, settlements, a muted trip, a soft-deleted expense, and manual activity rows. A payment/split verification query completed successfully: 16 seeded expenses, all 16 balanced, 1 soft-deleted.

## 2026-06-08 22:30 BST

Parallel verification queries caused Supabase CLI temporary connection throttling (`ECIRCUITBREAKER`). Stopped running remote checks in parallel and switched back to serial verification only.

## 2026-06-08 22:38 BST

User reauthenticated the Supabase MCP connection. Verified the seed through MCP: 16 seeded expenses, 16 balanced payment/split totals, 1 soft-deleted expense, 5 settlements, 3 custom categories, 9 manual activity rows, and 1 mute preference. Seeded active group trips are `Portugal Surf Week`, `Japan Ski Cabin`, `Flatmates - June`, and `Edge Case Lab`; also seeded two hidden non-group containers and one soft-deleted demo trip.
