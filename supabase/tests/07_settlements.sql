-- 07_settlements.sql — settlement scenarios with many dummy expenses.

begin;
set search_path = extensions, public, pg_temp;

select plan(9);
create temp table _r (line text);
grant insert, select on _r to authenticated;

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000001', 'alice@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Alice"}'),
  ('00000000-0000-0000-0000-000000000002', 'bob@test.tab',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Bob"}'),
  ('00000000-0000-0000-0000-000000000003', 'cara@test.tab',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Cara"}'),
  ('00000000-0000-0000-0000-000000000004', 'mallory@test.tab', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '{"display_name":"Mallory"}');

insert into public.trips (id, name, created_by)
values
  ('11111111-1111-1111-1111-111111111111', 'Settlement Stress Trip', '00000000-0000-0000-0000-000000000001'),
  ('22222222-2222-2222-2222-222222222222', 'Other Trip', '00000000-0000-0000-0000-000000000004');

insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
values
  ('10000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 'alice@test.tab', 'Alice', '00000000-0000-0000-0000-000000000001', now()),
  ('10000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000002', 'bob@test.tab', 'Bob', '00000000-0000-0000-0000-000000000001', now()),
  ('10000000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000003', 'cara@test.tab', 'Cara', '00000000-0000-0000-0000-000000000001', now()),
  ('10000000-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', null, 'dee@test.tab', 'Dee', '00000000-0000-0000-0000-000000000001', null),
  ('20000000-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000004', 'mallory@test.tab', 'Mallory', '00000000-0000-0000-0000-000000000004', now());

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

insert into _r select lives_ok(
  $sql$do $body$
    declare i int;
    begin
      -- Stress the settlement path with enough ledger rows to catch fixture
      -- shortcuts while keeping the arithmetic human-checkable: Alice fronts
      -- 12 x EUR 120, split equally across four trip people.
      for i in 1..12 loop
        perform public.create_expense_with_payments_and_splits(
          jsonb_build_object(
            'id', ('aaaaaaaa-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
            'trip_id', '11111111-1111-1111-1111-111111111111',
            'amount', 120,
            'currency', 'EUR',
            'description', 'Shared cost ' || i,
            'expense_date', '2026-05-01'::date + i
          ),
          jsonb_build_array(
            jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000001', 'amount_paid', 120, 'payment_mode', 'exact')
          ),
          jsonb_build_array(
            jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000001', 'amount_owed', 30, 'split_type', 'exact'),
            jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000002', 'amount_owed', 30, 'split_type', 'exact'),
            jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000003', 'amount_owed', 30, 'split_type', 'exact'),
            jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000004', 'amount_owed', 30, 'split_type', 'exact')
          )
        );
      end loop;
    end
  $body$;$sql$,
  'joined member can create many expenses with joined and pending trip people');

insert into _r select is((select count(*)::int from public.expenses where trip_id = '11111111-1111-1111-1111-111111111111'), 12, 'twelve dummy expenses written');
insert into _r select is((select count(*)::int from public.expense_splits), 48, 'four split rows per dummy expense written');
insert into _r select is((select count(*)::int from public.expense_payments), 12, 'one payment row per dummy expense written');

insert into _r select lives_ok(
  $$insert into public.settlements (id, trip_id, from_person_id, to_person_id, amount, currency, note, created_by)
    values
      ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '10000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 180, 'EUR', 'Bob partial', '00000000-0000-0000-0000-000000000001'),
      ('bbbbbbbb-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '10000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 90, 'EUR', 'Cara partial', '00000000-0000-0000-0000-000000000001'),
      ('bbbbbbbb-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', '10000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', 45, 'EUR', 'Pending Dee partial', '00000000-0000-0000-0000-000000000001')$$,
  'joined member can record settlements involving joined and pending trip people');

insert into _r select is((select count(*)::int from public.settlements where trip_id = '11111111-1111-1111-1111-111111111111'), 3, 'three settlement rows written');
insert into _r select is((select count(*)::int from public.settlements where from_person_id = '10000000-0000-0000-0000-000000000004'), 1, 'pending email-added person can be a settlement party');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000004","role":"authenticated"}';
insert into _r select throws_ok(
  $$insert into public.settlements (trip_id, from_person_id, to_person_id, amount, currency, created_by)
    values ('11111111-1111-1111-1111-111111111111', '10000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 10, 'EUR', '00000000-0000-0000-0000-000000000004')$$,
  '23514', null, 'non-member cannot record a settlement in another trip');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into _r select throws_ok(
  $$insert into public.settlements (trip_id, from_person_id, to_person_id, amount, currency, created_by)
    values ('11111111-1111-1111-1111-111111111111', '10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000004', 10, 'EUR', '00000000-0000-0000-0000-000000000001')$$,
  '23514', null, 'settlement party from another trip rejected');

insert into _r select * from finish();
select line from _r;
rollback;
