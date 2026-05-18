create or replace function public.purge_soft_deleted_records(
  p_cutoff timestamptz default clock_timestamp() - interval '30 days'
)
returns table (table_name text, deleted_count integer)
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_count integer;
begin
  delete from public.settlements where deleted_at is not null and deleted_at < p_cutoff;
  get diagnostics v_count = row_count;
  table_name := 'public.settlements'; deleted_count := v_count; return next;

  delete from public.expenses where deleted_at is not null and deleted_at < p_cutoff;
  get diagnostics v_count = row_count;
  table_name := 'public.expenses'; deleted_count := v_count; return next;

  delete from public.categories where deleted_at is not null and deleted_at < p_cutoff;
  get diagnostics v_count = row_count;
  table_name := 'public.categories'; deleted_count := v_count; return next;

  delete from public.trips t
  where t.deleted_at is not null
    and t.deleted_at < p_cutoff
    and not exists (select 1 from public.expenses e where e.trip_id = t.id)
    and not exists (select 1 from public.settlements s where s.trip_id = t.id);
  get diagnostics v_count = row_count;
  table_name := 'public.trips'; deleted_count := v_count; return next;
end;
$$;

comment on function public.purge_soft_deleted_records(timestamptz) is
  'Hard-deletes soft-deleted rows older than the cutoff. Intended for service-role scheduled execution after the 30-day recovery window.';

-- Ensure Postgres change feeds include the trip-sync tables used by the app's
-- realtime subscriptions.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  if not exists (
    select 1
    from pg_publication p
    join pg_publication_rel pr on pr.prpubid = p.oid
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'trips'
  ) then
    execute 'alter publication supabase_realtime add table public.trips';
  end if;

  if not exists (
    select 1
    from pg_publication p
    join pg_publication_rel pr on pr.prpubid = p.oid
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'trip_people'
  ) then
    execute 'alter publication supabase_realtime add table public.trip_people';
  end if;

  if not exists (
    select 1
    from pg_publication p
    join pg_publication_rel pr on pr.prpubid = p.oid
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'expenses'
  ) then
    execute 'alter publication supabase_realtime add table public.expenses';
  end if;

  if not exists (
    select 1
    from pg_publication p
    join pg_publication_rel pr on pr.prpubid = p.oid
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'settlements'
  ) then
    execute 'alter publication supabase_realtime add table public.settlements';
  end if;
end
$$;


-- ============================================================================
