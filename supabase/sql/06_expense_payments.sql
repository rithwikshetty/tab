-- ============================================================================
-- Expense payment ledger
-- ============================================================================

create table public.expense_payments (
  expense_id     uuid not null references public.expenses(id) on delete cascade,
  trip_person_id uuid not null references public.trip_people(id) on delete restrict,
  amount_paid    numeric(20, 8) not null check (amount_paid >= 0),
  payment_mode   text not null check (payment_mode in ('equal', 'exact', 'percentage', 'shares', 'adjustment')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  write_id       uuid not null default gen_random_uuid(),
  primary key (expense_id, trip_person_id)
);

comment on table public.expense_payments is
  'Per-payer contribution to an expense. Mirrors expense_splits. Cascade-deletes if the parent expense is hard-deleted.';

create index expense_payments_trip_person_id_idx on public.expense_payments(trip_person_id);

create trigger trg_expense_payments_sync_fields
  before insert or update on public.expense_payments
  for each row execute function public.set_sync_fields();

create or replace function public.validate_expense_payment_row()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_trip_id    uuid;
  v_deleted_at timestamptz;
begin
  select trip_id, deleted_at
  into v_trip_id, v_deleted_at
  from public.expenses
  where id = new.expense_id;

  if v_trip_id is null then
    raise exception 'Expense payment parent expense must exist' using errcode = '23514';
  end if;

  if v_deleted_at is not null then
    raise exception 'Cannot write payments for a deleted expense' using errcode = '23514';
  end if;

  if not private.is_trip_person(v_trip_id, new.trip_person_id) then
    raise exception 'Expense payment person must belong to the expense trip' using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger trg_expense_payments_validate
  before insert or update of expense_id, trip_person_id on public.expense_payments
  for each row execute function public.validate_expense_payment_row();

create or replace function public.validate_expense_payment_total(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount     numeric(20, 8);
  v_deleted_at timestamptz;
  v_pay_count  int;
  v_pay_total  numeric(20, 8);
begin
  select amount, deleted_at
  into v_amount, v_deleted_at
  from public.expenses
  where id = p_expense_id;

  if v_amount is null or v_deleted_at is not null then
    return;
  end if;

  select count(*)::int, coalesce(sum(amount_paid), 0)::numeric(20, 8)
  into v_pay_count, v_pay_total
  from public.expense_payments
  where expense_id = p_expense_id;

  if v_pay_count = 0 then
    raise exception 'Expense % must have at least one payment', p_expense_id using errcode = '23514';
  end if;

  if v_pay_total <> v_amount then
    raise exception 'Expense % payment total % does not equal amount %', p_expense_id, v_pay_total, v_amount
      using errcode = '23514';
  end if;
end;
$$;

create or replace function public.validate_expense_payment_total_from_expense_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.validate_expense_payment_total(coalesce(new.id, old.id));
  return coalesce(new, old);
end;
$$;

create or replace function public.validate_expense_payment_total_from_payment_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.validate_expense_payment_total(coalesce(new.expense_id, old.expense_id));
  if tg_op = 'UPDATE'
     and old.expense_id is not null
     and new.expense_id is not null
     and old.expense_id <> new.expense_id then
    perform public.validate_expense_payment_total(old.expense_id);
  end if;

  return coalesce(new, old);
end;
$$;

create constraint trigger trg_expenses_payment_total
  after insert or update of amount, deleted_at on public.expenses
  deferrable initially deferred
  for each row execute function public.validate_expense_payment_total_from_expense_trigger();

create constraint trigger trg_expense_payments_total
  after insert or update or delete on public.expense_payments
  deferrable initially deferred
  for each row execute function public.validate_expense_payment_total_from_payment_trigger();
