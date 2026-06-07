-- 19. Client RPC: non-group containers
-- ============================================================================
-- A non-group expense is backed by a hidden trips row (kind='non_group') shared
-- by the exact set of participants. The container is deduplicated by
-- member_signature (the canonical sort of participants' normalised emails), so
-- the same set of people always resolves to one shared container regardless of
-- who creates the expense, and the signature is stable across sign-in/claim
-- (email never changes when a pending row is claimed).

create or replace function public.resolve_or_create_non_group_container(
  p_participants jsonb
)
returns setof public.trip_people
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_actor     uuid := auth.uid();
  v_email     text := private.current_auth_email();
  v_self_name text;
  v_emails    text[];
  v_signature text;
  v_container uuid;
  v_row       jsonb;
  v_p_email   text;
  v_p_name    text;
  v_user_id   uuid;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if v_email is null or v_email = '' or v_email not like '%@%' then
    raise exception 'A verified email is required to add non-group expenses' using errcode = '22023';
  end if;

  if p_participants is null or jsonb_typeof(p_participants) <> 'array' then
    raise exception 'participants must be a JSON array' using errcode = '22023';
  end if;

  -- Collect the deduped set of normalised emails (caller + the other participants).
  v_emails := array[v_email];
  for v_row in select * from jsonb_array_elements(p_participants) loop
    v_p_email := private.normalized_email(v_row->>'email');
    if v_p_email is null or v_p_email = '' or v_p_email not like '%@%' or char_length(v_p_email) > 320 then
      raise exception 'A valid participant email is required' using errcode = '22023';
    end if;
    if not (v_p_email = any (v_emails)) then
      v_emails := array_append(v_emails, v_p_email);
    end if;
  end loop;

  if array_length(v_emails, 1) < 2 then
    raise exception 'A non-group expense needs at least two people' using errcode = '22023';
  end if;

  -- Canonical participant-set signature: sorted emails joined by '|'.
  select string_agg(e, '|' order by e) into v_signature
  from unnest(v_emails) as e;

  -- Find the existing shared container, or create it.
  select id into v_container
  from public.trips
  where kind = 'non_group' and member_signature = v_signature and deleted_at is null
  limit 1;

  if v_container is null then
    v_container := gen_random_uuid();
    begin
      insert into public.trips (id, name, kind, member_signature, created_by)
      values (v_container, '', 'non_group', v_signature, v_actor);
    exception when unique_violation then
      -- Another transaction created the same participant-set container concurrently.
      select id into v_container
      from public.trips
      where kind = 'non_group' and member_signature = v_signature and deleted_at is null
      limit 1;
    end;
  end if;

  -- Caller's display name (ensure their profile exists).
  insert into public.profiles (id, display_name)
  values (v_actor, left(split_part(v_email, '@', 1), 60))
  on conflict (id) do nothing;

  select left(coalesce(nullif(trim(display_name), ''), split_part(v_email, '@', 1)), 60)
  into v_self_name
  from public.profiles where id = v_actor;

  -- The caller must be a joined member so create_expense_with_payments_and_splits
  -- (which requires is_profile_trip_member) accepts their write.
  insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
  values (gen_random_uuid(), v_container, v_actor, v_email, v_self_name, v_actor, clock_timestamp())
  on conflict on constraint trip_people_email_unique do update
    set user_id   = v_actor,
        joined_at = coalesce(public.trip_people.joined_at, clock_timestamp());

  -- Ensure each other participant: claimed if their email already has an account,
  -- otherwise pending until they sign in (claim_trip_people_for_current_email).
  for v_row in select * from jsonb_array_elements(p_participants) loop
    v_p_email := private.normalized_email(v_row->>'email');
    if v_p_email = v_email then
      continue;
    end if;

    v_user_id := null;
    select u.id into v_user_id
    from auth.users u
    where private.normalized_email(u.email) = v_p_email
    limit 1;

    v_p_name := left(coalesce(nullif(trim(v_row->>'display_name'), ''), split_part(v_p_email, '@', 1)), 60);

    if v_user_id is not null then
      insert into public.profiles (id, display_name)
      values (v_user_id, v_p_name)
      on conflict (id) do nothing;
    end if;

    insert into public.trip_people (id, trip_id, user_id, email, display_name, invited_by, joined_at)
    values (
      gen_random_uuid(), v_container, v_user_id, v_p_email, v_p_name, v_actor,
      case when v_user_id is null then null else clock_timestamp() end
    )
    on conflict on constraint trip_people_email_unique do update
      set user_id   = coalesce(public.trip_people.user_id, excluded.user_id),
          joined_at = case
            when public.trip_people.joined_at is not null then public.trip_people.joined_at
            when excluded.user_id is not null then clock_timestamp()
            else null
          end;
  end loop;

  return query
  select tp.* from public.trip_people tp where tp.trip_id = v_container;
end;
$$;

comment on function public.resolve_or_create_non_group_container(jsonb) is
  'Finds or creates the hidden non-group container for the canonical set of participant emails (caller + p_participants [{email, display_name}]), ensuring a trip_people row for each. Idempotent by member_signature. Returns the container''s trip_people rows; the caller derives container_id from trip_id.';
