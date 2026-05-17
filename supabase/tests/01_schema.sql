-- 01_schema.sql — table / column / PK / FK / RLS structural checks.
-- Run via mcp__supabase__execute_sql. Returns one row per assertion.

begin;
set local search_path = extensions, public, pg_temp;

select plan(51);

create temp table _r (line text);

-- ===== 10 public tables exist =====
insert into _r select has_table('public', 'profiles',        'profiles exists');
insert into _r select has_table('public', 'trips',           'trips exists');
insert into _r select has_table('public', 'trip_members',    'trip_members exists');
insert into _r select has_table('public', 'categories',      'categories exists');
insert into _r select has_table('public', 'expenses',        'expenses exists');
insert into _r select has_table('public', 'expense_splits',  'expense_splits exists');
insert into _r select has_table('public', 'settlements',     'settlements exists');
insert into _r select has_table('public', 'activity_log',    'activity_log exists');
insert into _r select has_table('public', 'push_devices',    'push_devices exists');
insert into _r select has_table('public', 'trip_mute_prefs', 'trip_mute_prefs exists');

-- ===== private schema + helper function =====
insert into _r select has_schema('private', 'private schema exists');
insert into _r select has_function('private', 'is_trip_member', array['uuid'], 'private.is_trip_member(uuid) exists');
insert into _r select has_function('private', 'is_profile_trip_member', array['uuid', 'uuid'], 'private.is_profile_trip_member(uuid, uuid) exists');
insert into _r select has_function('private', 'receipt_object_trip_id', array['text'], 'private.receipt_object_trip_id(text) exists');
insert into _r select has_table('private', 'trip_invites', 'private.trip_invites exists');
insert into _r select has_function('public', 'create_trip_invite', array['uuid', 'timestamp with time zone'], 'public.create_trip_invite(uuid, timestamptz) exists');
insert into _r select has_function('public', 'join_trip_with_invite', array['uuid', 'uuid', 'text'], 'public.join_trip_with_invite(uuid, uuid, text) exists');
insert into _r select has_function('public', 'purge_soft_deleted_records', array['timestamp with time zone'], 'public.purge_soft_deleted_records(timestamptz) exists');
insert into _r select ok((select relrowsecurity from pg_class where oid='private.trip_invites'::regclass), 'RLS enabled: private.trip_invites');

-- ===== RLS enabled on every public table =====
insert into _r select ok((select relrowsecurity from pg_class where oid='public.profiles'::regclass),        'RLS enabled: profiles');
insert into _r select ok((select relrowsecurity from pg_class where oid='public.trips'::regclass),           'RLS enabled: trips');
insert into _r select ok((select relrowsecurity from pg_class where oid='public.trip_members'::regclass),    'RLS enabled: trip_members');
insert into _r select ok((select relrowsecurity from pg_class where oid='public.categories'::regclass),      'RLS enabled: categories');
insert into _r select ok((select relrowsecurity from pg_class where oid='public.expenses'::regclass),        'RLS enabled: expenses');
insert into _r select ok((select relrowsecurity from pg_class where oid='public.expense_splits'::regclass),  'RLS enabled: expense_splits');
insert into _r select ok((select relrowsecurity from pg_class where oid='public.settlements'::regclass),     'RLS enabled: settlements');
insert into _r select ok((select relrowsecurity from pg_class where oid='public.activity_log'::regclass),    'RLS enabled: activity_log');
insert into _r select ok((select relrowsecurity from pg_class where oid='public.push_devices'::regclass),    'RLS enabled: push_devices');
insert into _r select ok((select relrowsecurity from pg_class where oid='public.trip_mute_prefs'::regclass), 'RLS enabled: trip_mute_prefs');

-- ===== Primary keys =====
insert into _r select col_is_pk('public', 'profiles',        'id',                  'profiles.id is PK');
insert into _r select col_is_pk('public', 'trips',           'id',                  'trips.id is PK');
insert into _r select col_is_pk('public', 'trip_members',    array['trip_id', 'user_id'], 'trip_members composite PK');
insert into _r select col_is_pk('public', 'expense_splits',  array['expense_id', 'user_id'], 'expense_splits composite PK');
insert into _r select col_is_pk('public', 'trip_mute_prefs', array['trip_id', 'user_id'], 'trip_mute_prefs composite PK');

-- ===== Foreign keys =====
insert into _r select col_is_fk('public', 'profiles',       'id',          'profiles.id is FK -> auth.users');
insert into _r select col_is_fk('public', 'trips',          'created_by',  'trips.created_by is FK');
insert into _r select col_is_fk('public', 'trip_members',   'trip_id',     'trip_members.trip_id is FK');
insert into _r select col_is_fk('public', 'trip_members',   'user_id',     'trip_members.user_id is FK');
insert into _r select col_is_fk('public', 'expenses',       'trip_id',     'expenses.trip_id is FK');
insert into _r select col_is_fk('public', 'expenses',       'payer_id',    'expenses.payer_id is FK');
insert into _r select col_is_fk('public', 'expenses',       'created_by',  'expenses.created_by is FK');
insert into _r select col_is_fk('public', 'expense_splits', 'expense_id',  'expense_splits.expense_id is FK');
insert into _r select col_is_fk('public', 'settlements',    'from_user',   'settlements.from_user is FK');
insert into _r select col_is_fk('public', 'settlements',    'to_user',     'settlements.to_user is FK');

-- ===== Key column types =====
insert into _r select col_type_is('public', 'expenses',    'amount',   'numeric(14,2)',  'expenses.amount is numeric(14,2)');
insert into _r select col_type_is('public', 'settlements', 'amount',   'numeric(14,2)',  'settlements.amount is numeric(14,2)');
insert into _r select col_type_is('public', 'expenses',    'currency', 'text',           'expenses.currency is text');
insert into _r select col_type_is('public', 'trips',       'id',       'uuid',           'trips.id is uuid');
insert into _r select col_type_is('public', 'expenses',    'write_id', 'uuid',           'expenses.write_id is uuid');

-- ===== Categories seeded =====
insert into _r select is(
  (select count(*)::int from public.categories where is_default),
  6,
  'six built-in categories seeded'
);

insert into _r select ok(
  exists (select 1 from storage.buckets where id = 'receipts' and public = false),
  'private receipts storage bucket exists'
);

insert into _r select * from finish();
select line from _r;
rollback;
