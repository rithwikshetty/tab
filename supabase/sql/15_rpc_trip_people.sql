-- ============================================================================
-- Client RPCs: trip people
-- ============================================================================

create or replace function public.add_trip_person_by_email(
  p_trip_id uuid,
  p_email text,
  p_display_name text default null,
  p_person_id uuid default null
)
returns public.trip_people
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_actor uuid := auth.uid();
  v_email text := private.normalized_email(p_email);
  v_display_name text := nullif(trim(p_display_name), '');
  v_user_id uuid;
  v_person public.trip_people;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if v_email is null or v_email = '' or v_email not like '%@%' or char_length(v_email) > 320 then
    raise exception 'A valid email is required' using errcode = '22023';
  end if;

  if not exists (select 1 from public.trips t where t.id = p_trip_id and t.deleted_at is null) then
    raise exception 'Trip not found or deleted' using errcode = 'P0002';
  end if;

  if not private.is_profile_trip_member(p_trip_id, v_actor) then
    raise exception 'Only trip members can add people' using errcode = '42501';
  end if;

  select u.id, coalesce(p.display_name, split_part(v_email, '@', 1))
  into v_user_id, v_display_name
  from auth.users u
  left join public.profiles p on p.id = u.id
  where private.normalized_email(u.email) = v_email
  limit 1;

  v_display_name := left(coalesce(nullif(trim(p_display_name), ''), nullif(trim(v_display_name), ''), split_part(v_email, '@', 1)), 60);

  if v_user_id is not null then
    insert into public.profiles (id, display_name)
    values (v_user_id, v_display_name)
    on conflict (id) do nothing;
  end if;

  if v_user_id is not null then
    select tp.* into v_person
    from public.trip_people tp
    where tp.trip_id = p_trip_id
      and tp.user_id = v_user_id;

    if found then
      update public.trip_people
      set email = v_email,
          display_name = v_display_name,
          joined_at = coalesce(public.trip_people.joined_at, clock_timestamp())
      where public.trip_people.id = v_person.id
      returning public.trip_people.* into v_person;

      return v_person;
    end if;
  end if;

  insert into public.trip_people (
    id, trip_id, user_id, email, display_name, invited_by, joined_at
  )
  values (
    coalesce(p_person_id, gen_random_uuid()),
    p_trip_id,
    v_user_id,
    v_email,
    v_display_name,
    v_actor,
    case when v_user_id is null then null else clock_timestamp() end
  )
  on conflict on constraint trip_people_email_unique do update
    set user_id = coalesce(public.trip_people.user_id, excluded.user_id),
        display_name = excluded.display_name,
        joined_at = case
          when public.trip_people.joined_at is not null then public.trip_people.joined_at
          when excluded.user_id is not null then clock_timestamp()
          else null
        end
  returning public.trip_people.* into v_person;

  return v_person;
end;
$$;

comment on function public.add_trip_person_by_email(uuid, text, text, uuid) is
  'Adds a pending trip person by email, or immediately links the person if an auth account with that email already exists.';

create or replace function public.claim_trip_people_for_current_email()
returns setof public.trip_people
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_actor uuid := auth.uid();
  v_email text := private.current_auth_email();
  v_display_name text;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if v_email is null or v_email = '' then
    return;
  end if;

  select display_name into v_display_name
  from public.profiles
  where id = v_actor;

  insert into public.profiles (id, display_name)
  values (v_actor, left(coalesce(nullif(trim(v_display_name), ''), split_part(v_email, '@', 1)), 60))
  on conflict (id) do nothing;

  return query
  update public.trip_people tp
  set user_id = v_actor,
      display_name = left(coalesce(nullif(trim(v_display_name), ''), tp.display_name), 60),
      joined_at = clock_timestamp()
  where tp.email = v_email
    and tp.user_id is null
    and not exists (
      select 1
      from public.trip_people existing
      where existing.trip_id = tp.trip_id
        and existing.user_id = v_actor
    )
  returning tp.*;
end;
$$;

comment on function public.claim_trip_people_for_current_email() is
  'Links pending trip_people rows for auth.uid() email. Called after sign-in before sync pull.';

create or replace function public.suggest_trip_people(
  p_query text default null,
  p_limit int default 8
)
returns table (
  user_id uuid,
  email text,
  display_name text
)
language plpgsql
security definer
stable
set search_path = public, private
as $$
declare
  v_actor uuid := auth.uid();
  v_query text := nullif(trim(p_query), '');
  v_limit int := least(greatest(coalesce(p_limit, 8), 1), 25);
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  return query
  select distinct on (tp.email)
    tp.user_id,
    tp.email,
    tp.display_name
  from public.trip_people tp
  where coalesce(tp.user_id, '00000000-0000-0000-0000-000000000000'::uuid) <> v_actor
    and exists (
      select 1
      from public.trip_people mine
      where mine.trip_id = tp.trip_id
        and mine.user_id = v_actor
        and mine.joined_at is not null
    )
    and (
      v_query is null
      or tp.email ilike '%' || v_query || '%'
      or tp.display_name ilike '%' || v_query || '%'
    )
  order by tp.email, tp.updated_at desc
  limit v_limit;
end;
$$;

comment on function public.suggest_trip_people(text, int) is
  'Suggests people the current user has already shared a trip with. No global user search.';
