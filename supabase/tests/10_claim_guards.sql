-- 10_claim_guards.sql — claimed trip_people rows must never transfer between
-- accounts via the email-unique upserts, and participant emails must not be
-- able to pollute non-group member signatures.

begin;
set search_path = extensions, public, pg_temp;

select plan(8);
create temp table _r (line text);
grant insert, select on _r to authenticated;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000041', 'shared@test.tab',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Avery"}'),
  ('00000000-0000-0000-0000-000000000042', 'brook@test.tab',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Brook"}'),
  ('00000000-0000-0000-0000-000000000043', 'carol3@test.tab',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Carol"}'),
  ('00000000-0000-0000-0000-000000000044', 'evan@test.tab',    '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Evan"}');

-- ── Scenario 1: create_trip_with_self must not steal a claimed person row.
-- Avery (auth email shared@test.tab) creates a trip, claiming person row P.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000041","role":"authenticated"}';
select public.create_trip_with_self(
  '31111111-1111-1111-1111-111111111111',
  '30000000-0000-0000-0000-000000000001',
  'Guard Trip'
);
reset role;

-- Avery's auth email moves on; Brook registers the recycled address and is
-- separately a legitimate member of the same trip under another person row.
update auth.users set email = 'avery-moved@test.tab' where id = '00000000-0000-0000-0000-000000000041';
update auth.users set email = 'shared@test.tab'      where id = '00000000-0000-0000-0000-000000000042';
insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
values ('30000000-0000-0000-0000-000000000002', '31111111-1111-1111-1111-111111111111',
        '00000000-0000-0000-0000-000000000042', 'brook@test.tab', 'Brook',
        '00000000-0000-0000-0000-000000000041', now());

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000042","role":"authenticated"}';

insert into _r select throws_ok(
  $$select public.create_trip_with_self(
      '31111111-1111-1111-1111-111111111111',
      '30000000-0000-0000-0000-000000000099',
      'Guard Trip')$$,
  '42501', null, 'create_trip_with_self refuses to reassign a claimed person row');

reset role;

insert into _r select is(
  (select user_id from public.trip_people where id = '30000000-0000-0000-0000-000000000001'),
  '00000000-0000-0000-0000-000000000041'::uuid,
  'claimed person row keeps its original account after attempted steal');

-- Idempotent re-claim by the same account is still allowed (offline retry).
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000042","role":"authenticated"}';
select public.create_trip_with_self(
  '32222222-2222-2222-2222-222222222222',
  '30000000-0000-0000-0000-000000000011',
  'Brook Solo'
);
select public.create_trip_with_self(
  '32222222-2222-2222-2222-222222222222',
  '30000000-0000-0000-0000-000000000011',
  'Brook Solo Renamed'
);
reset role;

insert into _r select is(
  (select user_id from public.trip_people where id = '30000000-0000-0000-0000-000000000011'),
  '00000000-0000-0000-0000-000000000042'::uuid,
  'same-account re-claim stays idempotent');

insert into _r select is(
  (select name from public.trips where id = '32222222-2222-2222-2222-222222222222'),
  'Brook Solo Renamed',
  'same-account retry still applies the trip update');

-- ── Scenario 2: resolve_or_create_non_group_container must not steal either.
-- Carol creates a non-group container with pending participant dana.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000043","role":"authenticated"}';
select count(*) from public.resolve_or_create_non_group_container(
  '[{"email":"dana@test.tab","display_name":"Dana"}]'::jsonb
);
reset role;

-- Carol's auth email is recycled to Evan.
update auth.users set email = 'carol-moved@test.tab' where id = '00000000-0000-0000-0000-000000000043';
update auth.users set email = 'carol3@test.tab'      where id = '00000000-0000-0000-0000-000000000044';

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000044","role":"authenticated"}';

insert into _r select throws_ok(
  $$select count(*) from public.resolve_or_create_non_group_container(
      '[{"email":"dana@test.tab","display_name":"Dana"}]'::jsonb)$$,
  '42501', null, 'non-group resolver refuses to reassign a claimed person row');

reset role;

insert into _r select is(
  (select tp.user_id
   from public.trip_people tp
   join public.trips t on t.id = tp.trip_id
   where t.kind = 'non_group' and tp.email = 'carol3@test.tab'),
  '00000000-0000-0000-0000-000000000043'::uuid,
  'container person row keeps its original account after attempted steal');

-- ── Scenario 3: '|' in a participant email must be rejected (it is the
-- member_signature delimiter, so it could forge another set's identity).
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000044","role":"authenticated"}';

insert into _r select throws_ok(
  $$select count(*) from public.resolve_or_create_non_group_container(
      '[{"email":"b@b|c@c","display_name":"Phantom"}]'::jsonb)$$,
  '22023', null, 'participant emails containing the signature delimiter are rejected');

reset role;

insert into _r select is(
  (select count(*)::int from public.trip_people where email like '%|%'),
  0,
  'no person row carries a delimiter-bearing email');

insert into _r select * from finish();
select line from _r;
rollback;
