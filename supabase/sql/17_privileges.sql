-- 13. Function privilege locking
-- ============================================================================
-- Trigger functions exist only to be invoked by their triggers — they should
-- never be callable via /rest/v1/rpc. Revoke EXECUTE from public/anon/auth.
revoke execute on function public.handle_new_user()            from public, anon, authenticated;
revoke execute on function public.touch_trip_last_activity()   from public, anon, authenticated;
revoke execute on function public.set_sync_fields()            from public, anon, authenticated;
revoke execute on function public.validate_category_row() from public, anon, authenticated;
revoke execute on function public.validate_expense_row() from public, anon, authenticated;
revoke execute on function public.validate_expense_split_row() from public, anon, authenticated;
revoke execute on function public.validate_expense_split_total(uuid) from public, anon, authenticated;
revoke execute on function public.validate_expense_split_total_from_expense_trigger() from public, anon, authenticated;
revoke execute on function public.validate_expense_split_total_from_split_trigger() from public, anon, authenticated;
revoke execute on function public.validate_expense_payment_row() from public, anon, authenticated;
revoke execute on function public.validate_expense_payment_total(uuid) from public, anon, authenticated;
revoke execute on function public.validate_expense_payment_total_from_expense_trigger() from public, anon, authenticated;
revoke execute on function public.validate_expense_payment_total_from_payment_trigger() from public, anon, authenticated;
revoke execute on function public.validate_settlement_row() from public, anon, authenticated;
revoke execute on function public.validate_trip_mute_pref_row() from public, anon, authenticated;
revoke execute on function public.purge_soft_deleted_records(timestamptz) from public, anon, authenticated;

revoke execute on function public.ensure_current_profile(text, text) from public, anon;
grant  execute on function public.ensure_current_profile(text, text) to authenticated;
revoke execute on function public.create_trip_with_self(uuid, uuid, text) from public, anon;
grant  execute on function public.create_trip_with_self(uuid, uuid, text) to authenticated;
revoke execute on function public.add_trip_person_by_email(uuid, text, text, uuid) from public, anon;
grant  execute on function public.add_trip_person_by_email(uuid, text, text, uuid) to authenticated;
revoke execute on function public.claim_trip_people_for_current_email() from public, anon;
grant  execute on function public.claim_trip_people_for_current_email() to authenticated;
revoke execute on function public.suggest_trip_people(text, int) from public, anon;
grant  execute on function public.suggest_trip_people(text, int) to authenticated;
revoke execute on function public.create_expense_with_payments_and_splits(jsonb, jsonb, jsonb) from public, anon;
grant  execute on function public.create_expense_with_payments_and_splits(jsonb, jsonb, jsonb) to authenticated;

-- private helpers are not PostgREST-exposed, but authenticated sessions need
-- EXECUTE for policy evaluation.
revoke execute on function private.is_trip_member(uuid) from public, anon;
grant  execute on function private.is_trip_member(uuid) to authenticated;
revoke execute on function private.is_profile_trip_member(uuid, uuid) from public, anon;
grant  execute on function private.is_profile_trip_member(uuid, uuid) to authenticated;
revoke execute on function private.is_trip_person(uuid, uuid) from public, anon;
grant  execute on function private.is_trip_person(uuid, uuid) to authenticated;
revoke execute on function private.normalized_email(text) from public, anon;
grant  execute on function private.normalized_email(text) to authenticated;
revoke execute on function private.current_auth_email() from public, anon;
grant  execute on function private.current_auth_email() to authenticated;
revoke execute on function private.receipt_object_trip_id(text) from public, anon;
grant  execute on function private.receipt_object_trip_id(text) to authenticated;
