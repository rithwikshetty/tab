-- 04_rls.sql — RLS allow/deny paths for email-first trip people.

begin;
set search_path = extensions, public, pg_temp;

select plan(16);
create temp table _r (line text);
grant insert, select on _r to authenticated;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000001', 'alice@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Alice"}'),
  ('00000000-0000-0000-0000-000000000002', 'bob@test.tab',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Bob"}'),
  ('00000000-0000-0000-0000-000000000003', 'carol@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Carol"}');

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

insert into _r select throws_ok(
  $$insert into public.trip_people (trip_id, email, display_name) values ('11111111-1111-1111-1111-111111111111', 'direct@test.tab', 'Direct')$$,
  '42501', null, 'direct trip_people insert denied');

insert into _r select lives_ok(
  $$select * from public.add_trip_person_by_email('11111111-1111-1111-1111-111111111111', 'newuser@test.tab', 'New User', '10000000-0000-0000-0000-000000000099')$$,
  'Alice adds pending person by email');

insert into _r select ok(
  (select user_id is null and joined_at is null from public.trip_people where email = 'newuser@test.tab'),
  'new email is pending');

insert into _r select is(
  (select count(*)::int from public.suggest_trip_people('bob', 8)),
  1,
  'suggestions include people Alice has shared trips with');

insert into _r select throws_ok(
  $$select * from public.add_trip_person_by_email('22222222-2222-2222-2222-222222222222', 'mallory@test.tab', 'Mallory', null)$$,
  '42501', null, 'Alice cannot add people to Solo');

insert into _r select lives_ok(
  $$select public.create_expense_with_payments_and_splits(
      jsonb_build_object('id', 'aaaaaaaa-0000-0000-0000-000000000001', 'trip_id', '11111111-1111-1111-1111-111111111111', 'amount', 10, 'currency', 'EUR', 'description', 'Dinner', 'expense_date', '2026-05-01'),
      jsonb_build_array(jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000001', 'amount_paid', 10, 'payment_mode', 'equal')),
      jsonb_build_array(jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000001', 'amount_owed', 10, 'split_type', 'equal'))
    )$$,
  'Alice writes Lisbon expense through RPC');

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
