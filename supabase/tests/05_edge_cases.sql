-- 05_edge_cases.sql — helper behavior, cascades, and purge edges.

begin;
set search_path = extensions, public, pg_temp;

select plan(10);
create temp table _r (line text);

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000001', 'alice@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Alice"}'),
  ('00000000-0000-0000-0000-000000000002', 'bob@test.tab',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Bob"}');

insert into public.trips (id, name, created_by)
values
  ('11111111-1111-1111-1111-111111111111', 'Lisbon', '00000000-0000-0000-0000-000000000001'),
  ('22222222-2222-2222-2222-222222222222', 'Cascade', '00000000-0000-0000-0000-000000000001');

insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
values
  ('10000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 'alice@test.tab', 'Alice', '00000000-0000-0000-0000-000000000001', now()),
  ('10000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', null, 'pending@test.tab', 'Pending', '00000000-0000-0000-0000-000000000001', null),
  ('20000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000001', 'alice@test.tab', 'Alice', '00000000-0000-0000-0000-000000000001', now());

insert into _r select ok(
  private.is_profile_trip_member('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001'),
  'is_profile_trip_member true for joined person');

insert into _r select ok(
  not private.is_profile_trip_member('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000002'),
  'is_profile_trip_member false for non-member even if pending email exists');

insert into _r select ok(
  private.is_trip_person('11111111-1111-1111-1111-111111111111', '10000000-0000-0000-0000-000000000002'),
  'is_trip_person true for pending ledger person');

insert into _r select is(
  private.normalized_email('  PERSON@Example.COM  '),
  'person@example.com',
  'normalized_email lowercases and trims');

insert into _r select throws_ok(
  $$delete from public.profiles where id = '00000000-0000-0000-0000-000000000001'$$,
  '23503', null, 'joined trip_people restrict profile hard-delete');

delete from public.trips where id = '22222222-2222-2222-2222-222222222222';
insert into _r select is(
  (select count(*)::int from public.trip_people where trip_id = '22222222-2222-2222-2222-222222222222'),
  0,
  'trip hard-delete cascades trip_people');

insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by, deleted_at)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 10, 'EUR', 'Old deleted', '2026-05-01', '00000000-0000-0000-0000-000000000001', now() - interval '40 days');

insert into _r select lives_ok(
  $$select * from public.purge_soft_deleted_records(now() - interval '30 days')$$,
  'purge_soft_deleted_records runs');

insert into _r select is(
  (select count(*)::int from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  0,
  'purge removes old soft-deleted expense');

insert into public.trips (id, name, created_by, deleted_at)
values ('33333333-3333-3333-3333-333333333333', 'Deleted empty', '00000000-0000-0000-0000-000000000001', now() - interval '40 days');
insert into public.trip_people (id, trip_id, user_id, email, display_name, joined_at)
values ('30000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000001', 'deleted@test.tab', 'Deleted', now());

insert into _r select lives_ok(
  $$select * from public.purge_soft_deleted_records(now() - interval '30 days')$$,
  'purge runs for old empty deleted trip');

insert into _r select is(
  (select count(*)::int from public.trips where id = '33333333-3333-3333-3333-333333333333'),
  0,
  'purge removes old soft-deleted empty trip');

insert into _r select * from finish();
select line from _r;
rollback;
