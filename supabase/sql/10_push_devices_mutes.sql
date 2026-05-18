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

create or replace function public.validate_trip_mute_pref_row()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not private.is_profile_trip_member(new.trip_id, new.user_id) then
    raise exception 'Trip mute preference user must be a trip member' using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger trg_trip_mute_prefs_validate
  before insert or update of trip_id, user_id on public.trip_mute_prefs
  for each row execute function public.validate_trip_mute_pref_row();
