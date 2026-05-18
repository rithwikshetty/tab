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
