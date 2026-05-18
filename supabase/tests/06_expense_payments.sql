-- 06_expense_payments.sql — column constraints, sum invariant, trigger logic,
-- cascade behavior, RLS allow/deny for the new expense_payments table.
--
-- Run via mcp__supabase__execute_sql.
--
-- Notes on test mechanics:
-- * `set constraints all deferred` is sprinkled before every deferred-constraint
--   test because pgTAP's throws_ok/lives_ok savepoint does NOT revert prior
--   `set constraints ... immediate` from earlier tests.
-- * lives_ok and throws_ok bodies that need to surface deferred-trigger errors
--   end with `set constraints all immediate` so the trigger fires inside the
--   savepoint where the exception can be caught.

begin;
set local search_path = extensions, public, pg_temp;

select plan(24);
create temp table _r (line text);
grant insert, select on _r to authenticated, anon;

-- ============================================================================
-- Fixture
-- ============================================================================

insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000001'::uuid, 'alice@test.tab', '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', '{"display_name":"Alice"}'::jsonb),
  ('00000000-0000-0000-0000-000000000002'::uuid, 'bob@test.tab',   '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', '{"display_name":"Bob"}'::jsonb),
  ('00000000-0000-0000-0000-000000000003'::uuid, 'carol@test.tab', '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', '{"display_name":"Carol"}'::jsonb);

insert into public.trips (id, name, created_by)
values ('11111111-1111-1111-1111-111111111111'::uuid, 'Lisbon', '00000000-0000-0000-0000-000000000001'::uuid);

insert into public.trip_members (trip_id, user_id)
values ('11111111-1111-1111-1111-111111111111'::uuid, '00000000-0000-0000-0000-000000000002'::uuid);
-- Carol intentionally NOT a member.

insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by)
values ('aaaaaaaa-0000-0000-0000-000000000001'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        100, 'EUR', 'seed', '2026-05-01',
        '00000000-0000-0000-0000-000000000001'::uuid);
insert into public.expense_payments (expense_id, user_id, amount_paid, payment_mode) values
    ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, 100, 'equal');
insert into public.expense_splits (expense_id, user_id, amount_owed, split_type) values
    ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, 50, 'equal'),
    ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, 50, 'equal');

-- ============================================================================
-- CHECK + PK + parent-must-exist + trip-member triggers
-- ============================================================================

set constraints all deferred;
insert into _r select lives_ok(
  $$insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by)
    values ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 0.01, 'EUR', 'zero-pay', '2026-05-01', '00000000-0000-0000-0000-000000000001');
    insert into public.expense_payments (expense_id, user_id, amount_paid, payment_mode)
    values ('aaaaaaaa-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 0.01, 'equal');
    insert into public.expense_splits (expense_id, user_id, amount_owed, split_type)
    values ('aaaaaaaa-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 0.01, 'equal');
    set constraints all immediate$$,
  'amount_paid boundary value accepted'
);

set constraints all deferred;
insert into _r select throws_ok(
  $$insert into public.expense_payments (expense_id, user_id, amount_paid, payment_mode)
    values ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', -1, 'equal')$$,
  '23514', null, 'amount_paid = -1 rejected'
);

insert into _r select throws_ok(
  $$insert into public.expense_payments (expense_id, user_id, amount_paid, payment_mode)
    values ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 0, 'banana')$$,
  '23514', null, 'payment_mode = banana rejected'
);
insert into _r select throws_ok(
  $$insert into public.expense_payments (expense_id, user_id, amount_paid, payment_mode)
    values ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 0, '')$$,
  '23514', null, 'payment_mode empty rejected'
);

insert into _r select throws_ok(
  $$insert into public.expense_payments (expense_id, user_id, amount_paid, payment_mode)
    values ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 50, 'equal')$$,
  '23505', null, 'duplicate (expense_id, user_id) PK rejected'
);

insert into _r select throws_ok(
  $$insert into public.expense_payments (expense_id, user_id, amount_paid, payment_mode)
    values ('bbbbbbbb-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000001', 10, 'equal')$$,
  '23514', null, 'expense_payments with nonexistent expense_id rejected (parent-must-exist trigger)'
);

insert into _r select throws_ok(
  $$insert into public.expense_payments (expense_id, user_id, amount_paid, payment_mode)
    values ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 0, 'equal')$$,
  '23514', null, 'payer not in trip members rejected'
);

update public.expenses set deleted_at = clock_timestamp()
 where id = 'aaaaaaaa-0000-0000-0000-000000000002'::uuid;

insert into _r select throws_ok(
  $$insert into public.expense_payments (expense_id, user_id, amount_paid, payment_mode)
    values ('aaaaaaaa-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 1, 'equal')$$,
  '23514', null, 'cannot write payment for deleted expense'
);

-- ============================================================================
-- Sum invariant
-- ============================================================================

set constraints all deferred;
insert into _r select throws_ok(
  $$insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by)
    values ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 100, 'EUR', 'mismatch', '2026-05-01', '00000000-0000-0000-0000-000000000001');
    insert into public.expense_payments (expense_id, user_id, amount_paid, payment_mode)
    values ('cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 99, 'exact');
    insert into public.expense_splits (expense_id, user_id, amount_owed, split_type)
    values ('cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 100, 'equal');
    set constraints all immediate$$,
  '23514', null, 'payments sum != amount rejected at constraint-check time'
);

set constraints all deferred;
insert into _r select lives_ok(
  $$insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by)
    values ('cccccccc-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 100, 'EUR', 'multi-pay', '2026-05-01', '00000000-0000-0000-0000-000000000001');
    insert into public.expense_payments (expense_id, user_id, amount_paid, payment_mode) values
      ('cccccccc-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 60, 'exact'),
      ('cccccccc-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 40, 'exact');
    insert into public.expense_splits (expense_id, user_id, amount_owed, split_type) values
      ('cccccccc-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 50, 'equal'),
      ('cccccccc-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 50, 'equal');
    set constraints all immediate$$,
  'multi-payer expense with matched sums accepted'
);

set constraints all deferred;
insert into _r select throws_ok(
  $$insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by)
    values ('cccccccc-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 50, 'EUR', 'no-pay', '2026-05-01', '00000000-0000-0000-0000-000000000001');
    insert into public.expense_splits (expense_id, user_id, amount_owed, split_type)
    values ('cccccccc-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 50, 'equal');
    set constraints all immediate$$,
  '23514', null, 'expense with zero payments rejected'
);

-- ============================================================================
-- Sync fields + cascade
-- ============================================================================

set constraints all deferred;
insert into _r select ok(
  (select write_id is not null and updated_at is not null
   from public.expense_payments
   where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid
     and user_id    = '00000000-0000-0000-0000-000000000001'::uuid),
  'expense_payments insert stamps write_id + updated_at'
);

do $do$
declare v_initial uuid;
declare v_after uuid;
begin
    select write_id into v_initial from public.expense_payments
     where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid
       and user_id    = '00000000-0000-0000-0000-000000000001'::uuid;
    update public.expense_payments set payment_mode = 'exact'
     where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid
       and user_id    = '00000000-0000-0000-0000-000000000001'::uuid;
    select write_id into v_after from public.expense_payments
     where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid
       and user_id    = '00000000-0000-0000-0000-000000000001'::uuid;
    if v_initial = v_after then
        raise exception 'write_id did not change on update';
    end if;
end; $do$;
insert into _r select ok(true, 'write_id changes on update');

delete from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000002'::uuid;
insert into _r select is(
  (select count(*)::int from public.expense_payments where expense_id = 'aaaaaaaa-0000-0000-0000-000000000002'::uuid),
  0,
  'expense hard-delete CASCADEs to expense_payments'
);

-- ============================================================================
-- RLS
-- ============================================================================

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

insert into _r select ok(
  (select count(*)::int from public.expense_payments where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid) > 0,
  'RLS allows trip member to SELECT expense_payments'
);

insert into _r select lives_ok(
  $$insert into public.expense_payments (expense_id, user_id, amount_paid, payment_mode)
    values ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 0, 'equal')$$,
  'RLS allows trip member to INSERT a payment row'
);

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}';

insert into _r select is(
  (select count(*)::int from public.expense_payments where expense_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid),
  0,
  'RLS hides expense_payments from non-member'
);

insert into _r select throws_ok(
  $$insert into public.expense_payments (expense_id, user_id, amount_paid, payment_mode)
    values ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 0, 'equal')$$,
  '42501', null, 'RLS denies non-member INSERT into expense_payments'
);

reset role;
reset request.jwt.claims;

-- ============================================================================
-- RPC
-- ============================================================================

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

set constraints all deferred;
insert into _r select lives_ok(
  $$select public.create_expense_with_payments_and_splits(
        jsonb_build_object(
            'id',           'dddddddd-0000-0000-0000-000000000001',
            'trip_id',      '11111111-1111-1111-1111-111111111111',
            'amount',       100,
            'currency',     'EUR',
            'description',  'rpc happy',
            'expense_date', '2026-05-01'
        ),
        jsonb_build_array(
            jsonb_build_object('user_id', '00000000-0000-0000-0000-000000000001', 'amount_paid', 60, 'payment_mode', 'exact'),
            jsonb_build_object('user_id', '00000000-0000-0000-0000-000000000002', 'amount_paid', 40, 'payment_mode', 'exact')
        ),
        jsonb_build_array(
            jsonb_build_object('user_id', '00000000-0000-0000-0000-000000000001', 'amount_owed', 50, 'split_type', 'equal'),
            jsonb_build_object('user_id', '00000000-0000-0000-0000-000000000002', 'amount_owed', 50, 'split_type', 'equal')
        )
    );
    set constraints all immediate$$,
  'RPC accepts well-formed multi-payer expense'
);

insert into _r select is(
  (select count(*)::int from public.expense_payments where expense_id = 'dddddddd-0000-0000-0000-000000000001'::uuid),
  2,
  'RPC creates two payment rows'
);

insert into _r select is(
  (select count(*)::int from public.expense_splits where expense_id = 'dddddddd-0000-0000-0000-000000000001'::uuid),
  2,
  'RPC creates two split rows'
);

set constraints all deferred;
insert into _r select lives_ok(
  $$select public.create_expense_with_payments_and_splits(
        jsonb_build_object(
            'id',           'dddddddd-0000-0000-0000-000000000001',
            'trip_id',      '11111111-1111-1111-1111-111111111111',
            'amount',       100,
            'currency',     'EUR',
            'description',  'rpc updated',
            'expense_date', '2026-05-02'
        ),
        jsonb_build_array(
            jsonb_build_object('user_id', '00000000-0000-0000-0000-000000000001', 'amount_paid', 100, 'payment_mode', 'equal')
        ),
        jsonb_build_array(
            jsonb_build_object('user_id', '00000000-0000-0000-0000-000000000001', 'amount_owed', 50, 'split_type', 'equal'),
            jsonb_build_object('user_id', '00000000-0000-0000-0000-000000000002', 'amount_owed', 50, 'split_type', 'equal')
        )
    );
    set constraints all immediate$$,
  'RPC accepts re-run replacing payment ledger'
);

insert into _r select is(
  (select count(*)::int from public.expense_payments where expense_id = 'dddddddd-0000-0000-0000-000000000001'::uuid),
  1,
  'RPC replaces payment rows (now 1 instead of 2)'
);

set constraints all deferred;
insert into _r select throws_ok(
  $$select public.create_expense_with_payments_and_splits(
        jsonb_build_object(
            'id',           'dddddddd-0000-0000-0000-000000000002',
            'trip_id',      '11111111-1111-1111-1111-111111111111',
            'amount',       100,
            'currency',     'EUR',
            'description',  'rpc bad sum',
            'expense_date', '2026-05-01'
        ),
        jsonb_build_array(
            jsonb_build_object('user_id', '00000000-0000-0000-0000-000000000001', 'amount_paid', 50, 'payment_mode', 'exact')
        ),
        jsonb_build_array(
            jsonb_build_object('user_id', '00000000-0000-0000-0000-000000000001', 'amount_owed', 100, 'split_type', 'equal')
        )
    );
    set constraints all immediate$$,
  '23514', null, 'RPC rejects mismatched payment sum'
);

reset role;
reset request.jwt.claims;

insert into _r select * from finish();
select line from _r;
rollback;
