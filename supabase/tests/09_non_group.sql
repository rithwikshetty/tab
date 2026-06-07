-- 09_non_group.sql — non-group containers: resolution, dedup, RLS privacy, claim.

begin;
set search_path = extensions, public, pg_temp;

select plan(25);
create temp table _r (line text);
grant insert, select on _r to authenticated;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000001', 'alice@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Alice"}'),
  ('00000000-0000-0000-0000-000000000002', 'bob@test.tab',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Bob"}'),
  ('00000000-0000-0000-0000-000000000003', 'carol@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Carol"}');

-- ============================================================================
-- Alice resolves / writes
-- ============================================================================
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

insert into _r select lives_ok(
  $$select * from public.resolve_or_create_non_group_container('[{"email":"bob@test.tab","display_name":"Bob"}]'::jsonb)$$,
  'Alice resolves a non-group container with Bob');

insert into _r select is(
  (select count(*)::int from public.trips where kind = 'non_group'),
  1, 'exactly one non-group container exists');

insert into _r select is(
  (select member_signature from public.trips where kind = 'non_group'),
  'alice@test.tab|bob@test.tab', 'signature is the canonical sorted emails');

insert into _r select is(
  (select count(*)::int from public.resolve_or_create_non_group_container('[{"email":"bob@test.tab"}]'::jsonb)),
  2, 'container has Alice and Bob (resolve returns both people)');

insert into _r select is(
  (select count(*)::int from public.trips where kind = 'non_group'),
  1, 'resolving the same set again is idempotent — still one container');

insert into _r select is(
  (select count(*)::int
   from public.activity_log
   where trip_id = (select id from public.trips where kind = 'non_group' and member_signature = 'alice@test.tab|bob@test.tab')
     and action in ('trip_created', 'member_joined')),
  0, 'hidden non-group container/member scaffolding does not create Activity rows');

insert into _r select is(
  (with attempted as (
    update public.trips
    set name = 'visible bucket'
    where kind = 'non_group' and member_signature = 'alice@test.tab|bob@test.tab'
    returning 1
  ) select count(*)::int from attempted),
  0, 'clients cannot directly update hidden non-group trip rows');

insert into _r select lives_ok(
  format(
    $f$select public.create_expense_with_payments_and_splits(
      jsonb_build_object('id', %L, 'trip_id', %L, 'amount', 10, 'currency', 'EUR', 'description', 'Casual dinner', 'expense_date', '2026-05-01'),
      jsonb_build_array(jsonb_build_object('trip_person_id', %L, 'amount_paid', 10, 'payment_mode', 'equal')),
      jsonb_build_array(
        jsonb_build_object('trip_person_id', %L, 'amount_owed', 5, 'split_type', 'equal'),
        jsonb_build_object('trip_person_id', %L, 'amount_owed', 5, 'split_type', 'equal'))
    )$f$,
    gen_random_uuid(),
    (select id from public.trips where kind = 'non_group' and member_signature = 'alice@test.tab|bob@test.tab'),
    (select id from public.trip_people where user_id = '00000000-0000-0000-0000-000000000001' and trip_id = (select id from public.trips where kind = 'non_group' and member_signature = 'alice@test.tab|bob@test.tab')),
    (select id from public.trip_people where user_id = '00000000-0000-0000-0000-000000000001' and trip_id = (select id from public.trips where kind = 'non_group' and member_signature = 'alice@test.tab|bob@test.tab')),
    (select id from public.trip_people where user_id = '00000000-0000-0000-0000-000000000002' and trip_id = (select id from public.trips where kind = 'non_group' and member_signature = 'alice@test.tab|bob@test.tab'))
  ),
  'Alice writes a non-group expense (split with Bob) through the expense RPC');

insert into _r select is(
  (select count(*)::int from public.expenses where trip_id = (select id from public.trips where kind = 'non_group' and member_signature = 'alice@test.tab|bob@test.tab')),
  1, 'Alice sees the non-group expense');

insert into _r select is(
  (select snapshot_json->>'trip_name'
   from public.activity_log
   where action = 'expense_created'
     and trip_id = (select id from public.trips where kind = 'non_group' and member_signature = 'alice@test.tab|bob@test.tab')
   order by timestamp desc
   limit 1),
  'Non-group', 'non-group expense Activity rows use a readable source name');

insert into _r select lives_ok(
  $$select * from public.resolve_or_create_non_group_container('[{"email":"carol@test.tab","display_name":"Carol"}]'::jsonb)$$,
  'Alice resolves a separate non-group container with Carol');

insert into _r select is(
  (select count(*)::int from public.trips where kind = 'non_group'),
  2, 'Alice now sees two non-group containers');

insert into _r select lives_ok(
  $$select * from public.resolve_or_create_non_group_container('[{"email":"frank@test.tab","display_name":"Frank"}]'::jsonb)$$,
  'Alice resolves a non-group container with a not-yet-registered email');

insert into _r select ok(
  (select user_id is null and joined_at is null
   from public.trip_people where email = 'frank@test.tab'),
  'the unregistered participant is pending until they sign in');

insert into _r select throws_ok(
  $$insert into public.trips (name, kind, member_signature, created_by)
    values ('sneaky', 'non_group', 'x|y', '00000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'a client cannot directly insert a non-group container');

reset role;
insert into _r select throws_ok(
  $$update public.trips set kind = 'trip'
    where kind = 'non_group' and member_signature = 'alice@test.tab|bob@test.tab'$$,
  '42501', null, 'trips.kind is immutable even outside client RLS');
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

-- ============================================================================
-- Bob: shares the {Alice,Bob} container but NOT {Alice,Carol}
-- ============================================================================
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';

insert into _r select is(
  (select count(*)::int from public.trips where kind = 'non_group' and member_signature = 'alice@test.tab|bob@test.tab'),
  1, 'Bob sees the {Alice,Bob} container');

insert into _r select is(
  (select count(*)::int from public.trips where kind = 'non_group' and member_signature = 'alice@test.tab|carol@test.tab'),
  0, 'Bob CANNOT see the {Alice,Carol} container (privacy)');

insert into _r select is(
  (select count(*)::int from public.expenses where trip_id = (select id from public.trips where kind = 'non_group' and member_signature = 'alice@test.tab|bob@test.tab')),
  1, 'Bob sees the expense in the container he shares');

-- ============================================================================
-- Carol: shares {Alice,Carol} but NOT {Alice,Bob}
-- ============================================================================
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}';

insert into _r select is(
  (select count(*)::int from public.trips where kind = 'non_group' and member_signature = 'alice@test.tab|bob@test.tab'),
  0, 'Carol CANNOT see the {Alice,Bob} container (privacy)');

insert into _r select is(
  (select count(*)::int from public.trips where kind = 'non_group' and member_signature = 'alice@test.tab|carol@test.tab'),
  1, 'Carol sees the {Alice,Carol} container');

-- ============================================================================
-- Uniqueness: one container per participant set (enforced by the partial index)
-- ============================================================================
reset role;
insert into _r select throws_ok(
  $$insert into public.trips (name, kind, member_signature, created_by)
    values ('dup', 'non_group', 'alice@test.tab|bob@test.tab', '00000000-0000-0000-0000-000000000001')$$,
  '23505', null, 'a second container for the same participant set is rejected');

-- ============================================================================
-- Claim: a pending non-group participant is linked when they sign in
-- ============================================================================
insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values ('00000000-0000-0000-0000-000000000005', 'frank@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Frank"}');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000005","role":"authenticated"}';

insert into _r select lives_ok(
  $$select * from public.claim_trip_people_for_current_email()$$,
  'Frank claims his pending non-group rows on sign-in');

insert into _r select is(
  (select user_id from public.trip_people where email = 'frank@test.tab'),
  '00000000-0000-0000-0000-000000000005'::uuid, 'pending non-group participant linked to Frank');

insert into _r select is(
  (select count(*)::int from public.trips where kind = 'non_group' and member_signature = 'alice@test.tab|frank@test.tab'),
  1, 'Frank sees the {Alice,Frank} container after claim');

insert into _r select * from finish();
select line from _r;
rollback;
