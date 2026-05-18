-- 03_triggers.sql — trigger side-effects.

begin;
set local search_path = extensions, public, pg_temp;

select plan(14);
create temp table _r (line text);

-- ===== Fixture =====
insert into auth.users (id, email, instance_id, aud, role, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000001'::uuid, 'alice@test.tab',
   '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
   '{"display_name":"Alice"}'::jsonb),
  ('00000000-0000-0000-0000-000000000002'::uuid, 'bob@test.tab',
   '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
   '{}'::jsonb),
  ('00000000-0000-0000-0000-000000000003'::uuid, null,
   '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
   '{}'::jsonb),
  ('00000000-0000-0000-0000-000000000004'::uuid, 'rithwik@test.tab',
   '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
   '{"name":"Rithwik Shetty"}'::jsonb);

-- handle_new_user: profile created with name from metadata
insert into _r select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-000000000001'::uuid),
  'Alice',
  'handle_new_user: display_name comes from raw_user_meta_data.display_name'
);

-- handle_new_user: falls back to email-local-part when metadata is empty
insert into _r select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-000000000002'::uuid),
  'bob',
  'handle_new_user: falls back to email local-part (split_part) when metadata empty'
);

-- handle_new_user: final fallback to 'user' when no email and no metadata
insert into _r select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-000000000003'::uuid),
  'user',
  'handle_new_user: final fallback to literal "user" when email and metadata absent'
);

insert into _r select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-000000000004'::uuid),
  'Rithwik Shetty',
  'handle_new_user: display_name falls back to raw_user_meta_data.name'
);

-- auto_add_creator_as_member
insert into public.trips (id, name, created_by)
values ('11111111-1111-1111-1111-111111111111'::uuid, 'Lisbon', '00000000-0000-0000-0000-000000000001'::uuid);

insert into _r select ok(
  exists (
    select 1 from public.trip_members
    where trip_id = '11111111-1111-1111-1111-111111111111'::uuid
      and user_id = '00000000-0000-0000-0000-000000000001'::uuid
  ),
  'auto_add_creator_as_member: creator becomes a member after trip insert'
);

insert into public.trip_members (trip_id, user_id)
values ('11111111-1111-1111-1111-111111111111'::uuid, '00000000-0000-0000-0000-000000000002'::uuid);

-- ===== set_sync_fields on INSERT =====
insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by)
values ('aaaaaaaa-0000-0000-0000-000000000001'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        10, 'EUR', 'first', '2026-05-01',
        '00000000-0000-0000-0000-000000000001'::uuid);

insert into _r select isnt(
  (select created_at::text from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid),
  null::text,
  'set_sync_fields INSERT: created_at populated'
);

insert into _r select isnt(
  (select write_id::text from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid),
  null::text,
  'set_sync_fields INSERT: write_id populated'
);

-- Capture pre-update values
create temp table _snap (created_before timestamptz, updated_before timestamptz, write_before uuid);
insert into _snap
select created_at, updated_at, write_id from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;

-- Wait long enough for now() to advance (statement_timestamp() granularity)
select pg_sleep(0.05);

update public.expenses set description = 'edited' where id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;

-- set_sync_fields on UPDATE: updated_at bumped
insert into _r select ok(
  (select updated_at from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid)
   > (select updated_before from _snap),
  'set_sync_fields UPDATE: updated_at advances after UPDATE'
);

-- set_sync_fields on UPDATE: write_id regenerated
insert into _r select ok(
  (select write_id from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid)
   <> (select write_before from _snap),
  'set_sync_fields UPDATE: write_id regenerated on UPDATE'
);

-- set_sync_fields on UPDATE: created_at preserved
insert into _r select is(
  (select created_at from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid),
  (select created_before from _snap),
  'set_sync_fields UPDATE: created_at unchanged'
);

-- ===== touch_trip_last_activity on expense events =====
create temp table _trip_snap (last_before timestamptz);
insert into _trip_snap
select last_activity_at from public.trips where id = '11111111-1111-1111-1111-111111111111'::uuid;

select pg_sleep(0.05);

insert into public.expenses (id, trip_id, amount, currency, description, expense_date, created_by)
values ('aaaaaaaa-0000-0000-0000-000000000002'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        20, 'EUR', 'second', '2026-05-02',
        '00000000-0000-0000-0000-000000000001'::uuid);

insert into _r select ok(
  (select last_activity_at from public.trips where id = '11111111-1111-1111-1111-111111111111'::uuid)
   > (select last_before from _trip_snap),
  'touch_trip_last_activity: trips.last_activity_at advances after expense INSERT'
);

-- DELETE also bumps last_activity_at (covered by AFTER ... DELETE clause)
update _trip_snap set last_before = (select last_activity_at from public.trips where id = '11111111-1111-1111-1111-111111111111'::uuid);
select pg_sleep(0.05);
delete from public.expenses where id = 'aaaaaaaa-0000-0000-0000-000000000002'::uuid;

insert into _r select ok(
  (select last_activity_at from public.trips where id = '11111111-1111-1111-1111-111111111111'::uuid)
   > (select last_before from _trip_snap),
  'touch_trip_last_activity: trips.last_activity_at advances after expense DELETE'
);

-- ===== touch_trip_last_activity on settlement INSERT =====
update _trip_snap set last_before = (select last_activity_at from public.trips where id = '11111111-1111-1111-1111-111111111111'::uuid);
select pg_sleep(0.05);

insert into public.settlements (trip_id, from_user, to_user, amount, currency, created_by)
values ('11111111-1111-1111-1111-111111111111'::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000001'::uuid,
        15, 'EUR',
        '00000000-0000-0000-0000-000000000001'::uuid);

insert into _r select ok(
  (select last_activity_at from public.trips where id = '11111111-1111-1111-1111-111111111111'::uuid)
   > (select last_before from _trip_snap),
  'touch_trip_last_activity: trips.last_activity_at advances after settlement INSERT'
);

-- handle_new_user is idempotent-by-PK (id is PK referencing auth.users)
-- Re-inserting the same auth.users id would fail the PK; tested implicitly by Alice's profile existing.
insert into _r select is(
  (select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-000000000001'::uuid),
  1,
  'handle_new_user: exactly one profile per auth user'
);

insert into _r select * from finish();
select line from _r;
rollback;
