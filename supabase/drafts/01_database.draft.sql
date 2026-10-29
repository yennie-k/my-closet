-- DRAFT ONLY / NOT EXECUTED. Review docs/supabase/design-draft.md first.
-- Deliberately outside supabase/migrations: not picked up by db push.
-- Intended for a NEW schema in a reviewed staging project, applied exactly once.
-- Revised review: client upload acknowledgement is NOT server verification.
-- Existing objects/policies cause failure; do not add DROP TABLE or blanket IF NOT EXISTS.
begin;

create schema my_closet_private;
revoke all on schema my_closet_private from public, anon, authenticated, service_role;

create table public.user_preferences (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  model_version smallint not null default 1 check (model_version = 1),
  design text not null default 'minimal' check (design in ('minimal', 'lovely', 'modern')),
  styles text[] not null default '{}',
  temperature text not null default 'normal' check (temperature in ('cold', 'normal', 'hot')),
  onboarding_complete boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  constraint preferences_styles_no_null check (array_position(styles, null) is null),
  constraint preferences_onboarding_has_style check (not onboarding_complete or cardinality(styles) > 0)
);

create table public.garments (
  id uuid primary key default gen_random_uuid(), -- Server ID; NOT the Flutter/local ID.
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  local_id text not null check (length(btrim(local_id)) > 0),
  model_version smallint not null default 2 check (model_version = 2),
  source_model_version smallint not null default 2 check (source_model_version in (1, 2)),
  name text not null check (length(btrim(name)) > 0),
  category text not null check (category in ('tops', 'bottoms', 'outerwear', 'dresses', 'shoes', 'bags', 'accessories', 'other')),
  created_at timestamptz not null default now(), -- Original local creation time.
  updated_at timestamptz not null default now(), -- Original local modification time.
  subtype text not null default '', -- Free text; recommendations are NOT a DB enum.
  primary_color text not null default '',
  primary_color_hex text check (primary_color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  additional_colors text[] not null default '{}',
  additional_color_details jsonb not null default '[]'::jsonb check (jsonb_typeof(additional_color_details) = 'array'),
  seasons text[] not null default '{}',
  thickness text,
  thickness_level smallint check (thickness_level between 1 and 5),
  style_tags text[] not null default '{}',
  material text not null default '', -- Original single string; never split heuristically.
  materials text[] not null default '{}', -- Authoritative, including an intentionally empty list.
  fit text not null default '', -- Preserve old/custom fits even when not suggested.
  notes text not null default '',
  image_mime_type text not null default 'image/jpeg' check (image_mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  image_width integer not null check (image_width > 0),
  image_height integer not null check (image_height > 0),
  photo_state text not null default 'pending' check (photo_state in ('pending', 'ready')),
  photo_path text unique,
  photo_sha256 text check (photo_sha256 ~ '^[0-9a-f]{64}$'),
  photo_size_bytes bigint check (photo_size_bytes between 1 and 2097152),
  photo_verified_at timestamptz, -- Service-only attestation, only after downloading/decoding/hashing actual bytes.
  upload_state text not null default 'none' check (upload_state in ('none', 'reserved', 'client_confirmed', 'checking', 'failed')),
  upload_path text unique, -- Service-only, one candidate slot per garment.
  upload_size_bytes bigint check (upload_size_bytes between 1 and 2097152), -- Expected size, NOT a verified fact.
  upload_expires_at timestamptz,
  upload_error_code text check (upload_error_code in ('not_found', 'hash_mismatch', 'size_mismatch', 'mime_mismatch', 'invalid_image', 'expired', 'cancelled')),
  retired_photo_path text unique, -- Old active object awaiting Storage API cleanup.
  retired_cleanup_after timestamptz,
  import_fingerprint text check (import_fingerprint ~ '^[0-9a-f]{64}$'),
  server_created_at timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  constraint garments_user_local_id_key unique (user_id, local_id),
  constraint garments_seasons_valid check (
    seasons <@ array['spring', 'summer', 'autumn', 'winter']::text[]
    and array_position(seasons, null) is null
  ),
  constraint garments_lists_no_null check (
    array_position(additional_colors, null) is null
    and array_position(style_tags, null) is null
    and array_position(materials, null) is null
  ),
  constraint garments_thickness_consistent check (
    (thickness is null and thickness_level is null)
    or (thickness is not null and thickness_level is not null and
      case thickness
        when 'veryThin' then thickness_level = 1
        when 'thin' then thickness_level = 2
        when 'medium' then thickness_level = 3
        when 'thick' then thickness_level = 4
        when 'veryThick' then thickness_level = 5
        else false
      end)
  ),
  constraint garments_photo_trust_state check (
    (photo_state = 'pending' and photo_path is null and photo_sha256 is null and photo_size_bytes is null and photo_verified_at is null)
    or (photo_state = 'ready' and photo_path is not null and photo_sha256 is not null and photo_size_bytes is not null and photo_verified_at is not null)
  ),
  constraint garments_photo_path_scoped check (
    photo_path is null or (
      photo_sha256 is not null and photo_size_bytes is not null
      and photo_path = user_id::text || '/' || id::text || '/' || photo_sha256 ||
        case image_mime_type when 'image/jpeg' then '.jpg' when 'image/png' then '.png' when 'image/webp' then '.webp' end
    )
  ),
  constraint garments_upload_slot_shape check (
    (upload_state = 'none' and upload_path is null and upload_size_bytes is null and upload_expires_at is null and upload_error_code is null)
    or (upload_state <> 'none' and upload_path is not null and upload_size_bytes is not null and upload_expires_at is not null
        and upload_path ~ ('^' || user_id::text || '/' || id::text || '/[0-9a-f]{64}[.](jpg|png|webp)$')
        and (photo_path is null or upload_path <> photo_path)
        and ((upload_state = 'failed' and upload_error_code is not null) or (upload_state <> 'failed' and upload_error_code is null)))
  ),
  constraint garments_retired_slot_shape check (
    (retired_photo_path is null and retired_cleanup_after is null)
    or (retired_photo_path is not null and retired_cleanup_after is not null
        and retired_photo_path ~ ('^' || user_id::text || '/' || id::text || '/[0-9a-f]{64}[.](jpg|png|webp)$')
        and (photo_path is null or retired_photo_path <> photo_path))
  ),
  -- Drain the old object before allocating another candidate: at most two
  -- named live slots per extant row (active+candidate OR active+retired).
  constraint garments_cleanup_before_next_upload check (upload_path is null or retired_photo_path is null)
);

create index garments_user_id_idx on public.garments(user_id);
create index garments_user_category_subtype_idx on public.garments(user_id, category, subtype);

-- These trigger functions are not RPCs and have no SECURITY DEFINER privileges.
create function my_closet_private.bump_preferences_revision()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if row(new.user_id, new.created_at) is distinct from row(old.user_id, old.created_at) then
    raise exception 'Preference identity and creation time are immutable';
  end if;
  new.revision := old.revision + 1;
  new.updated_at := pg_catalog.clock_timestamp();
  return new;
end;
$$;

create function my_closet_private.bump_garment_revision()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if row(new.id, new.user_id, new.local_id, new.created_at, new.server_created_at,
         new.import_fingerprint, new.source_model_version)
     is distinct from
     row(old.id, old.user_id, old.local_id, old.created_at, old.server_created_at,
         old.import_fingerprint, old.source_model_version) then
    raise exception 'Garment identity, creation time and import provenance are immutable';
  end if;
  new.revision := old.revision + 1;
  new.server_updated_at := pg_catalog.clock_timestamp();
  -- Do NOT replace new.updated_at: it belongs to the Flutter model.
  return new;
end;
$$;

-- Applies to INSERT and UPDATE; grants are the first barrier, this trigger is
-- defense in depth. A client can acknowledge ONE reserved upload, never verify.
create function my_closet_private.guard_photo_workflow()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.photo_state <> 'pending' or new.photo_path is not null or new.photo_sha256 is not null
       or new.photo_size_bytes is not null or new.photo_verified_at is not null
       or new.upload_state <> 'none' or new.upload_path is not null
       or new.retired_photo_path is not null then
      raise exception 'New garments cannot claim verified photos or allocate upload slots' using errcode = '42501';
    end if;
    return new;
  end if;

  if current_user <> 'service_role' then
    if row(new.photo_state, new.photo_path, new.photo_sha256, new.photo_size_bytes, new.photo_verified_at,
           new.image_mime_type, new.image_width, new.image_height,
           new.upload_path, new.upload_size_bytes, new.upload_expires_at, new.upload_error_code,
           new.retired_photo_path, new.retired_cleanup_after)
       is distinct from
       row(old.photo_state, old.photo_path, old.photo_sha256, old.photo_size_bytes, old.photo_verified_at,
           old.image_mime_type, old.image_width, old.image_height,
           old.upload_path, old.upload_size_bytes, old.upload_expires_at, old.upload_error_code,
           old.retired_photo_path, old.retired_cleanup_after) then
      raise exception 'Only the server photo worker can change photo facts or reservations' using errcode = '42501';
    end if;
    if new.upload_state is distinct from old.upload_state and not (
      old.upload_state = 'reserved' and new.upload_state = 'client_confirmed'
      and old.upload_expires_at > pg_catalog.clock_timestamp()
    ) then
      raise exception 'Client may only acknowledge an unexpired reserved upload' using errcode = '23514';
    end if;
  end if;

  if old.upload_path is not null and new.upload_path is not null and old.upload_path <> new.upload_path then
    raise exception 'Clean up and release the old upload slot before replacing it' using errcode = '23514';
  end if;
  if old.retired_photo_path is not null and new.retired_photo_path is not null and old.retired_photo_path <> new.retired_photo_path then
    raise exception 'Drain the existing retired slot before replacing it' using errcode = '23514';
  end if;
  if new.photo_state = 'ready' and (
    old.photo_state <> 'ready' or row(new.photo_path,new.photo_sha256,new.photo_size_bytes,new.image_mime_type,new.image_width,new.image_height)
      is distinct from row(old.photo_path,old.photo_sha256,old.photo_size_bytes,old.image_mime_type,old.image_width,old.image_height)
  ) then
    if old.upload_state <> 'checking' or old.upload_path is null
       or new.photo_path is distinct from old.upload_path
       or new.photo_size_bytes is distinct from old.upload_size_bytes
       or new.photo_verified_at is null
       or new.photo_verified_at is not distinct from old.photo_verified_at
       or new.upload_state <> 'none' or new.upload_path is not null then
      raise exception 'Activation must consume the exact checking slot with fresh server attestation' using errcode = '23514';
    end if;
    if old.photo_path is not null and (
      new.retired_photo_path is distinct from old.photo_path
      or new.retired_cleanup_after is null
      or new.retired_cleanup_after < pg_catalog.clock_timestamp() + interval '24 hours'
    ) then
      raise exception 'Retain the previous active path with a cleanup grace period' using errcode = '23514';
    end if;
  end if;
  if new.upload_path is not null and (old.upload_path is distinct from new.upload_path or old.upload_expires_at is distinct from new.upload_expires_at) then
    if new.upload_expires_at is null or new.upload_expires_at <= pg_catalog.clock_timestamp()
       or new.upload_expires_at > pg_catalog.clock_timestamp() + interval '15 minutes' then
      raise exception 'Upload reservations must expire within fifteen minutes' using errcode = '23514';
    end if;
  end if;
  -- SQL cannot inspect S3 bytes. service_role is a trusted attestor, not a hash
  -- verification algorithm. Worker implementation/tests remain a release gate.
  return new;
end;
$$;

revoke all on function my_closet_private.bump_preferences_revision() from public, anon, authenticated, service_role;
revoke all on function my_closet_private.bump_garment_revision() from public, anon, authenticated, service_role;
revoke all on function my_closet_private.guard_photo_workflow() from public, anon, authenticated, service_role;

create trigger mc_preferences_revision before update on public.user_preferences
for each row execute function my_closet_private.bump_preferences_revision();
create trigger mc_garment_revision before update on public.garments
for each row execute function my_closet_private.bump_garment_revision();
create trigger mc_guard_photo_workflow before insert or update on public.garments
for each row execute function my_closet_private.guard_photo_workflow();

-- No anonymous personal-data policies. Existing automatic RLS does not replace these.

alter table public.user_preferences enable row level security;
alter table public.user_preferences force row level security;

create policy mc_user_preferences_select on public.user_preferences
for select to authenticated using ((select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true'));
create policy mc_user_preferences_insert on public.user_preferences
for insert to authenticated with check ((select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true'));
create policy mc_user_preferences_update on public.user_preferences
for update to authenticated
using ((select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true'))
with check ((select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true'));
create policy mc_user_preferences_delete on public.user_preferences
for delete to authenticated using ((select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true'));


alter table public.garments enable row level security;
alter table public.garments force row level security;

create policy mc_garments_select on public.garments
for select to authenticated using ((select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true'));
create policy mc_garments_insert on public.garments
for insert to authenticated with check ((select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true'));
create policy mc_garments_update on public.garments
for update to authenticated
using ((select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true'))
with check ((select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true'));
create policy mc_garments_delete on public.garments
for delete to authenticated using ((select auth.uid()) is not null
  and (select auth.uid()) = user_id
  and ((select auth.jwt() ->> 'is_anonymous') is distinct from 'true'));

-- Explicit opt-in for a project with automatic table exposure disabled.
-- Do not change grants/default privileges of unrelated objects or auth/storage schemas.
revoke all on table public.user_preferences, public.garments from public, anon, authenticated, service_role;
grant usage on schema public to authenticated;
grant select, delete on table public.user_preferences, public.garments to authenticated;

grant insert (user_id, model_version, design, styles, temperature, onboarding_complete)
on public.user_preferences to authenticated;
grant update (model_version, design, styles, temperature, onboarding_complete)
on public.user_preferences to authenticated;

grant insert (
  id, user_id, local_id, model_version, source_model_version,
  name, category, created_at, updated_at, subtype, primary_color, primary_color_hex,
  additional_colors, additional_color_details, seasons, thickness, thickness_level,
  style_tags, material, materials, fit, notes, image_mime_type, image_width, image_height,
  import_fingerprint
) on public.garments to authenticated;

grant update (
  model_version, name, category, updated_at, subtype, primary_color, primary_color_hex,
  additional_colors, additional_color_details, seasons, thickness, thickness_level,
  style_tags, material, materials, fit, notes, upload_state
) on public.garments to authenticated;

-- No sequence privileges (UUID IDs), no table-wide UPDATE/INSERT, no GRANT ALL,
-- Server-only photo worker: no preferences access, garment INSERT/DELETE or
-- edits to ordinary garment metadata. service_role still bypasses RLS; the
-- server MUST validate caller identity/ownership and use expected-revision CAS.
grant usage on schema public to service_role;
grant select (
  id, user_id, photo_state, photo_path, photo_sha256, photo_size_bytes, photo_verified_at,
  image_mime_type, image_width, image_height, upload_state, upload_path,
  upload_size_bytes, upload_expires_at, upload_error_code,
  retired_photo_path, retired_cleanup_after, revision, server_created_at, server_updated_at
) on public.garments to service_role;
grant update (
  photo_state, photo_path, photo_sha256, photo_size_bytes, photo_verified_at,
  image_mime_type, image_width, image_height, upload_state, upload_path,
  upload_size_bytes, upload_expires_at, upload_error_code, retired_photo_path, retired_cleanup_after
) on public.garments to service_role;

-- No grants to anon, no browser service key, no general service_role CRUD,
-- and no new callable API functions. API/worker code is NOT implemented here.
commit;