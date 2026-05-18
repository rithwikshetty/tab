-- 06_expense_payments.sql — transactional expense RPC with trip_person IDs.

begin;
set search_path = extensions, public, pg_temp;

select plan(10);
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

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

insert into _r select lives_ok(
  $$select public.create_expense_with_payments_and_splits(
      jsonb_build_object('id', 'aaaaaaaa-0000-0000-0000-000000000001', 'trip_id', '11111111-1111-1111-1111-111111111111', 'amount', 100, 'currency', 'EUR', 'description', 'Villa', 'expense_date', '2026-05-01'),
      jsonb_build_array(
        jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000001', 'amount_paid', 60, 'payment_mode', 'exact'),
        jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000002', 'amount_paid', 40, 'payment_mode', 'exact')
      ),
      jsonb_build_array(
        jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000001', 'amount_owed', 50, 'split_type', 'equal'),
        jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000002', 'amount_owed', 50, 'split_type', 'equal')
      )
    )$$,
  'multi-payer expense RPC succeeds');

insert into _r select is((select count(*)::int from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 1, 'expense row exists');
insert into _r select is((select count(*)::int from public.expense_payments where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 2, 'two payment rows written');
insert into _r select is((select count(*)::int from public.expense_splits where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 2, 'two split rows written');
insert into _r select is((select sum(amount_paid)::numeric(14,2) from public.expense_payments where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 100.00::numeric(14,2), 'payment total matches expense');
insert into _r select is((select sum(amount_owed)::numeric(14,2) from public.expense_splits where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 100.00::numeric(14,2), 'split total matches expense');

insert into _r select throws_ok(
  $$select public.create_expense_with_payments_and_splits(
      jsonb_build_object('id', 'aaaaaaaa-0000-0000-0000-000000000002', 'trip_id', '11111111-1111-1111-1111-111111111111', 'amount', 20, 'currency', 'EUR', 'description', 'Wrong person', 'expense_date', '2026-05-01'),
      jsonb_build_array(jsonb_build_object('trip_person_id', '20000000-0000-0000-0000-000000000003', 'amount_paid', 20, 'payment_mode', 'equal')),
      jsonb_build_array(jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000001', 'amount_owed', 20, 'split_type', 'equal'))
    )$$,
  '23514', null, 'RPC rejects payment person from another trip');

insert into _r select lives_ok(
  $$select public.create_expense_with_payments_and_splits(
      jsonb_build_object('id', 'aaaaaaaa-0000-0000-0000-000000000001', 'trip_id', '11111111-1111-1111-1111-111111111111', 'amount', 100, 'currency', 'EUR', 'description', 'Villa edited', 'expense_date', '2026-05-02'),
      jsonb_build_array(jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000001', 'amount_paid', 100, 'payment_mode', 'equal')),
      jsonb_build_array(jsonb_build_object('trip_person_id', '10000000-0000-0000-0000-000000000001', 'amount_owed', 100, 'split_type', 'equal'))
    )$$,
  'expense RPC replaces existing payment and split ledgers');

insert into _r select is((select count(*)::int from public.expense_payments where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 1, 'payment rows replaced');
insert into _r select is((select count(*)::int from public.expense_splits where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 1, 'split rows replaced');

insert into _r select * from finish();
select line from _r;
rollback;
