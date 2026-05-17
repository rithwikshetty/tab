-- 02_constraints.sql — CHECK / UNIQUE / FK constraints (positive + negative).
-- Bypasses RLS by inserting as the postgres owner; we're testing constraint
-- enforcement, not access control.

begin;
set local search_path = extensions, public, pg_temp;

select plan(34);
create temp table _r (line text);

-- Fixture: minimal auth user + auto-created profile via handle_new_user trigger.
insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values (
  '00000000-0000-0000-0000-000000000001'::uuid,
  'alice@test.roam',
  '00000000-0000-0000-0000-000000000000'::uuid,
  'authenticated', 'authenticated',
  '{"display_name":"Alice"}'::jsonb
);
insert into public.trips (id, name, created_by)
values ('11111111-1111-1111-1111-111111111111'::uuid, 'Lisbon', '00000000-0000-0000-0000-000000000001'::uuid);

-- ===== expenses.amount > 0 =====
insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 0, 'EUR', 'zero', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'expense amount = 0 rejected');

insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', -1, 'EUR', 'neg', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'expense amount = -1 rejected');

insert into _r select lives_ok(
  $$insert into public.expenses (id, trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 0.01, 'EUR', 'one cent', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  'expense amount = 0.01 accepted (positive boundary)');

-- ===== currency: length 3, uppercase =====
insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 10, 'EU', 'short', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'currency length 2 rejected');

insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 10, 'EURO', 'long', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'currency length 4 rejected');

insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 10, 'eur', 'lower', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'currency lowercase rejected');

insert into _r select lives_ok(
  $$insert into public.expenses (id, trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 10, 'EUR', 'valid', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  'currency EUR accepted');

-- ===== description trimmed-length > 0 =====
insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 10, 'EUR', '', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'empty description rejected');

insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 10, 'EUR', '   ', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'whitespace-only description rejected');

-- ===== trips.name trimmed-length > 0 =====
insert into _r select throws_ok(
  $$insert into public.trips (name, created_by) values ('', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'empty trip name rejected');

-- ===== expense_splits.amount_owed >= 0 =====
insert into _r select lives_ok(
  $$insert into public.expense_splits (expense_id, user_id, amount_owed, split_type)
    values ('aaaaaaaa-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 0, 'equal')$$,
  'expense_split amount_owed = 0 accepted');

insert into _r select throws_ok(
  $$insert into public.expense_splits (expense_id, user_id, amount_owed, split_type)
    values ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', -1, 'equal')$$,
  '23514', null, 'expense_split amount_owed = -1 rejected');

-- ===== expense_splits.split_type enum =====
insert into _r select throws_ok(
  $$insert into public.expense_splits (expense_id, user_id, amount_owed, split_type)
    values ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 5, 'lol')$$,
  '23514', null, 'invalid split_type rejected');

insert into _r select lives_ok(
  $$insert into public.expense_splits (expense_id, user_id, amount_owed, split_type)
    values ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 5, 'percentage')$$,
  'split_type percentage accepted (V2 reserved)');

-- ===== settlements: from_user != to_user =====
insert into _r select throws_ok(
  $$insert into public.settlements (trip_id, from_user, to_user, amount, currency, created_by)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 10, 'EUR', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'settlement from_user = to_user rejected');

-- ===== settlements.amount > 0 (CHECK constraint) =====
-- Need Bob to exist first so we don't trip the FK before reaching the CHECK.
insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values ('00000000-0000-0000-0000-000000000002'::uuid, 'bob@test.roam', '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', '{"display_name":"Bob"}'::jsonb);

insert into _r select throws_ok(
  $$insert into public.settlements (trip_id, from_user, to_user, amount, currency, created_by)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 0, 'EUR', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'settlement amount 0 rejected (CHECK)');

-- ===== categories: default_xor_trip constraint =====
insert into _r select throws_ok(
  $$insert into public.categories (trip_id, name, icon, is_default)
    values ('11111111-1111-1111-1111-111111111111', 'bad-default', '?', true)$$,
  '23514', null, 'built-in category with trip_id rejected');

insert into _r select throws_ok(
  $$insert into public.categories (trip_id, name, icon, is_default)
    values (null, 'bad-custom', '?', false)$$,
  '23514', null, 'custom category with null trip_id rejected');

insert into _r select lives_ok(
  $$insert into public.categories (trip_id, name, icon, is_default)
    values ('11111111-1111-1111-1111-111111111111', 'BBQ', '🍖', false)$$,
  'custom category with trip_id accepted');

-- ===== categories: case-insensitive unique within a trip =====
insert into _r select throws_ok(
  $$insert into public.categories (trip_id, name, icon, is_default)
    values ('11111111-1111-1111-1111-111111111111', 'bbq', '🍖', false)$$,
  '23505', null, 'case-insensitive duplicate category name in same trip rejected');

-- ===== categories: built-in name unique globally =====
insert into _r select throws_ok(
  $$insert into public.categories (trip_id, name, icon, is_default)
    values (null, 'Food & Drink', '?', true)$$,
  '23505', null, 'duplicate built-in category name rejected');

-- ===== activity_log: action + entity_type enums =====
insert into _r select throws_ok(
  $$insert into public.activity_log (trip_id, actor_id, action, entity_type, entity_id)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 'made_up_action', 'expense', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'invalid activity action rejected');

insert into _r select throws_ok(
  $$insert into public.activity_log (trip_id, actor_id, action, entity_type, entity_id)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 'expense_created', 'made_up_entity', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'invalid activity entity_type rejected');

-- ===== FK enforcement =====
insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('99999999-9999-9999-9999-999999999999', '00000000-0000-0000-0000-000000000001', 10, 'EUR', 'no trip', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  '23503', null, 'expense with nonexistent trip_id rejected (FK)');

insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('11111111-1111-1111-1111-111111111111', '99999999-9999-9999-9999-999999999999', 10, 'EUR', 'no payer', '2026-05-01', '00000000-0000-0000-0000-000000000001')$$,
  '23503', null, 'expense with nonexistent payer_id rejected (FK)');

-- ===== profiles.display_name boundaries =====
insert into _r select throws_ok(
  $$update public.profiles set display_name = '' where id = '00000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'empty display_name rejected on update');

insert into _r select throws_ok(
  $$update public.profiles set display_name = repeat('x', 61) where id = '00000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'display_name length > 60 rejected');

insert into _r select lives_ok(
  $$update public.profiles set display_name = repeat('x', 60) where id = '00000000-0000-0000-0000-000000000001'$$,
  'display_name length = 60 accepted (boundary)');

-- ===== push_devices: unique (user_id, apns_token) =====
insert into _r select lives_ok(
  $$insert into public.push_devices (user_id, apns_token) values ('00000000-0000-0000-0000-000000000001', 'token-A')$$,
  'first push token accepted');

insert into _r select throws_ok(
  $$insert into public.push_devices (user_id, apns_token) values ('00000000-0000-0000-0000-000000000001', 'token-A')$$,
  '23505', null, 'duplicate push token for same user rejected');

insert into _r select lives_ok(
  $$insert into public.push_devices (user_id, apns_token) values ('00000000-0000-0000-0000-000000000002', 'token-A')$$,
  'same push token for different user accepted');

-- ===== push_devices: empty apns_token rejected =====
insert into _r select throws_ok(
  $$insert into public.push_devices (user_id, apns_token) values ('00000000-0000-0000-0000-000000000001', '')$$,
  '23514', null, 'empty apns_token rejected');

-- ===== trip_members: composite uniqueness =====
insert into _r select throws_ok(
  $$insert into public.trip_members (trip_id, user_id)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001')$$,
  '23505', null, 'duplicate trip_members row (same trip+user) rejected (creator already added)');

-- ===== profiles.avatar_url length boundary =====
insert into _r select throws_ok(
  $$update public.profiles set avatar_url = repeat('x', 2049) where id = '00000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'avatar_url length > 2048 rejected');

insert into _r select * from finish();
select line from _r;
rollback;
