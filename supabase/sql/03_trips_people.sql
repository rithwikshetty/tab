-- 4. trips + trip_people + email-based membership RPCs
-- ============================================================================

create table public.trips (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  kind             text not null default 'trip' check (kind in ('trip', 'non_group')),
  member_signature text,
  created_by       uuid not null references public.profiles(id) on delete restrict,
  last_activity_at timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  write_id         uuid not null default gen_random_uuid(),
  -- A user-facing trip needs a name; a hidden non-group container does not.
  constraint trips_name_valid check (
    kind = 'non_group'
    or (char_length(trim(name)) > 0 and char_length(name) <= 100)
  ),
  -- A non-group container is identified by its participant-set signature; trips have none.
  constraint trips_signature_matches_kind check (
    (kind = 'non_group') = (member_signature is not null)
  )
);

comment on table public.trips is
  'Top-level expense container. last_activity_at bumped by triggers on expense/settlement writes. kind=''non_group'' rows are hidden shadow groups backing non-group expenses, deduplicated per participant set via member_signature.';

create index trips_created_by_idx on public.trips(created_by);
create index trips_active_idx     on public.trips(last_activity_at desc) where deleted_at is null and kind = 'trip';
-- One shadow group per participant set, globally (so {A,B} is shared regardless of creator).
create unique index trips_non_group_signature_uniq on public.trips(member_signature)
  where kind = 'non_group' and deleted_at is null;

create trigger trg_trips_sync_fields
  before insert or update on public.trips
  for each row execute function public.set_sync_fields();

-- kind is immutable: a trip can never become a non-group container or vice versa.
create or replace function public.guard_trip_kind()
returns trigger
language plpgsql
as $$
begin
  if new.kind is distinct from old.kind then
    raise exception 'trips.kind is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger trg_trips_guard_kind
  before update on public.trips
  for each row execute function public.guard_trip_kind();

create table public.trip_people (
  id           uuid primary key default gen_random_uuid(),
  trip_id      uuid not null references public.trips(id) on delete cascade,
  user_id      uuid references public.profiles(id) on delete restrict,
  email        text not null check (
    email = lower(trim(email))
    and email like '%@%'
    and char_length(email) <= 320
  ),
  display_name text not null check (
    char_length(trim(display_name)) > 0 and char_length(display_name) <= 60
  ),
  invited_by   uuid references public.profiles(id) on delete set null,
  joined_at    timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  write_id     uuid not null default gen_random_uuid(),
  constraint trip_people_join_state check (
    (user_id is null and joined_at is null)
    or (user_id is not null and joined_at is not null)
  ),
  constraint trip_people_email_unique unique (trip_id, email)
);

comment on table public.trip_people is
  'Trip-scoped ledger identities. A person can be pending by email, then claimed by a real auth profile when that email signs in.';

create unique index trip_people_trip_user_uniq on public.trip_people(trip_id, user_id)
  where user_id is not null;
create index trip_people_trip_id_idx on public.trip_people(trip_id);
create index trip_people_user_id_idx on public.trip_people(user_id) where user_id is not null;
create index trip_people_invited_by_idx on public.trip_people(invited_by) where invited_by is not null;

create trigger trg_trip_people_sync_fields
  before insert or update on public.trip_people
  for each row execute function public.set_sync_fields();


-- ============================================================================
