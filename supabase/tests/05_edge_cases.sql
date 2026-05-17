-- 05_edge_cases.sql — Soft-delete behavior, cascade vs restrict, helper-fn
-- behavior, sync-field invariants.

begin;
set local search_path = extensions, public, pg_temp;

select plan(14);
create temp table _r (line text);

-- Fixture
insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000001'::uuid, 'alice@test.roam', '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', '{"display_name":"Alice"}'::jsonb),
  ('00000000-0000-0000-0000-000000000002'::uuid, 'bob@test.roam',   '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', '{"display_name":"Bob"}'::jsonb);

insert into public.trips (id, name, created_by)
values
  ('11111111-1111-1111-1111-111111111111'::uuid, 'Lisbon', '00000000-0000-0000-0000-000000000001'::uuid),
  ('33333333-3333-3333-3333-333333333333'::uuid, 'Empty',  '00000000-0000-0000-0000-000000000001'::uuid);

insert into public.trip_members (trip_id, user_id)
values ('11111111-1111-1111-1111-111111111111'::uuid, '00000000-0000-0000-0000-000000000002'::uuid);

insert into public.expenses (id, trip_id, payer_id, amount, currency, description, expense_date, created_by)
values ('aaaaaaaa-0000-0000-0000-000000000001'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        '00000000-0000-0000-0000-000000000001'::uuid,
        30, 'EUR', 'Dinner', '2026-05-14',
        '00000000-0000-0000-0000-000000000001'::uuid);

insert into public.expense_splits (expense_id, user_id, amount_owed, split_type) values
  ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, 15, 'equal'),
  ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, 15, 'equal');

insert into public.categories (id, trip_id, name, icon, is_default)
values ('cccccccc-0000-0000-0000-000000000001'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'Custom-Cat', '?', false);

-- ===== Soft-delete: setting deleted_at does NOT remove the row =====
update public.expenses set deleted_at = clock_timestamp()
where id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;

insert into _r select ok(
  exists (select 1 from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid),
  'Soft-delete: row still physically present after deleted_at set');

insert into _r select isnt(
  (select deleted_at from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid),
  null::timestamptz, 'Soft-delete: deleted_at populated');

-- Active-only partial index excludes soft-deleted rows.
insert into _r select ok(
  not exists (select 1 from public.expenses where trip_id = '11111111-1111-1111-1111-111111111111'::uuid and deleted_at is null),
  'Soft-delete: active-only query returns zero rows after deleted_at set');

-- Reset for cascade tests
update public.expenses set deleted_at = null where id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;

-- ===== expense_splits CASCADE-deletes when expense is hard-deleted =====
delete from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;

insert into _r select is(
  (select count(*)::int from public.expense_splits where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid),
  0, 'expense hard-delete CASCADEs to expense_splits');

-- ===== Trip hard-delete blocked by RESTRICT FKs from expenses =====
-- "Empty" trip has no expenses → can be hard-deleted.
insert into _r select lives_ok(
  $$delete from public.trips where id = '33333333-3333-3333-3333-333333333333'$$,
  'Empty trip hard-delete succeeds (no expense FKs blocking)');

-- Recreate Empty + add an expense → now hard-delete must RESTRICT
insert into public.trips (id, name, created_by) values ('33333333-3333-3333-3333-333333333333'::uuid, 'Empty', '00000000-0000-0000-0000-000000000001'::uuid);
insert into public.expenses (id, trip_id, payer_id, amount, currency, description, expense_date, created_by)
values ('bbbbbbbb-0000-0000-0000-000000000001'::uuid, '33333333-3333-3333-3333-333333333333'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, 5, 'EUR', 'blocker', '2026-05-01', '00000000-0000-0000-0000-000000000001'::uuid);

insert into _r select throws_ok(
  $$delete from public.trips where id = '33333333-3333-3333-3333-333333333333'$$,
  '23503', null, 'trip hard-delete RESTRICTed when expenses reference it');

-- Cleanup the expense so subsequent tests don't trip over it
delete from public.expenses where id = 'bbbbbbbb-0000-0000-0000-000000000001'::uuid;

-- ===== Profile hard-delete RESTRICTed by expense.payer_id and created_by =====
insert into public.expenses (id, trip_id, payer_id, amount, currency, description, expense_date, created_by)
values ('bbbbbbbb-0000-0000-0000-000000000002'::uuid, '33333333-3333-3333-3333-333333333333'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, 5, 'EUR', 'blocker2', '2026-05-01', '00000000-0000-0000-0000-000000000001'::uuid);

insert into _r select throws_ok(
  $$delete from public.profiles where id = '00000000-0000-0000-0000-000000000001'$$,
  '23503', null, 'profile hard-delete RESTRICTed when expenses reference it (payer_id/created_by)');

delete from public.expenses where id = 'bbbbbbbb-0000-0000-0000-000000000002'::uuid;
delete from public.trips where id = '33333333-3333-3333-3333-333333333333'::uuid;

-- ===== Trip cascade: deleting empty trip cascades trip_members, categories, activity_log =====
insert into public.trips (id, name, created_by) values ('44444444-4444-4444-4444-444444444444'::uuid, 'Cascade', '00000000-0000-0000-0000-000000000002'::uuid);
insert into public.categories (trip_id, name, icon, is_default) values ('44444444-4444-4444-4444-444444444444'::uuid, 'CTest', '?', false);
insert into public.activity_log (trip_id, actor_id, action, entity_type, entity_id)
values ('44444444-4444-4444-4444-444444444444'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, 'trip_created', 'trip', '44444444-4444-4444-4444-444444444444'::uuid);

-- Trip should have: 1 member (creator Bob, auto-added), 1 custom category, 1 activity row
delete from public.trips where id = '44444444-4444-4444-4444-444444444444'::uuid;

insert into _r select is((select count(*)::int from public.trip_members where trip_id = '44444444-4444-4444-4444-444444444444'::uuid), 0, 'trip delete CASCADEs to trip_members');
insert into _r select is((select count(*)::int from public.categories   where trip_id = '44444444-4444-4444-4444-444444444444'::uuid), 0, 'trip delete CASCADEs to categories');
insert into _r select is((select count(*)::int from public.activity_log where trip_id = '44444444-4444-4444-4444-444444444444'::uuid), 0, 'trip delete CASCADEs to activity_log');

-- ===== Helper function private.is_trip_member =====
-- Without auth.uid() (no JWT in this session): returns false.
insert into _r select ok(
  not private.is_trip_member('11111111-1111-1111-1111-111111111111'::uuid),
  'private.is_trip_member returns false when auth.uid() is null (no JWT)');

-- With auth.uid() set to Alice (a member of Lisbon): returns true.
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into _r select ok(
  private.is_trip_member('11111111-1111-1111-1111-111111111111'::uuid),
  'private.is_trip_member returns true for Alice on Lisbon');

-- With auth.uid() set to Alice but querying an unknown trip: returns false.
insert into _r select ok(
  not private.is_trip_member('99999999-9999-9999-9999-999999999999'::uuid),
  'private.is_trip_member returns false for unknown trip_id');

-- ===== Category soft-delete + re-create same name =====
-- Partial unique index has `where deleted_at is null`, so a soft-deleted name
-- frees up the slot.
update public.categories set deleted_at = clock_timestamp()
where id = 'cccccccc-0000-0000-0000-000000000001'::uuid;

reset role;  -- back to postgres for direct insert without RLS
insert into _r select lives_ok(
  $$insert into public.categories (trip_id, name, icon, is_default) values ('11111111-1111-1111-1111-111111111111', 'Custom-Cat', '?', false)$$,
  'After soft-delete, same category name can be re-created (partial unique index excludes deleted)');

insert into _r select * from finish();
select line from _r;
rollback;
