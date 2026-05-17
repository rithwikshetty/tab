-- Harden the greenfield foundation contract:
-- - invite-only joining via tokenized RPCs
-- - DB-enforced trip/member/category invariants
-- - DB-enforced active expense split totals
-- - private receipt storage bucket policies

create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.is_profile_trip_member(p_trip_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public, private
as $$
  select exists (
    select 1 from public.trip_members
    where trip_id = p_trip_id and user_id = p_user_id
  );
$$;

create or replace function private.is_trip_member(p_trip_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public, private
as $$
  select private.is_profile_trip_member(p_trip_id, auth.uid());
$$;

create or replace function private.receipt_object_trip_id(p_name text)
returns uuid
language plpgsql
security definer
immutable
set search_path = public, private
as $$
declare
  first_token text;
  second_token text;
  candidate text;
begin
  first_token := split_part(p_name, '/', 1);
  second_token := split_part(p_name, '/', 2);
  candidate := case when first_token = 'receipts' then second_token else first_token end;

  if candidate ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return candidate::uuid;
  end if;

  return null;
end;
$$;

create table if not exists private.trip_invites (
  id         uuid primary key default gen_random_uuid(),
  trip_id    uuid not null references public.trips(id) on delete cascade,
  token_hash bytea not null unique,
  created_by uuid not null references public.profiles(id) on delete restrict,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  used_at    timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  write_id   uuid not null default gen_random_uuid(),
  constraint trip_invites_expiry_future check (expires_at > created_at)
);

create index if not exists trip_invites_trip_id_idx on private.trip_invites(trip_id);
create index if not exists trip_invites_active_idx on private.trip_invites(trip_id, expires_at)
  where revoked_at is null and deleted_at is null;

drop trigger if exists trg_trip_invites_sync_fields on private.trip_invites;
create trigger trg_trip_invites_sync_fields
  before insert or update on private.trip_invites
  for each row execute function public.set_sync_fields();

create or replace function public.create_trip_invite(
  p_trip_id uuid,
  p_expires_at timestamptz default null
)
returns table (
  trip_id uuid,
  invite_id uuid,
  token text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_actor uuid := auth.uid();
  v_token text;
  v_expires_at timestamptz := coalesce(p_expires_at, clock_timestamp() + interval '7 days');
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if not exists (select 1 from public.trips where id = p_trip_id and deleted_at is null) then
    raise exception 'Trip not found or deleted' using errcode = 'P0002';
  end if;

  if not private.is_profile_trip_member(p_trip_id, v_actor) then
    raise exception 'Only trip members can create invites' using errcode = '42501';
  end if;

  if v_expires_at <= clock_timestamp()
     or v_expires_at > clock_timestamp() + interval '30 days' then
    raise exception 'Invite expiry must be in the future and within 30 days' using errcode = '22023';
  end if;

  v_token := encode(gen_random_bytes(32), 'hex');

  insert into private.trip_invites (trip_id, token_hash, created_by, expires_at)
  values (p_trip_id, digest(v_token, 'sha256'), v_actor, v_expires_at)
  returning id into invite_id;

  trip_id := p_trip_id;
  token := v_token;
  expires_at := v_expires_at;
  return next;
end;
$$;

create or replace function public.join_trip_with_invite(
  p_trip_id uuid,
  p_invite_id uuid,
  p_token text
)
returns uuid
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_actor uuid := auth.uid();
  v_trip_id uuid;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if p_token is null or char_length(p_token) < 32 then
    raise exception 'Invalid invite token' using errcode = '22023';
  end if;

  select i.trip_id into v_trip_id
  from private.trip_invites i
  join public.trips t on t.id = i.trip_id
  where i.id = p_invite_id
    and i.trip_id = p_trip_id
    and i.token_hash = digest(p_token, 'sha256')
    and i.revoked_at is null
    and i.deleted_at is null
    and i.expires_at > clock_timestamp()
    and t.deleted_at is null;

  if v_trip_id is null then
    raise exception 'Invite is invalid, expired, or revoked' using errcode = '22023';
  end if;

  insert into public.trip_members (trip_id, user_id)
  values (v_trip_id, v_actor)
  on conflict (trip_id, user_id) do nothing;

  update private.trip_invites
  set used_at = coalesce(used_at, clock_timestamp())
  where id = p_invite_id;

  return v_trip_id;
end;
$$;

create or replace function public.revoke_trip_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_actor uuid := auth.uid();
  v_trip_id uuid;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select trip_id into v_trip_id
  from private.trip_invites
  where id = p_invite_id and deleted_at is null;

  if v_trip_id is null then
    raise exception 'Invite not found' using errcode = 'P0002';
  end if;

  if not private.is_profile_trip_member(v_trip_id, v_actor) then
    raise exception 'Only trip members can revoke invites' using errcode = '42501';
  end if;

  update private.trip_invites
  set revoked_at = coalesce(revoked_at, clock_timestamp())
  where id = p_invite_id;
end;
$$;

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

drop trigger if exists trg_categories_validate on public.categories;
create trigger trg_categories_validate
  before insert or update of trip_id, is_default, deleted_at on public.categories
  for each row execute function public.validate_category_row();

create or replace function public.validate_expense_row()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not exists (select 1 from public.trips where id = new.trip_id and deleted_at is null) then
    raise exception 'Expense trip must exist and be active' using errcode = '23514';
  end if;

  if not private.is_profile_trip_member(new.trip_id, new.payer_id) then
    raise exception 'Expense payer must be a trip member' using errcode = '23514';
  end if;

  if not private.is_profile_trip_member(new.trip_id, new.created_by) then
    raise exception 'Expense creator must be a trip member' using errcode = '23514';
  end if;

  if new.category_id is not null and not exists (
    select 1 from public.categories c
    where c.id = new.category_id
      and c.deleted_at is null
      and (c.is_default or c.trip_id = new.trip_id)
  ) then
    raise exception 'Expense category must be default or belong to the expense trip' using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_expenses_validate on public.expenses;
create trigger trg_expenses_validate
  before insert or update of trip_id, payer_id, category_id, created_by, deleted_at on public.expenses
  for each row execute function public.validate_expense_row();

create or replace function public.validate_expense_split_row()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_trip_id uuid;
  v_deleted_at timestamptz;
begin
  select trip_id, deleted_at
  into v_trip_id, v_deleted_at
  from public.expenses
  where id = new.expense_id;

  if v_trip_id is null then
    raise exception 'Expense split parent expense must exist' using errcode = '23514';
  end if;

  if v_deleted_at is not null then
    raise exception 'Cannot write splits for a deleted expense' using errcode = '23514';
  end if;

  if not private.is_profile_trip_member(v_trip_id, new.user_id) then
    raise exception 'Expense split user must be a trip member' using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_expense_splits_validate on public.expense_splits;
create trigger trg_expense_splits_validate
  before insert or update of expense_id, user_id on public.expense_splits
  for each row execute function public.validate_expense_split_row();

create or replace function public.validate_expense_split_total(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount numeric(14, 2);
  v_deleted_at timestamptz;
  v_split_count int;
  v_split_total numeric(14, 2);
begin
  select amount, deleted_at
  into v_amount, v_deleted_at
  from public.expenses
  where id = p_expense_id;

  if v_amount is null or v_deleted_at is not null then
    return;
  end if;

  select count(*)::int, coalesce(sum(amount_owed), 0)::numeric(14, 2)
  into v_split_count, v_split_total
  from public.expense_splits
  where expense_id = p_expense_id;

  if v_split_count = 0 then
    raise exception 'Expense % must have at least one split', p_expense_id using errcode = '23514';
  end if;

  if v_split_total <> v_amount then
    raise exception 'Expense % split total % does not equal amount %', p_expense_id, v_split_total, v_amount
      using errcode = '23514';
  end if;
end;
$$;

create or replace function public.validate_expense_split_total_from_expense_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.validate_expense_split_total(coalesce(new.id, old.id));
  return coalesce(new, old);
end;
$$;

create or replace function public.validate_expense_split_total_from_split_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.validate_expense_split_total(coalesce(new.expense_id, old.expense_id));
  if tg_op = 'UPDATE'
     and old.expense_id is not null
     and new.expense_id is not null
     and old.expense_id <> new.expense_id then
    perform public.validate_expense_split_total(old.expense_id);
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_expenses_split_total on public.expenses;
create constraint trigger trg_expenses_split_total
  after insert or update of amount, deleted_at on public.expenses
  deferrable initially deferred
  for each row execute function public.validate_expense_split_total_from_expense_trigger();

drop trigger if exists trg_expense_splits_total on public.expense_splits;
create constraint trigger trg_expense_splits_total
  after insert or update or delete on public.expense_splits
  deferrable initially deferred
  for each row execute function public.validate_expense_split_total_from_split_trigger();

create or replace function public.validate_settlement_row()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not exists (select 1 from public.trips where id = new.trip_id and deleted_at is null) then
    raise exception 'Settlement trip must exist and be active' using errcode = '23514';
  end if;

  if not private.is_profile_trip_member(new.trip_id, new.from_user) then
    raise exception 'Settlement from_user must be a trip member' using errcode = '23514';
  end if;

  if not private.is_profile_trip_member(new.trip_id, new.to_user) then
    raise exception 'Settlement to_user must be a trip member' using errcode = '23514';
  end if;

  if not private.is_profile_trip_member(new.trip_id, new.created_by) then
    raise exception 'Settlement creator must be a trip member' using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_settlements_validate on public.settlements;
create trigger trg_settlements_validate
  before insert or update of trip_id, from_user, to_user, created_by, deleted_at on public.settlements
  for each row execute function public.validate_settlement_row();

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

drop trigger if exists trg_trip_mute_prefs_validate on public.trip_mute_prefs;
create trigger trg_trip_mute_prefs_validate
  before insert or update of trip_id, user_id on public.trip_mute_prefs
  for each row execute function public.validate_trip_mute_pref_row();

drop policy if exists trip_members_insert_self on public.trip_members;

drop policy if exists expenses_insert_member on public.expenses;
drop policy if exists expenses_update_member on public.expenses;
create policy expenses_insert_member on public.expenses
  for insert to authenticated
  with check (
    private.is_trip_member(trip_id)
    and created_by = (select auth.uid())
    and private.is_profile_trip_member(trip_id, payer_id)
    and (
      category_id is null
      or exists (
        select 1 from public.categories c
        where c.id = expenses.category_id
          and c.deleted_at is null
          and (c.is_default or c.trip_id = expenses.trip_id)
      )
    )
  );
create policy expenses_update_member on public.expenses
  for update to authenticated
  using (private.is_trip_member(trip_id))
  with check (
    private.is_trip_member(trip_id)
    and private.is_profile_trip_member(trip_id, payer_id)
    and private.is_profile_trip_member(trip_id, created_by)
    and (
      category_id is null
      or exists (
        select 1 from public.categories c
        where c.id = expenses.category_id
          and c.deleted_at is null
          and (c.is_default or c.trip_id = expenses.trip_id)
      )
    )
  );

drop policy if exists expense_splits_insert_member on public.expense_splits;
drop policy if exists expense_splits_update_member on public.expense_splits;
create policy expense_splits_insert_member on public.expense_splits
  for insert to authenticated
  with check (exists (
    select 1 from public.expenses e
    where e.id = expense_splits.expense_id
      and private.is_trip_member(e.trip_id)
      and private.is_profile_trip_member(e.trip_id, expense_splits.user_id)
  ));
create policy expense_splits_update_member on public.expense_splits
  for update to authenticated
  using  (exists (select 1 from public.expenses e where e.id = expense_splits.expense_id and private.is_trip_member(e.trip_id)))
  with check (exists (
    select 1 from public.expenses e
    where e.id = expense_splits.expense_id
      and private.is_trip_member(e.trip_id)
      and private.is_profile_trip_member(e.trip_id, expense_splits.user_id)
  ));

drop policy if exists settlements_insert_member on public.settlements;
drop policy if exists settlements_update_member on public.settlements;
create policy settlements_insert_member on public.settlements
  for insert to authenticated
  with check (
    private.is_trip_member(trip_id)
    and created_by = (select auth.uid())
    and private.is_profile_trip_member(trip_id, from_user)
    and private.is_profile_trip_member(trip_id, to_user)
  );
create policy settlements_update_member on public.settlements
  for update to authenticated
  using (private.is_trip_member(trip_id))
  with check (
    private.is_trip_member(trip_id)
    and private.is_profile_trip_member(trip_id, from_user)
    and private.is_profile_trip_member(trip_id, to_user)
    and private.is_profile_trip_member(trip_id, created_by)
  );

drop policy if exists trip_mute_prefs_update_self on public.trip_mute_prefs;
create policy trip_mute_prefs_update_self on public.trip_mute_prefs
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and private.is_trip_member(trip_id));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 1048576, array['image/jpeg'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists receipts_select_member on storage.objects;
drop policy if exists receipts_insert_member on storage.objects;
drop policy if exists receipts_update_member on storage.objects;
drop policy if exists receipts_delete_member on storage.objects;

create policy receipts_select_member on storage.objects
  for select to authenticated
  using (
    bucket_id = 'receipts'
    and private.is_trip_member(private.receipt_object_trip_id(name))
  );
create policy receipts_insert_member on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'receipts'
    and private.is_trip_member(private.receipt_object_trip_id(name))
  );
create policy receipts_update_member on storage.objects
  for update to authenticated
  using (
    bucket_id = 'receipts'
    and private.is_trip_member(private.receipt_object_trip_id(name))
  )
  with check (
    bucket_id = 'receipts'
    and private.is_trip_member(private.receipt_object_trip_id(name))
  );
create policy receipts_delete_member on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'receipts'
    and private.is_trip_member(private.receipt_object_trip_id(name))
  );

revoke execute on function public.validate_category_row() from public, anon, authenticated;
revoke execute on function public.validate_expense_row() from public, anon, authenticated;
revoke execute on function public.validate_expense_split_row() from public, anon, authenticated;
revoke execute on function public.validate_expense_split_total(uuid) from public, anon, authenticated;
revoke execute on function public.validate_expense_split_total_from_expense_trigger() from public, anon, authenticated;
revoke execute on function public.validate_expense_split_total_from_split_trigger() from public, anon, authenticated;
revoke execute on function public.validate_settlement_row() from public, anon, authenticated;
revoke execute on function public.validate_trip_mute_pref_row() from public, anon, authenticated;

revoke execute on function public.create_trip_invite(uuid, timestamptz) from public, anon;
grant  execute on function public.create_trip_invite(uuid, timestamptz) to authenticated;
revoke execute on function public.join_trip_with_invite(uuid, uuid, text) from public, anon;
grant  execute on function public.join_trip_with_invite(uuid, uuid, text) to authenticated;
revoke execute on function public.revoke_trip_invite(uuid) from public, anon;
grant  execute on function public.revoke_trip_invite(uuid) to authenticated;

revoke execute on function private.is_trip_member(uuid) from public, anon;
grant  execute on function private.is_trip_member(uuid) to authenticated;
revoke execute on function private.is_profile_trip_member(uuid, uuid) from public, anon;
grant  execute on function private.is_profile_trip_member(uuid, uuid) to authenticated;
revoke execute on function private.receipt_object_trip_id(text) from public, anon;
grant  execute on function private.receipt_object_trip_id(text) to authenticated;
