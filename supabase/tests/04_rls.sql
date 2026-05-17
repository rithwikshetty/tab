-- 04_rls.sql — Row-level security: allow vs deny per table, per role.
--
-- Simulates authenticated sessions via `set local role authenticated` plus
-- `set local request.jwt.claims` (which determines what auth.uid() returns).
--
-- For SELECT denials, RLS silently filters — we assert count(*) = 0.
-- For INSERT/UPDATE/DELETE denials, RLS raises SQLSTATE 42501.

begin;
set local search_path = extensions, public, pg_temp;

select plan(37);
create temp table _r (line text);
grant insert, select on _r to authenticated, anon;

create temp table _invite (trip_id uuid, invite_id uuid, token text, expires_at timestamptz);
grant insert, select, update, delete on _invite to authenticated;

-- ===== Fixture (runs as postgres / table owner — bypasses RLS) =====
insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000001'::uuid, 'alice@test.tab', '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', '{"display_name":"Alice"}'::jsonb),
  ('00000000-0000-0000-0000-000000000002'::uuid, 'bob@test.tab',   '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', '{"display_name":"Bob"}'::jsonb),
  ('00000000-0000-0000-0000-000000000003'::uuid, 'carol@test.tab', '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', '{"display_name":"Carol"}'::jsonb),
  ('00000000-0000-0000-0000-000000000004'::uuid, 'dave@test.tab',  '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', '{"display_name":"Dave"}'::jsonb);

-- Lisbon trip: Alice creates (auto-joined); Bob joined manually. Carol is not a member.
insert into public.trips (id, name, created_by)
values ('11111111-1111-1111-1111-111111111111'::uuid, 'Lisbon', '00000000-0000-0000-0000-000000000001'::uuid);

insert into public.trip_members (trip_id, user_id)
values ('11111111-1111-1111-1111-111111111111'::uuid, '00000000-0000-0000-0000-000000000002'::uuid);

-- Solo trip: Dave-only.
insert into public.trips (id, name, created_by)
values ('22222222-2222-2222-2222-222222222222'::uuid, 'Solo', '00000000-0000-0000-0000-000000000004'::uuid);

-- One Lisbon expense paid by Alice.
insert into public.expenses (id, trip_id, payer_id, amount, currency, description, expense_date, created_by)
values ('aaaaaaaa-0000-0000-0000-000000000001'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        '00000000-0000-0000-0000-000000000001'::uuid,
        85, 'EUR', 'Dinner at Ramiro', '2026-05-14',
        '00000000-0000-0000-0000-000000000001'::uuid);

-- One Solo expense by Dave.
insert into public.expenses (id, trip_id, payer_id, amount, currency, description, expense_date, created_by)
values ('aaaaaaaa-0000-0000-0000-000000000099'::uuid,
        '22222222-2222-2222-2222-222222222222'::uuid,
        '00000000-0000-0000-0000-000000000004'::uuid,
        50, 'USD', 'Lone lunch', '2026-05-10',
        '00000000-0000-0000-0000-000000000004'::uuid);

-- Bob's push device (used to test self-only RLS).
insert into public.push_devices (user_id, apns_token)
values ('00000000-0000-0000-0000-000000000002'::uuid, 'bob-token');

-- ============================================================================
-- AS ALICE (member of Lisbon)
-- ============================================================================
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

-- Can SEE Lisbon
insert into _r select is(
  (select count(*)::int from public.trips where id = '11111111-1111-1111-1111-111111111111'::uuid),
  1, 'Alice (member) sees Lisbon trip');

-- Cannot SEE Dave's Solo
insert into _r select is(
  (select count(*)::int from public.trips where id = '22222222-2222-2222-2222-222222222222'::uuid),
  0, 'Alice (non-member of Solo) sees zero rows for Solo trip');

-- Can SEE Lisbon expenses
insert into _r select is(
  (select count(*)::int from public.expenses where trip_id = '11111111-1111-1111-1111-111111111111'::uuid),
  1, 'Alice sees Lisbon expenses');

-- Cannot SEE Solo expenses
insert into _r select is(
  (select count(*)::int from public.expenses where trip_id = '22222222-2222-2222-2222-222222222222'::uuid),
  0, 'Alice cannot see Solo expenses');

-- Can INSERT a new expense in Lisbon (with self as created_by)
insert into _r select lives_ok(
  $$insert into public.expenses (trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 22.40, 'EUR', 'Uber', '2026-05-14', '00000000-0000-0000-0000-000000000001')$$,
  'Alice INSERTs Lisbon expense with created_by=self');

-- Cannot INSERT a Lisbon expense with created_by = Bob (WITH CHECK violation)
insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 5, 'EUR', 'spoof', '2026-05-14', '00000000-0000-0000-0000-000000000002')$$,
  '42501', null, 'Alice cannot spoof created_by to another user');

-- Cannot INSERT in Solo (non-member)
insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000001', 5, 'EUR', 'wrong trip', '2026-05-14', '00000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'Alice cannot INSERT in Solo (non-member)');

-- Can UPDATE Lisbon expense she did not author? Per PRD any member can edit anything.
insert into _r select lives_ok(
  $$update public.expenses set description = 'Dinner (edited)' where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  'Alice (member) can UPDATE any Lisbon expense (PRD: any member edits)');

-- Can DELETE (soft-delete via UPDATE deleted_at)
insert into _r select lives_ok(
  $$update public.expenses set deleted_at = now() where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  'Alice (member) can soft-delete a Lisbon expense');

-- Can SEE trip_members of Lisbon
insert into _r select is(
  (select count(*)::int from public.trip_members where trip_id = '11111111-1111-1111-1111-111111111111'::uuid),
  2, 'Alice sees both Lisbon members');

-- Can create an invite token for Lisbon.
insert into _r select lives_ok(
  $$insert into _invite (trip_id, invite_id, token, expires_at)
    select trip_id, invite_id, token, expires_at
    from public.create_trip_invite('11111111-1111-1111-1111-111111111111'::uuid)$$,
  'Alice creates Lisbon invite via RPC');

-- Cannot SEE trip_members of Solo
insert into _r select is(
  (select count(*)::int from public.trip_members where trip_id = '22222222-2222-2222-2222-222222222222'::uuid),
  0, 'Alice cannot see Solo trip_members');

-- Can SELECT all profiles (open policy)
insert into _r select ok(
  (select count(*)::int from public.profiles) >= 4,
  'Alice sees all profiles (open SELECT policy)');

-- Cannot UPDATE Bob's profile. RLS USING-clause silently filters non-matching
-- rows on UPDATE — no error, just 0 rows affected. Verify Bob's name unchanged.
update public.profiles set display_name = 'pwned' where id = '00000000-0000-0000-0000-000000000002'::uuid;
insert into _r select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-000000000002'::uuid),
  'Bob',
  'Alice UPDATE to Bob profile filtered by RLS (Bob.display_name unchanged)');

-- Can SELECT defaults categories
insert into _r select is(
  (select count(*)::int from public.categories where is_default),
  6, 'Alice sees all 6 built-in categories');

-- Can INSERT custom category in Lisbon
insert into _r select lives_ok(
  $$insert into public.categories (trip_id, name, icon, is_default) values ('11111111-1111-1111-1111-111111111111', 'Coffee', '☕', false)$$,
  'Alice INSERTs custom Lisbon category');

-- Cannot INSERT custom category in Solo
insert into _r select throws_ok(
  $$insert into public.categories (trip_id, name, icon, is_default) values ('22222222-2222-2222-2222-222222222222', 'Coffee', '☕', false)$$,
  '42501', null, 'Alice cannot INSERT custom category in Solo');

-- Cannot INSERT default-flag category (RLS check: not is_default required)
insert into _r select throws_ok(
  $$insert into public.categories (trip_id, name, icon, is_default) values ('11111111-1111-1111-1111-111111111111', 'XYZ', '?', true)$$,
  '42501', null, 'Member cannot INSERT default-flagged category (RLS WITH CHECK fires first: not is_default required)');

-- Can SELECT activity_log for Lisbon (none yet, just verify no error)
insert into _r select is(
  (select count(*)::int from public.activity_log where trip_id = '11111111-1111-1111-1111-111111111111'::uuid),
  0, 'Alice SELECTs Lisbon activity_log (empty, no error)');

-- Can INSERT activity_log as self
insert into _r select lives_ok(
  $$insert into public.activity_log (trip_id, actor_id, action, entity_type, entity_id)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 'expense_created', 'expense', 'aaaaaaaa-0000-0000-0000-000000000001')$$,
  'Alice INSERTs activity_log as self');

-- Cannot INSERT activity_log spoofing another actor
insert into _r select throws_ok(
  $$insert into public.activity_log (trip_id, actor_id, action, entity_type, entity_id)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000002', 'expense_created', 'expense', 'aaaaaaaa-0000-0000-0000-000000000001')$$,
  '42501', null, 'Alice cannot INSERT activity_log with actor_id != self');

-- Cannot SELECT Bob's push_devices
insert into _r select is(
  (select count(*)::int from public.push_devices where user_id = '00000000-0000-0000-0000-000000000002'::uuid),
  0, 'Alice cannot see Bob push_devices (self-only)');

-- Can INSERT own push_devices
insert into _r select lives_ok(
  $$insert into public.push_devices (user_id, apns_token) values ('00000000-0000-0000-0000-000000000001', 'alice-token')$$,
  'Alice INSERTs own push_devices');

-- Cannot INSERT push_devices for another user
insert into _r select throws_ok(
  $$insert into public.push_devices (user_id, apns_token) values ('00000000-0000-0000-0000-000000000002', 'spoof-token')$$,
  '42501', null, 'Alice cannot INSERT push_devices with user_id=Bob');

-- ============================================================================
-- AS CAROL (NOT a member of any trip)
-- ============================================================================
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}';

-- Cannot SEE Lisbon
insert into _r select is(
  (select count(*)::int from public.trips where id = '11111111-1111-1111-1111-111111111111'::uuid),
  0, 'Carol (non-member) cannot SELECT Lisbon');

-- Cannot SEE Lisbon expenses
insert into _r select is(
  (select count(*)::int from public.expenses where trip_id = '11111111-1111-1111-1111-111111111111'::uuid),
  0, 'Carol cannot SELECT Lisbon expenses');

-- Cannot INSERT in Lisbon
insert into _r select throws_ok(
  $$insert into public.expenses (trip_id, payer_id, amount, currency, description, expense_date, created_by)
    values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000003', 5, 'EUR', 'intruder', '2026-05-14', '00000000-0000-0000-0000-000000000003')$$,
  '42501', null, 'Carol cannot INSERT in Lisbon');

-- Cannot SEE Lisbon trip_members
insert into _r select is(
  (select count(*)::int from public.trip_members where trip_id = '11111111-1111-1111-1111-111111111111'::uuid),
  0, 'Carol cannot SELECT Lisbon trip_members');

-- Cannot SEE Lisbon's custom categories
insert into _r select is(
  (select count(*)::int from public.categories where trip_id = '11111111-1111-1111-1111-111111111111'::uuid),
  0, 'Carol cannot SELECT Lisbon custom categories');

-- Can SELECT default categories (open to all authenticated)
insert into _r select is(
  (select count(*)::int from public.categories where is_default),
  6, 'Carol sees default categories');

-- Can SELECT profiles (open policy)
insert into _r select ok(
  (select count(*)::int from public.profiles) >= 4,
  'Carol sees all profiles (open SELECT policy)');

-- Cannot SELF-INSERT trip_members directly. Invite-only joining is enforced by
-- removing direct INSERT RLS and routing through join_trip_with_invite.
insert into _r select throws_ok(
  $$insert into public.trip_members (trip_id, user_id) values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000003')$$,
  '42501', null, 'Carol cannot self-add to Lisbon without invite RPC');

-- Can join via the invite token Alice created.
insert into _r select lives_ok(
  $$select public.join_trip_with_invite(
      (select trip_id from _invite limit 1),
      (select invite_id from _invite limit 1),
      (select token from _invite limit 1)
    )$$,
  'Carol joins Lisbon via invite RPC');

-- After invite join, Carol can now SELECT Lisbon.
insert into _r select is(
  (select count(*)::int from public.trips where id = '11111111-1111-1111-1111-111111111111'::uuid),
  1, 'After invite join, Carol sees Lisbon');

-- ============================================================================
-- AS ANON (no JWT)
-- ============================================================================
reset role;
set local role anon;

-- Cannot SEE anything
insert into _r select is(
  (select count(*)::int from public.trips), 0, 'anon cannot SELECT trips');
insert into _r select is(
  (select count(*)::int from public.expenses), 0, 'anon cannot SELECT expenses');
insert into _r select is(
  (select count(*)::int from public.profiles), 0, 'anon cannot SELECT profiles');

reset role;
insert into _r select * from finish();
select line from _r;
rollback;
