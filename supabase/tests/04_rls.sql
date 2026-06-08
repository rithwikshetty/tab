-- 04_rls.sql — RLS allow/deny paths for email-first trip people.

begin;
set search_path = extensions, public, pg_temp;

select plan(36);
create temp table _r (line text);
grant insert, select on _r to authenticated;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000001', 'alice@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Alice"}'),
  ('00000000-0000-0000-0000-000000000002', 'bob@test.tab',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Bob"}'),
  ('00000000-0000-0000-0000-000000000003', 'carol@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Carol"}'),
  ('00000000-0000-0000-0000-000000000005', 'dave@test.tab',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Dave"}');

insert into public.trips (id, name, created_by)
values
  ('11111111-1111-1111-1111-111111111111', 'Lisbon', '00000000-0000-0000-0000-000000000001'),
  ('22222222-2222-2222-2222-222222222222', 'Solo',   '00000000-0000-0000-0000-000000000003');

insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
values
  ('10000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 'alice@test.tab', 'Alice', '00000000-0000-0000-0000-000000000001', now()),
  ('10000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000002', 'bob@test.tab',   'Bob',   '00000000-0000-0000-0000-000000000001', now()),
  ('20000000-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000003', 'carol@test.tab', 'Carol', '00000000-0000-0000-0000-000000000003', now());

-- Alice is a Lisbon member.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

insert into _r select is((select count(*)::int from public.trips where id = '11111111-1111-1111-1111-111111111111'), 1, 'Alice sees Lisbon');
insert into _r select is((select count(*)::int from public.trips where id = '22222222-2222-2222-2222-222222222222'), 0, 'Alice cannot see Solo');
insert into _r select is((select count(*)::int from public.trip_people where trip_id = '11111111-1111-1111-1111-111111111111'), 2, 'Alice sees Lisbon people');
insert into _r select is((select count(*)::int from public.trip_people where trip_id = '22222222-2222-2222-2222-222222222222'), 0, 'Alice cannot see Solo people');
insert into _r select has_view('public', 'visible_profiles', 'visible_profiles view exists');
insert into _r select hasnt_column('public', 'visible_profiles', 'activity_last_seen_at', 'visible_profiles does not expose activity read cursors');
insert into _r select throws_ok(
  $$select activity_last_seen_at from public.profiles where id = '00000000-0000-0000-0000-000000000002'$$,
  '42501', null, 'Alice cannot read Bob profile Activity cursor from the raw profiles table');
insert into _r select is((select count(*)::int from public.visible_profiles where id = '00000000-0000-0000-0000-000000000002'), 1, 'Alice sees Bob profile display fields through visible_profiles');
insert into _r select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-000000000003'), 0, 'Alice cannot see Carol profile without a shared trip');

insert into _r select throws_ok(
  $$insert into public.trip_people (trip_id, email, display_name) values ('11111111-1111-1111-1111-111111111111', 'direct@test.tab', 'Direct')$$,
  '42501', null, 'direct trip_people insert denied');

insert into _r select lives_ok(
  $$select * from public.add_trip_person_by_email('11111111-1111-1111-1111-111111111111', 'newuser@test.tab', 'New User', '10000000-0000-0000-0000-000000000099')$$,
  'Alice adds pending person by email');

insert into _r select ok(
  (select user_id is null and joined_at is null from public.trip_people where email = 'newuser@test.tab'),
  'new email is pending');

insert into _r select lives_ok(
  $$select * from public.add_trip_person_by_email('11111111-1111-1111-1111-111111111111', 'dave@test.tab', 'Dave', '10000000-0000-0000-0000-000000000098')$$,
  'Alice adds a registered email without auto-linking the account');

insert into _r select ok(
  (select user_id is null and joined_at is null from public.trip_people where email = 'dave@test.tab'),
  'registered email invite remains pending until that user claims it');

insert into _r select lives_ok(
  $$select * from public.add_trip_person_by_email('11111111-1111-1111-1111-111111111111', 'delete-me@test.tab', 'Delete Me', '10000000-0000-0000-0000-000000000097')$$,
  'Alice adds a reference-free pending person for delete policy coverage');

delete from public.trip_people where id = '10000000-0000-0000-0000-000000000097';
insert into _r select is(
  (select count(*)::int from public.trip_people where id = '10000000-0000-0000-0000-000000000097'),
  1, 'direct trip_people hard delete has no effect; removals must go through server-owned paths');

insert into _r select is(
  (select count(*)::int from public.suggest_trip_people('bob', 8)),
  1,
  'suggestions include people Alice has shared trips with');

insert into _r select throws_ok(
  $$select * from public.add_trip_person_by_email('22222222-2222-2222-2222-222222222222', 'mallory@test.tab', 'Mallory', null)$$,
  '42501', null, 'Alice cannot add people to Solo');

insert into _r select lives_ok(
  $$select public.create_expense_with_payments_and_splits(
      jsonb_build_object(
        'id', 'aaaaaaaa-0000-0000-0000-000000000001',
        'trip_id', '11111111-1111-1111-1111-111111111111',
        'amount', 10,
        'currency', 'EUR',
        'description', 'Dinner',
        'expense_date', '2026-05-01',
        'receipt_storage_path', '11111111-1111-1111-1111-111111111111/aaaaaaaa-0000-0000-0000-000000000001.jpg'
      ),
      jsonb_build_array(jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000001', 'amount_paid', 10, 'payment_mode', 'equal')),
      jsonb_build_array(jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000001', 'amount_owed', 10, 'split_type', 'equal'))
    )$$,
  'Alice writes Lisbon expense through RPC');

insert into _r select ok(
  private.can_write_receipt_object('11111111-1111-1111-1111-111111111111/aaaaaaaa-0000-0000-0000-000000000001.jpg'),
  'expense creator can write the matching receipt object');

insert into _r select ok(
  not private.can_write_receipt_object('11111111-1111-1111-1111-111111111111/bbbbbbbb-0000-0000-0000-000000000001.jpg'),
  'receipt writes require a matching expense receipt path');

select public.create_trip_with_self('33333333-3333-3333-3333-333333333333', '30000000-0000-0000-0000-000000000001', 'Porto');

insert into _r select throws_ok(
  $$update public.trips set created_by = '00000000-0000-0000-0000-000000000002' where id = '11111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'direct trip creator rewrite denied');

insert into _r select throws_ok(
  $$update public.expenses set trip_id = '33333333-3333-3333-3333-333333333333' where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  '42501', null, 'direct expense trip move denied');

insert into _r select throws_ok(
  $$update public.expenses set created_by = '00000000-0000-0000-0000-000000000002' where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  '42501', null, 'direct expense creator rewrite denied');

delete from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000001';
insert into _r select is(
  (select count(*)::int from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  1, 'direct hard delete of expense has no effect; use deleted_at');

insert into public.categories (id, trip_id, name, icon, is_default)
values ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Local', 'tag', false);

delete from public.categories where id = 'cccccccc-0000-0000-0000-000000000001';
insert into _r select is(
  (select count(*)::int from public.categories where id = 'cccccccc-0000-0000-0000-000000000001'),
  1, 'direct hard delete of category has no effect; use deleted_at');

insert into public.settlements (id, trip_id, from_person_id, to_person_id, amount, currency, created_by)
values ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 5, 'EUR', '00000000-0000-0000-0000-000000000001');

insert into _r select throws_ok(
  $$update public.settlements set created_by = '00000000-0000-0000-0000-000000000002' where id = 'bbbbbbbb-0000-0000-0000-000000000001'$$,
  '42501', null, 'direct settlement creator rewrite denied');

delete from public.settlements where id = 'bbbbbbbb-0000-0000-0000-000000000001';
insert into _r select is(
  (select count(*)::int from public.settlements where id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  1, 'direct hard delete of settlement has no effect; use deleted_at');

delete from public.trips where id = '33333333-3333-3333-3333-333333333333';
insert into _r select is(
  (select count(*)::int from public.trips where id = '33333333-3333-3333-3333-333333333333'),
  1, 'direct hard delete of trip has no effect; use deleted_at');

insert into _r select throws_ok(
  $$select public.create_expense_with_payments_and_splits(
      jsonb_build_object('id', 'aaaaaaaa-0000-0000-0000-000000000002', 'trip_id', '22222222-2222-2222-2222-222222222222', 'amount', 10, 'currency', 'EUR', 'description', 'Wrong', 'expense_date', '2026-05-01'),
      jsonb_build_array(jsonb_build_object('trip_person_id', '20000000-0000-0000-0000-000000000003', 'amount_paid', 10, 'payment_mode', 'equal')),
      jsonb_build_array(jsonb_build_object('trip_person_id', '20000000-0000-0000-0000-000000000003', 'amount_owed', 10, 'split_type', 'equal'))
    )$$,
  '42501', null, 'Alice cannot write Solo expense through RPC');

-- Bob is also a Lisbon member.
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
insert into _r select is((select count(*)::int from public.trips where id = '11111111-1111-1111-1111-111111111111'), 1, 'Bob sees Lisbon');
insert into _r select ok(
  not private.can_write_receipt_object('11111111-1111-1111-1111-111111111111/aaaaaaaa-0000-0000-0000-000000000001.jpg'),
  'same-trip non-creator cannot overwrite or delete another member receipt object');

-- Carol is only a Solo member.
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into _r select is((select count(*)::int from public.trips where id = '11111111-1111-1111-1111-111111111111'), 0, 'Carol cannot see Lisbon');

-- A later signup with the pending email claims the trip automatically.
reset role;
insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values ('00000000-0000-0000-0000-000000000004', 'newuser@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"New User"}');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000004","role":"authenticated"}';

insert into _r select lives_ok($$select * from public.claim_trip_people_for_current_email()$$, 'new user claims pending email rows');
insert into _r select is((select count(*)::int from public.trips where id = '11111111-1111-1111-1111-111111111111'), 1, 'new user sees Lisbon after claim');
insert into _r select is((select user_id from public.trip_people where email = 'newuser@test.tab'), '00000000-0000-0000-0000-000000000004'::uuid, 'pending person linked to new auth user');

insert into _r select * from finish();
select line from _r;
rollback;
