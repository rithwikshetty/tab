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
    left(coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'given_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
      split_part(coalesce(new.email, 'user'), '@', 1)
    )::text, 60)
  );
  return new;
end;
$$;

create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.ensure_current_profile(
  p_display_name text default null,
  p_avatar_url text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_display_name text := nullif(trim(p_display_name), '');
  v_profile public.profiles;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if v_display_name is null then
    select coalesce(
      nullif(trim(raw_user_meta_data ->> 'display_name'), ''),
      nullif(trim(raw_user_meta_data ->> 'given_name'), ''),
      nullif(trim(raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(raw_user_meta_data ->> 'name'), ''),
      split_part(coalesce(email, 'user'), '@', 1)
    )
    into v_display_name
    from auth.users
    where id = v_actor;
  end if;

  v_display_name := left(coalesce(nullif(trim(v_display_name), ''), 'user'), 60);

  insert into public.profiles (id, display_name, avatar_url)
  values (v_actor, v_display_name, p_avatar_url)
  on conflict (id) do update
    set display_name = excluded.display_name,
        avatar_url = coalesce(excluded.avatar_url, public.profiles.avatar_url)
  returning * into v_profile;

  return v_profile;
end;
$$;


-- ============================================================================
