-- ============================================================================
-- roam — Supabase schema
-- ============================================================================
-- One-shot setup for a fresh Postgres 17 / Supabase database. Apply via
-- `mcp__supabase__apply_migration` (single migration named e.g. `schema`).
-- For post-launch changes, switch to versioned per-change migrations.
--
-- Sections:
--   1. Extensions + shared trigger functions
--   2. private schema + is_trip_member helper
--   3. profiles
--   4. trips + trip_members + auto-add-creator trigger
--   5. categories (built-in defaults + per-trip custom)
--   6. expenses + expense_splits + last_activity trigger
--   7. settlements
--   8. activity_log (append-only)
--   9. push_devices + trip_mute_prefs
--  10. RLS policies
--  11. Function privilege locking
-- ============================================================================


-- ============================================================================
-- 1. Extensions + shared trigger functions
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pgtap     with schema extensions;

-- Stamps server-owned sync fields. Clients cannot forge them — LWW ordering
-- is determined by server-receive time.
create or replace function public.set_sync_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := clock_timestamp();
  end if;
  new.updated_at := clock_timestamp();
  new.write_id   := gen_random_uuid();
  return new;
end;
$$;

comment on function public.set_sync_fields() is
  'BEFORE INSERT/UPDATE trigger. Stamps created_at on insert; updated_at + write_id always. Uses clock_timestamp() so consecutive statements within one transaction get ordered timestamps.';


-- ============================================================================
-- 2. private schema + is_trip_member helper
-- ============================================================================
-- The `private` schema holds RLS helper functions. Postgres RLS can call
-- across schemas, but PostgREST does NOT expose /rest/v1/rpc for anything
-- outside the configured exposed schemas (default: public) — so functions
-- here are invisible as RPC endpoints while remaining usable from RLS.

create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.is_trip_member(p_trip_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public, private
as $$
  select exists (
    select 1 from public.trip_members
    where trip_id = p_trip_id and user_id = auth.uid()
  );
$$;

comment on function private.is_trip_member(uuid) is
  'True if auth.uid() is a member of the given trip. Used by every RLS policy that scopes to trip access. SECURITY DEFINER to bypass RLS on trip_members (avoids self-recursion).';


-- ============================================================================
-- 3. profiles
-- ============================================================================

create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (
    char_length(trim(display_name)) > 0 and char_length(display_name) <= 60
  ),
  avatar_url   text check (avatar_url is null or char_length(avatar_url) <= 2048),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  write_id     uuid not null default gen_random_uuid()
);

comment on table public.profiles is
  'Per-user public profile data. One row per auth.users row, created automatically on signup.';

create trigger trg_profiles_sync_fields
  before insert or update on public.profiles
  for each row execute function public.set_sync_fields();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      split_part(coalesce(new.email, 'user'), '@', 1)
    )
  );
  return new;
end;
$$;

create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ============================================================================
-- 4. trips + trip_members + auto-add-creator trigger
-- ============================================================================

create table public.trips (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (
    char_length(trim(name)) > 0 and char_length(name) <= 100
  ),
  created_by       uuid not null references public.profiles(id) on delete restrict,
  last_activity_at timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  write_id         uuid not null default gen_random_uuid()
);

comment on table public.trips is
  'Top-level expense container. last_activity_at bumped by triggers on expense/settlement writes.';

create index trips_created_by_idx on public.trips(created_by);
create index trips_active_idx     on public.trips(last_activity_at desc) where deleted_at is null;

create trigger trg_trips_sync_fields
  before insert or update on public.trips
  for each row execute function public.set_sync_fields();

create table public.trip_members (
  trip_id    uuid not null references public.trips(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete restrict,
  joined_at  timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  write_id   uuid not null default gen_random_uuid(),
  primary key (trip_id, user_id)
);

comment on table public.trip_members is 'Membership join. Hard-delete = leave trip (no soft delete).';

create index trip_members_user_id_idx on public.trip_members(user_id);

create trigger trg_trip_members_sync_fields
  before insert or update on public.trip_members
  for each row execute function public.set_sync_fields();

-- Creator auto-joins the trip they create.
create or replace function public.auto_add_creator_as_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.trip_members (trip_id, user_id)
  values (new.id, new.created_by)
  on conflict (trip_id, user_id) do nothing;
  return new;
end;
$$;

create trigger trg_trips_add_creator
  after insert on public.trips
  for each row execute function public.auto_add_creator_as_member();


-- ============================================================================
-- 5. categories
-- ============================================================================

create table public.categories (
  id         uuid primary key default gen_random_uuid(),
  trip_id    uuid references public.trips(id) on delete cascade,  -- null for built-ins
  name       text not null check (char_length(trim(name)) > 0 and char_length(name) <= 50),
  icon       text not null check (char_length(icon) <= 16),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  write_id   uuid not null default gen_random_uuid(),
  constraint categories_default_xor_trip check (
    (is_default and trip_id is null) or (not is_default and trip_id is not null)
  )
);

comment on table public.categories is
  'Built-in categories (is_default=true, trip_id null) seeded by migration. Custom categories are trip-scoped.';

create unique index categories_default_name_uniq on public.categories(name) where is_default;
create unique index categories_trip_name_uniq    on public.categories(trip_id, lower(name)) where trip_id is not null and deleted_at is null;
create index        categories_trip_id_idx       on public.categories(trip_id) where trip_id is not null;

create trigger trg_categories_sync_fields
  before insert or update on public.categories
  for each row execute function public.set_sync_fields();

insert into public.categories (id, trip_id, name, icon, is_default) values
  (gen_random_uuid(), null, 'Food & Drink', '🍽', true),
  (gen_random_uuid(), null, 'Transport',    '🚗', true),
  (gen_random_uuid(), null, 'Lodging',      '🏨', true),
  (gen_random_uuid(), null, 'Activities',   '🎭', true),
  (gen_random_uuid(), null, 'Shopping',     '🛍', true),
  (gen_random_uuid(), null, 'Other',        '⋯', true);


-- ============================================================================
-- 6. expenses + expense_splits + touch_trip_last_activity trigger
-- ============================================================================

create table public.expenses (
  id                   uuid primary key default gen_random_uuid(),
  trip_id              uuid not null references public.trips(id) on delete restrict,
  payer_id             uuid not null references public.profiles(id) on delete restrict,
  amount               numeric(14, 2) not null check (amount > 0),
  currency             text not null check (char_length(currency) = 3 and currency = upper(currency)),
  category_id          uuid references public.categories(id) on delete set null,
  description          text not null check (char_length(trim(description)) > 0 and char_length(description) <= 200),
  expense_date         date not null,
  receipt_storage_path text check (receipt_storage_path is null or char_length(receipt_storage_path) <= 512),
  created_by           uuid not null references public.profiles(id) on delete restrict,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  write_id             uuid not null default gen_random_uuid()
);

comment on table public.expenses is
  'Group expenses. Soft-delete via deleted_at. Hard-delete blocked by FK from trips (RESTRICT).';

create index expenses_trip_id_idx     on public.expenses(trip_id);
create index expenses_trip_active_idx on public.expenses(trip_id, expense_date desc) where deleted_at is null;
create index expenses_payer_id_idx    on public.expenses(payer_id);
create index expenses_category_id_idx on public.expenses(category_id) where category_id is not null;
create index expenses_created_by_idx  on public.expenses(created_by);

create trigger trg_expenses_sync_fields
  before insert or update on public.expenses
  for each row execute function public.set_sync_fields();

create or replace function public.touch_trip_last_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_trip_id uuid;
begin
  v_trip_id := coalesce(new.trip_id, old.trip_id);
  if v_trip_id is not null then
    update public.trips set last_activity_at = clock_timestamp() where id = v_trip_id;
  end if;
  return coalesce(new, old);
end;
$$;

comment on function public.touch_trip_last_activity() is
  'Updates trips.last_activity_at when an expense or settlement is written. Used by TripStateDeriver.';

create trigger trg_expenses_touch_trip
  after insert or update or delete on public.expenses
  for each row execute function public.touch_trip_last_activity();

create table public.expense_splits (
  expense_id  uuid not null references public.expenses(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete restrict,
  amount_owed numeric(14, 2) not null check (amount_owed >= 0),
  split_type  text not null check (split_type in ('equal', 'exact', 'percentage', 'shares', 'adjustment')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  write_id    uuid not null default gen_random_uuid(),
  primary key (expense_id, user_id)
);

comment on table public.expense_splits is
  'Per-participant share of an expense. Cascade-deletes if the parent expense is hard-deleted.';

create index expense_splits_user_id_idx on public.expense_splits(user_id);

create trigger trg_expense_splits_sync_fields
  before insert or update on public.expense_splits
  for each row execute function public.set_sync_fields();


-- ============================================================================
-- 7. settlements
-- ============================================================================

create table public.settlements (
  id         uuid primary key default gen_random_uuid(),
  trip_id    uuid not null references public.trips(id) on delete restrict,
  from_user  uuid not null references public.profiles(id) on delete restrict,
  to_user    uuid not null references public.profiles(id) on delete restrict,
  amount     numeric(14, 2) not null check (amount > 0),
  currency   text not null check (char_length(currency) = 3 and currency = upper(currency)),
  note       text check (note is null or char_length(note) <= 200),
  settled_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  write_id   uuid not null default gen_random_uuid(),
  constraint settlements_distinct_parties check (from_user <> to_user)
);

comment on table public.settlements is
  'Pairwise payments outside the app. Subtracted from balances by BalanceEngine.';

create index settlements_trip_id_idx     on public.settlements(trip_id);
create index settlements_trip_active_idx on public.settlements(trip_id, settled_at desc) where deleted_at is null;
create index settlements_from_user_idx   on public.settlements(from_user);
create index settlements_to_user_idx     on public.settlements(to_user);
create index settlements_created_by_idx  on public.settlements(created_by);

create trigger trg_settlements_sync_fields
  before insert or update on public.settlements
  for each row execute function public.set_sync_fields();

create trigger trg_settlements_touch_trip
  after insert or update or delete on public.settlements
  for each row execute function public.touch_trip_last_activity();


-- ============================================================================
-- 8. activity_log (append-only)
-- ============================================================================

create table public.activity_log (
  id            uuid primary key default gen_random_uuid(),
  trip_id       uuid not null references public.trips(id) on delete cascade,
  actor_id      uuid not null references public.profiles(id) on delete restrict,
  action        text not null check (action in (
    'expense_created', 'expense_updated', 'expense_deleted',
    'settlement_created', 'settlement_updated', 'settlement_deleted',
    'member_joined', 'member_left',
    'trip_created', 'trip_updated'
  )),
  entity_type   text not null check (entity_type in ('expense', 'settlement', 'trip', 'member')),
  entity_id     uuid not null,
  timestamp     timestamptz not null default now(),
  snapshot_json jsonb
);

comment on table public.activity_log is
  'Append-only audit trail. No UPDATE/DELETE allowed via RLS.';

create index activity_log_trip_id_timestamp_idx on public.activity_log(trip_id, timestamp desc);
create index activity_log_actor_id_idx          on public.activity_log(actor_id);
create index activity_log_entity_idx            on public.activity_log(entity_type, entity_id);


-- ============================================================================
-- 9. push_devices + trip_mute_prefs
-- ============================================================================

create table public.push_devices (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  apns_token   text not null check (char_length(apns_token) > 0 and char_length(apns_token) <= 1024),
  device_name  text check (device_name is null or char_length(device_name) <= 100),
  last_seen_at timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  write_id     uuid not null default gen_random_uuid(),
  constraint push_devices_user_token_uniq unique (user_id, apns_token)
);

comment on table public.push_devices is 'APNs device tokens per user. One row per (user, device).';

create index push_devices_user_id_idx on public.push_devices(user_id);

create trigger trg_push_devices_sync_fields
  before insert or update on public.push_devices
  for each row execute function public.set_sync_fields();

create table public.trip_mute_prefs (
  trip_id    uuid not null references public.trips(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  muted_at   timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  write_id   uuid not null default gen_random_uuid(),
  primary key (trip_id, user_id)
);

comment on table public.trip_mute_prefs is 'Per-user, per-trip mute. Row presence = muted; absence = unmuted.';

create index trip_mute_prefs_user_id_idx on public.trip_mute_prefs(user_id);

create trigger trg_trip_mute_prefs_sync_fields
  before insert or update on public.trip_mute_prefs
  for each row execute function public.set_sync_fields();


-- ============================================================================
-- 10. RLS policies
-- ============================================================================
-- All references to auth.uid() are wrapped in (select auth.uid()) so the auth
-- lookup is evaluated once per query, not once per row. Same semantics, much
-- faster at scale.

alter table public.profiles        enable row level security;
alter table public.trips           enable row level security;
alter table public.trip_members    enable row level security;
alter table public.categories      enable row level security;
alter table public.expenses        enable row level security;
alter table public.expense_splits  enable row level security;
alter table public.settlements     enable row level security;
alter table public.activity_log    enable row level security;
alter table public.push_devices    enable row level security;
alter table public.trip_mute_prefs enable row level security;

-- profiles: any authenticated user can read; write only your own.
create policy profiles_select_authenticated on public.profiles
  for select to authenticated using (true);
create policy profiles_insert_self on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy profiles_delete_self on public.profiles
  for delete to authenticated using (id = (select auth.uid()));

-- trips: only members can read/update/delete; you can create trips for yourself.
create policy trips_select_member on public.trips
  for select to authenticated using (private.is_trip_member(id));
create policy trips_insert_self_created on public.trips
  for insert to authenticated with check (created_by = (select auth.uid()));
create policy trips_update_member on public.trips
  for update to authenticated
  using (private.is_trip_member(id)) with check (private.is_trip_member(id));
create policy trips_delete_member on public.trips
  for delete to authenticated using (private.is_trip_member(id));

-- trip_members: only members can read; only yourself can join/leave.
-- Creator auto-add via SECURITY DEFINER trigger; invite join via Edge Function (service role).
create policy trip_members_select_member on public.trip_members
  for select to authenticated using (private.is_trip_member(trip_id));
create policy trip_members_insert_self on public.trip_members
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy trip_members_delete_self on public.trip_members
  for delete to authenticated using (user_id = (select auth.uid()));

-- categories: defaults are globally readable; trip-scoped readable+writable by members.
create policy categories_select_default_or_member on public.categories
  for select to authenticated
  using (is_default or (trip_id is not null and private.is_trip_member(trip_id)));
create policy categories_insert_member_custom on public.categories
  for insert to authenticated
  with check (not is_default and trip_id is not null and private.is_trip_member(trip_id));
create policy categories_update_member_custom on public.categories
  for update to authenticated
  using  (not is_default and trip_id is not null and private.is_trip_member(trip_id))
  with check (not is_default and trip_id is not null and private.is_trip_member(trip_id));
create policy categories_delete_member_custom on public.categories
  for delete to authenticated
  using (not is_default and trip_id is not null and private.is_trip_member(trip_id));

-- expenses
create policy expenses_select_member on public.expenses
  for select to authenticated using (private.is_trip_member(trip_id));
create policy expenses_insert_member on public.expenses
  for insert to authenticated
  with check (private.is_trip_member(trip_id) and created_by = (select auth.uid()));
create policy expenses_update_member on public.expenses
  for update to authenticated
  using (private.is_trip_member(trip_id)) with check (private.is_trip_member(trip_id));
create policy expenses_delete_member on public.expenses
  for delete to authenticated using (private.is_trip_member(trip_id));

-- expense_splits: visibility follows parent expense's trip membership.
create policy expense_splits_select_member on public.expense_splits
  for select to authenticated
  using (exists (select 1 from public.expenses e where e.id = expense_splits.expense_id and private.is_trip_member(e.trip_id)));
create policy expense_splits_insert_member on public.expense_splits
  for insert to authenticated
  with check (exists (select 1 from public.expenses e where e.id = expense_splits.expense_id and private.is_trip_member(e.trip_id)));
create policy expense_splits_update_member on public.expense_splits
  for update to authenticated
  using  (exists (select 1 from public.expenses e where e.id = expense_splits.expense_id and private.is_trip_member(e.trip_id)))
  with check (exists (select 1 from public.expenses e where e.id = expense_splits.expense_id and private.is_trip_member(e.trip_id)));
create policy expense_splits_delete_member on public.expense_splits
  for delete to authenticated
  using (exists (select 1 from public.expenses e where e.id = expense_splits.expense_id and private.is_trip_member(e.trip_id)));

-- settlements
create policy settlements_select_member on public.settlements
  for select to authenticated using (private.is_trip_member(trip_id));
create policy settlements_insert_member on public.settlements
  for insert to authenticated
  with check (private.is_trip_member(trip_id) and created_by = (select auth.uid()));
create policy settlements_update_member on public.settlements
  for update to authenticated
  using (private.is_trip_member(trip_id)) with check (private.is_trip_member(trip_id));
create policy settlements_delete_member on public.settlements
  for delete to authenticated using (private.is_trip_member(trip_id));

-- activity_log: append-only — only SELECT and INSERT.
create policy activity_log_select_member on public.activity_log
  for select to authenticated using (private.is_trip_member(trip_id));
create policy activity_log_insert_member on public.activity_log
  for insert to authenticated
  with check (private.is_trip_member(trip_id) and actor_id = (select auth.uid()));

-- push_devices: self-only.
create policy push_devices_select_self on public.push_devices
  for select to authenticated using (user_id = (select auth.uid()));
create policy push_devices_insert_self on public.push_devices
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy push_devices_update_self on public.push_devices
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy push_devices_delete_self on public.push_devices
  for delete to authenticated using (user_id = (select auth.uid()));

-- trip_mute_prefs: self-only; insert also requires membership.
create policy trip_mute_prefs_select_self on public.trip_mute_prefs
  for select to authenticated using (user_id = (select auth.uid()));
create policy trip_mute_prefs_insert_self on public.trip_mute_prefs
  for insert to authenticated
  with check (user_id = (select auth.uid()) and private.is_trip_member(trip_id));
create policy trip_mute_prefs_delete_self on public.trip_mute_prefs
  for delete to authenticated using (user_id = (select auth.uid()));


-- ============================================================================
-- 11. Function privilege locking
-- ============================================================================
-- Trigger functions exist only to be invoked by their triggers — they should
-- never be callable via /rest/v1/rpc. Revoke EXECUTE from public/anon/auth.
revoke execute on function public.auto_add_creator_as_member() from public, anon, authenticated;
revoke execute on function public.handle_new_user()            from public, anon, authenticated;
revoke execute on function public.touch_trip_last_activity()   from public, anon, authenticated;
revoke execute on function public.set_sync_fields()            from public, anon, authenticated;
-- is_trip_member lives in `private` schema (not PostgREST-exposed) — already locked.
revoke execute on function private.is_trip_member(uuid) from public, anon;
grant  execute on function private.is_trip_member(uuid) to   authenticated;
