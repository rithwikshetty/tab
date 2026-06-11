-- 12_rls_deny_gaps.sql — deny-path coverage for tables whose RLS previously
-- had no negative tests: expense_payments, expense_splits, push_devices,
-- trip_mute_prefs.

begin;
set search_path = extensions, public, pg_temp;

select plan(11);
create temp table _r (line text);
grant insert, select on _r to authenticated;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000061', 'member@test.tab',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Member"}'),
  ('00000000-0000-0000-0000-000000000062', 'outsider@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Outsider"}');

insert into public.trips (id, name, created_by)
values ('61111111-1111-1111-1111-111111111111', 'Deny Trip', '00000000-0000-0000-0000-000000000061');

insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
values ('60000000-0000-0000-0000-000000000001', '61111111-1111-1111-1111-111111111111',
        '00000000-0000-0000-0000-000000000061', 'member@test.tab', 'Member',
        '00000000-0000-0000-0000-000000000061', now());

insert into public.expenses (id, trip_id, amount, currency, description, expense_date, payment_method, created_by)
values ('62000000-0000-0000-0000-000000000001', '61111111-1111-1111-1111-111111111111',
        50, 'EUR', 'deny seed', '2026-06-01', 'card', '00000000-0000-0000-0000-000000000061');
insert into public.expense_payments (expense_id, trip_person_id, amount_paid, payment_mode)
values ('62000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 50, 'equal');
insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type)
values ('62000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 50, 'equal');

insert into public.push_devices (user_id, apns_token, device_name)
values ('00000000-0000-0000-0000-000000000061', 'token-member-1', 'Member iPhone');

insert into public.trip_mute_prefs (trip_id, user_id)
values ('61111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000061');

-- ── Outsider: every read comes back empty, every write is rejected.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000062","role":"authenticated"}';

insert into _r select is(
  (select count(*)::int from public.expense_payments),
  0, 'non-member cannot read expense payments');

insert into _r select is(
  (select count(*)::int from public.expense_splits),
  0, 'non-member cannot read expense splits');

insert into _r select throws_ok(
  $$insert into public.expense_payments (expense_id, trip_person_id, amount_paid, payment_mode)
    values ('62000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 1, 'exact')$$,
  '42501', null, 'non-member cannot insert an expense payment');

insert into _r select throws_ok(
  $$insert into public.expense_splits (expense_id, trip_person_id, amount_owed, split_type)
    values ('62000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 1, 'exact')$$,
  '42501', null, 'non-member cannot insert an expense split');

insert into _r select is(
  (select count(*)::int from public.push_devices),
  0, 'user cannot read another user''s push devices');

insert into _r select throws_ok(
  $$insert into public.push_devices (user_id, apns_token, device_name)
    values ('00000000-0000-0000-0000-000000000061', 'planted-token', 'Evil')$$,
  '42501', null, 'user cannot register a push device for another user');

delete from public.push_devices where user_id = '00000000-0000-0000-0000-000000000061';

insert into _r select is(
  (select count(*)::int from public.trip_mute_prefs),
  0, 'user cannot read another user''s mute prefs');

delete from public.trip_mute_prefs where user_id = '00000000-0000-0000-0000-000000000061';

reset role;

insert into _r select is(
  (select count(*)::int from public.push_devices where user_id = '00000000-0000-0000-0000-000000000061'),
  1, 'cross-user push-device delete affected nothing');

insert into _r select is(
  (select count(*)::int from public.trip_mute_prefs where user_id = '00000000-0000-0000-0000-000000000061'),
  1, 'cross-user mute delete affected nothing');

-- ── Member sanity allows.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000061","role":"authenticated"}';

insert into _r select is(
  (select count(*)::int from public.expense_payments),
  1, 'member reads their trip''s payments');

insert into _r select is(
  (select count(*)::int from public.trip_mute_prefs),
  1, 'member reads their own mute pref');

reset role;

insert into _r select * from finish();
select line from _r;
rollback;
