-- REVIEW/TEST ONLY. NOT EXECUTED. Read-only catalog/helper assertions, NO files.
-- Run only in an explicitly approved staging session after both draft migrations.
-- This does NOT exercise HTTP upload/download/delete or physical object storage.
begin;
do $$
declare op text; value boolean;
begin
  if current_setting('my_closet_test.allow_fixtures',true) is distinct from 'yes' then
    raise exception 'Staging-only test opt-in required';
  end if;
  if to_regprocedure('storage.operation()') is null
     or to_regprocedure('storage.allow_only_operation(text)') is null
     or to_regprocedure('storage.allow_any_operation(text[])') is null then
    raise exception 'Deployed Storage does not have the reviewed helpers';
  end if;
  foreach op in array array[
    'storage.object.upload','storage.object.get_authenticated','storage.object.list',
    'storage.object.list_v2','storage.object.delete','storage.object.delete_many'
  ] loop
    perform set_config('storage.operation',op,true);
    if not storage.allow_only_operation(op)
       or not storage.allow_only_operation(substr(op,9))
       or not storage.allow_any_operation(array[op]) then
      raise exception 'Operation normalization failed: %',op;
    end if;
    if storage.allow_only_operation('object.sign') then raise exception 'Unexpected operation match'; end if;
  end loop;
  perform set_config('storage.operation','',true);
  if storage.allow_any_operation(array['object.upload']) or storage.allow_only_operation('') then
    raise exception 'Empty operation must fail closed';
  end if;
  if exists (
    select 1 from storage.buckets where id='garment-photos' and (
      public or file_size_limit is distinct from 2097152
      or allowed_mime_types is null
      or not (allowed_mime_types <@ array['image/jpeg','image/png','image/webp']::text[])
      or not (allowed_mime_types @> array['image/jpeg','image/png','image/webp']::text[])
    )
  ) or not exists (select 1 from storage.buckets where id='garment-photos') then
    raise exception 'Bucket absent or limits differ';
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects'
    and policyname='mc_photos_owner_guard' and permissive='RESTRICTIVE' and qual is not null and with_check is not null)
  or not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects'
    and policyname='mc_photos_insert_reservation_guard' and permissive='RESTRICTIVE'
    and with_check like '%upload_path%' and with_check like '%upload_expires_at%')
  or not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects'
    and policyname='mc_photos_delete_reference_guard' and permissive='RESTRICTIVE' and qual like '%photo_path%') then
    raise exception 'Required restrictive policies absent or incomplete';
  end if;
end;
$$;
rollback;
