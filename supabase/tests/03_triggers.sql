-- 03_triggers.sql — sync triggers and transactional trip creation.

begin;
set search_path = extensions, public, pg_temp;

select plan(9);
create temp table _r (line text);
grant insert, select on _r to authenticated;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000001', 'alice@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Alice"}'),
  ('00000000-0000-0000-0000-000000000002', 'bob@test.tab',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Bob"}');

insert into _r select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-000000000001'),
  'Alice',
  'handle_new_user creates profile with metadata display name');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

insert into _r select lives_ok(
  $$select * from public.create_trip_with_self(
      '11111111-1111-1111-1111-111111111111',
      '10000000-0000-0000-0000-000000000001',
      'Lisbon'
    )$$,
  'create_trip_with_self runs');

insert into _r select is(
  (select created_by from public.trips where id = '11111111-1111-1111-1111-111111111111'),
  '00000000-0000-0000-0000-000000000001'::uuid,
  'create_trip_with_self inserts trip with auth.uid creator');

insert into _r select is(
  (select user_id from public.trip_people where id = '10000000-0000-0000-0000-000000000001'),
  '00000000-0000-0000-0000-000000000001'::uuid,
  'create_trip_with_self inserts creator trip person with client UUID');

insert into _r select ok(
  (select joined_at is not null from public.trip_people where id = '10000000-0000-0000-0000-000000000001'),
  'creator trip person is joined');

insert into _r select lives_ok(
  $$select * from public.add_trip_person_by_email(
      '11111111-1111-1111-1111-111111111111',
      'pending@test.tab',
      'Pending',
      '10000000-0000-0000-0000-000000000099'
    )$$,
  'add_trip_person_by_email creates pending person');

insert into _r select ok(
  (select user_id is null and joined_at is null from public.trip_people where email = 'pending@test.tab'),
  'pending person remains unclaimed until matching sign-in');

insert into _r select lives_ok(
  $$select public.create_expense_with_payments_and_splits(
      jsonb_build_object('id', 'aaaaaaaa-0000-0000-0000-000000000001', 'trip_id', '11111111-1111-1111-1111-111111111111', 'amount', 10, 'currency', 'EUR', 'description', 'Dinner', 'expense_date', '2026-05-01'),
      jsonb_build_array(jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000001', 'amount_paid', 10, 'payment_mode', 'equal')),
      jsonb_build_array(jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000001', 'amount_owed', 10, 'split_type', 'equal'))
    )$$,
  'expense RPC writes expense with payments and splits');

insert into _r select ok(
  (select last_activity_at > created_at from public.trips where id = '11111111-1111-1111-1111-111111111111'),
  'expense insert touches trip.last_activity_at');

insert into _r select * from finish();
select line from _r;
rollback;
