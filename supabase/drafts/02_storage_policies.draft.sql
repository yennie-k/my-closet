-- DRAFT ONLY / NOT EXECUTED.
-- Requires 01_database.draft.sql and a reviewed private bucket created via Dashboard/Storage API.
-- No bucket/object DML, no broad grants or changes to Supabase-managed schema ownership.
-- Operation-aware helpers are intentionally required; fail closed on older installations.
-- Official sources checked: tenant/0024-operation-function.sql,
-- tenant/0058-operation-ergonomics.sql and src/http/routes/operations.ts.
-- Their presence in this deployed project is NOT established by source review.
begin;

do $$
begin
  if to_regprocedure('storage.operation()') is null
     or to_regprocedure('storage.allow_any_operation(text[])') is null
     or to_regprocedure('storage.allow_only_operation(text)') is null then
    raise exception 'Storage operation helpers unavailable: review deployment; do not weaken policies';
  end if;
  if not exists (
    select 1 from storage.buckets
    where id = 'garment-photos' and name = 'garment-photos'
      and public = false
      and file_size_limit = 2097152
      and allowed_mime_types @> array['image/jpeg', 'image/png', 'image/webp']::text[]
      and allowed_mime_types <@ array['image/jpeg', 'image/png', 'image/webp']::text[]
  ) then
    raise exception 'Create/review private garment-photos bucket with exact MIME and 2 MiB limit first';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_class
    where oid = 'storage.objects'::regclass and relrowsecurity
  ) then
    raise exception 'Managed Storage RLS is not enabled; inspect project configuration';
  end if;
  if not (
    has_table_privilege('authenticated', 'storage.objects', 'SELECT')
    and has_table_privilege('authenticated', 'storage.objects', 'INSERT')
    and has_table_privilege('authenticated', 'storage.objects', 'DELETE')
  ) then
    raise exception 'Expected managed Storage grants missing; review rather than granting all';
  end if;
end;
$$;

-- Restrictive guards prevent unrelated broad permissive policies from granting
-- access to this bucket. Other buckets are not constrained by these guards.
create policy mc_photos_anon_guard on storage.objects
as restrictive for all to anon
using (bucket_id <> 'garment-photos')
with check (bucket_id <> 'garment-photos');

create policy mc_photos_owner_guard on storage.objects
as restrictive for all to authenticated
using (bucket_id <> 'garment-photos' or ((select auth.uid()) is not null
    and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true')
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[2] ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    and storage.filename(name) ~ '^[0-9a-f]{64}[.](jpg|png|webp)$'))
with check (bucket_id <> 'garment-photos' or ((select auth.uid()) is not null
    and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true')
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[2] ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    and storage.filename(name) ~ '^[0-9a-f]{64}[.](jpg|png|webp)$'));

-- SELECT is used by download, metadata, list and internal upload/delete checks.
-- Exclude sign/sign_many/sign_upload_url: MVP downloads require an active user JWT.
-- Inspect operation labels and deployed helpers during staging verification.
create policy mc_photos_read_operations_guard on storage.objects
as restrictive for select to authenticated
using (bucket_id <> 'garment-photos' or (storage.allow_any_operation(array[
    'object.get_authenticated', 'object.get_authenticated_info', 'object.head_authenticated_info',
    'object.list', 'object.list_v2', 'object.upload', 'object.delete', 'object.delete_many'
  ]::text[])));

create policy mc_photos_insert_reservation_guard on storage.objects
as restrictive for insert to authenticated
with check (bucket_id <> 'garment-photos' or (
  storage.allow_only_operation('object.upload') and exists (
      select 1 from public.garments g
      where g.user_id = (select auth.uid())
        and g.id::text = (storage.foldername(storage.objects.name))[2]
        and g.upload_path = storage.objects.name
        and g.upload_state = 'reserved'
        and g.upload_expires_at > now()
        and g.retired_photo_path is null
    )
));

-- Content-addressed objects are replaced by uploading a NEW path, then updating
-- the garment metadata. No Storage upsert, overwrites, or moves in this draft.
create policy mc_photos_no_update on storage.objects
as restrictive for update to authenticated
using (bucket_id <> 'garment-photos')
with check (bucket_id <> 'garment-photos');

-- Protect active and in-flight images from direct user deletion. Server-side
-- cleanup uses Storage API after owner/reference/lease rechecks, never SQL DML.
create policy mc_photos_delete_reference_guard on storage.objects
as restrictive for delete to authenticated
using (bucket_id <> 'garment-photos' or not exists (
  select 1 from public.garments g
  where g.user_id = (select auth.uid()) and (
    g.photo_path = storage.objects.name
    or g.upload_path = storage.objects.name
    or (g.retired_photo_path = storage.objects.name and g.retired_cleanup_after > now())
  )
));

create policy mc_photos_select on storage.objects
for select to authenticated
using (bucket_id = 'garment-photos' and ((select auth.uid()) is not null
    and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true')
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[2] ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    and storage.filename(name) ~ '^[0-9a-f]{64}[.](jpg|png|webp)$'));

create policy mc_photos_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'garment-photos'
  and ((select auth.uid()) is not null
    and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true')
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[2] ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    and storage.filename(name) ~ '^[0-9a-f]{64}[.](jpg|png|webp)$')
  and storage.allow_only_operation('object.upload')
  and exists (
      select 1 from public.garments g
      where g.user_id = (select auth.uid())
        and g.id::text = (storage.foldername(storage.objects.name))[2]
        and g.upload_path = storage.objects.name
        and g.upload_state = 'reserved'
        and g.upload_expires_at > now()
        and g.retired_photo_path is null
    )
);

-- Orphans remain removable by their original owner even after a garment row
-- was deleted. Never require row existence for owner SELECT/DELETE.
create policy mc_photos_delete on storage.objects
for delete to authenticated
using (bucket_id = 'garment-photos' and ((select auth.uid()) is not null
    and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true')
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[2] ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    and storage.filename(name) ~ '^[0-9a-f]{64}[.](jpg|png|webp)$'));

-- No GRANT on storage.buckets/objects: retain Supabase's managed Storage grants.
-- Bucket/object creation/removal happens only through Dashboard/Storage API.
commit;