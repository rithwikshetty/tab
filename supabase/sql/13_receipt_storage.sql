-- 11. Receipt storage bucket + policies
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 10485760, array['image/jpeg'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy receipts_select_member on storage.objects
  for select to authenticated
  using (
    bucket_id = 'receipts'
    and private.can_read_receipt_object(name)
  );

create policy receipts_insert_member on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'receipts'
    and private.can_write_receipt_object(name)
  );

create policy receipts_update_member on storage.objects
  for update to authenticated
  using (
    bucket_id = 'receipts'
    and private.can_write_receipt_object(name)
  )
  with check (
    bucket_id = 'receipts'
    and private.can_write_receipt_object(name)
  );

create policy receipts_delete_member on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'receipts'
    and private.can_write_receipt_object(name)
  );


-- ============================================================================
