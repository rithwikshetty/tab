-- Keep expense IDs scoped to their original trip when the transactional RPC
-- is used for edits. Without this guard, a colliding expense ID could update
-- row fields while leaving the original trip_id unchanged.

create or replace function public.create_expense_with_splits(
    p_expense jsonb,
    p_splits  jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
    v_actor       uuid := auth.uid();
    v_expense_id  uuid;
    v_trip_id     uuid;
    v_split       jsonb;
begin
    if v_actor is null then
        raise exception 'Authentication required' using errcode = '28000';
    end if;

    v_expense_id := coalesce((p_expense->>'id')::uuid, gen_random_uuid());
    v_trip_id    := (p_expense->>'trip_id')::uuid;

    if v_trip_id is null then
        raise exception 'trip_id is required' using errcode = '22023';
    end if;

    if not private.is_profile_trip_member(v_trip_id, v_actor) then
        raise exception 'Must be a trip member to write expenses' using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.expenses
        where id = v_expense_id
          and trip_id <> v_trip_id
    ) then
        raise exception 'Expense belongs to a different trip' using errcode = '23514';
    end if;

    insert into public.expenses (
        id, trip_id, payer_id, amount, currency, category_id,
        description, expense_date, receipt_storage_path, created_by
    )
    values (
        v_expense_id,
        v_trip_id,
        (p_expense->>'payer_id')::uuid,
        (p_expense->>'amount')::numeric(14, 2),
        p_expense->>'currency',
        nullif(p_expense->>'category_id', '')::uuid,
        p_expense->>'description',
        (p_expense->>'expense_date')::date,
        nullif(p_expense->>'receipt_storage_path', ''),
        v_actor
    )
    on conflict (id) do update set
        payer_id             = excluded.payer_id,
        amount               = excluded.amount,
        currency             = excluded.currency,
        category_id          = excluded.category_id,
        description          = excluded.description,
        expense_date         = excluded.expense_date,
        receipt_storage_path = excluded.receipt_storage_path;

    delete from public.expense_splits where expense_id = v_expense_id;

    for v_split in select * from jsonb_array_elements(p_splits)
    loop
        insert into public.expense_splits (
            expense_id, user_id, amount_owed, split_type
        )
        values (
            v_expense_id,
            (v_split->>'user_id')::uuid,
            (v_split->>'amount_owed')::numeric(14, 2),
            v_split->>'split_type'
        );
    end loop;

    return v_expense_id;
end;
$$;

comment on function public.create_expense_with_splits(jsonb, jsonb) is
    'Atomically upserts an expense and replaces its splits. Required because the split-total constraint is deferred and would fail on separate REST writes.';

revoke execute on function public.create_expense_with_splits(jsonb, jsonb) from public, anon;
grant  execute on function public.create_expense_with_splits(jsonb, jsonb) to authenticated;
