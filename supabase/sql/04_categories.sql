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

create or replace function public.validate_category_row()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if new.trip_id is not null
     and not exists (select 1 from public.trips where id = new.trip_id and deleted_at is null) then
    raise exception 'Custom category trip must exist and be active' using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger trg_categories_validate
  before insert or update of trip_id, is_default, deleted_at on public.categories
  for each row execute function public.validate_category_row();

insert into public.categories (id, trip_id, name, icon, is_default) values
  ('00000001-0000-0000-0000-000000000000', null, 'Food & Drink', 'bowl-food',    true),
  ('00000002-0000-0000-0000-000000000000', null, 'Transport',    'car-profile',  true),
  ('00000003-0000-0000-0000-000000000000', null, 'Lodging',      'bed',          true),
  ('00000004-0000-0000-0000-000000000000', null, 'Activities',   'mask-happy',   true),
  ('00000005-0000-0000-0000-000000000000', null, 'Shopping',     'shopping-bag', true),
  ('00000006-0000-0000-0000-000000000000', null, 'Other',        'tag',          true);


-- ============================================================================
