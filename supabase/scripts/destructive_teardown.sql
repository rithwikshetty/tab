-- Pre-launch destructive reset for tab.
-- Drops app-owned schema objects. Supabase blocks direct deletes from storage
-- metadata tables, so receipt files/buckets are left to Storage API cleanup.

drop policy if exists receipts_select_member on storage.objects;
drop policy if exists receipts_insert_member on storage.objects;
drop policy if exists receipts_update_member on storage.objects;
drop policy if exists receipts_delete_member on storage.objects;

drop trigger if exists trg_on_auth_user_created on auth.users;

drop table if exists
  public.trip_mute_prefs,
  public.push_devices,
  public.activity_log,
  public.settlements,
  public.expense_payments,
  public.expense_splits,
  public.expenses,
  public.categories,
  public.trip_members,
  public.trips,
  public.profiles
cascade;

drop schema if exists private cascade;

drop function if exists public.set_sync_fields() cascade;
drop function if exists public.handle_new_user() cascade;
drop function if exists public.auto_add_creator_as_member() cascade;
drop function if exists public.create_trip_invite(uuid, timestamptz) cascade;
drop function if exists public.join_trip_with_invite(uuid, uuid, text) cascade;
drop function if exists public.revoke_trip_invite(uuid) cascade;
drop function if exists public.validate_category_row() cascade;
drop function if exists public.validate_expense_row() cascade;
drop function if exists public.touch_trip_last_activity() cascade;
drop function if exists public.validate_expense_split_row() cascade;
drop function if exists public.validate_expense_split_total(uuid) cascade;
drop function if exists public.validate_expense_split_total_from_expense_trigger() cascade;
drop function if exists public.validate_expense_split_total_from_split_trigger() cascade;
drop function if exists public.validate_expense_payment_row() cascade;
drop function if exists public.validate_expense_payment_total(uuid) cascade;
drop function if exists public.validate_expense_payment_total_from_expense_trigger() cascade;
drop function if exists public.validate_expense_payment_total_from_payment_trigger() cascade;
drop function if exists public.validate_settlement_row() cascade;
drop function if exists public.validate_trip_mute_pref_row() cascade;
drop function if exists public.purge_soft_deleted_records(timestamptz) cascade;
drop function if exists public.create_expense_with_payments_and_splits(jsonb, jsonb, jsonb) cascade;
