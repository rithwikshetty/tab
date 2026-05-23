# CONTEXT.md audit

## 2026-05-23 20:21:37 BST

Goal: audit `CONTEXT.md` against the current repository and update it where the domain glossary or adopted decisions are stale, incomplete, or inaccurate.

## 2026-05-23 20:23:18 BST

Audited `TabCore` models/calculators, SwiftData entities/presenters, Supabase SQL source, database test README, ADR-0001, and the settle-up working log. The existing glossary is directionally correct for trips, trip people, expenses, payments, splits, balances, settlements, currency, and email pre-add, but it is incomplete. Missing domain terms now present in the repo include profiles, categories, payment method, receipt photo/storage path, activity/timeline, trip mute preferences, push devices, trip export, and the transactional expense write path. The trip completion wording also needs to line up with `last_activity_at`: it starts at trip creation and is bumped by expense/settlement writes.

## 2026-05-23 20:25:17 BST

Updated `CONTEXT.md` to reflect the current domain model. Added missing glossary entries for account profiles, trip members, categories, receipt photos, payment method, user balances, settle-up behavior, visible timeline, activity log, soft delete, notification-related server concepts, and trip export. Tightened existing wording around expense atomicity, multi-payer as V1 behavior, unsupported future split/payment modes, pair-balance sign conventions, proportional multi-payer balance allocation, settlement overpayment/opposite-direction behavior, and active/completed trip derivation from `lastActivityAt`.
