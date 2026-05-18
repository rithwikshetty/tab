-- 1. Extensions + shared trigger functions
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pgtap     with schema extensions;

grant usage on schema extensions to public;

set check_function_bodies = off;

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
