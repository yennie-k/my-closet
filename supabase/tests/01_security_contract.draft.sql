-- REVIEW/TEST ONLY. NOT EXECUTED. NEVER RUN AGAINST PRODUCTION.
-- Requires reviewed migrations in staging and TWO FRESH disposable Auth users.
-- The reviewer must explicitly set session GUCs BEFORE running this file:
-- my_closet_test.allow_fixtures = 'yes'; my_closet_test.user_a = '<UUID>';
-- my_closet_test.user_b = '<UUID>'. No auth.users INSERT/UPDATE/DELETE here.
-- SQL role/JWT-GUC simulation tests DB behavior, NOT JWT signature validation.
-- All application fixtures roll back. No storage.objects/buckets DML is used.
begin;

do $$
declare a uuid; b uuid;
begin
  if current_setting('my_closet_test.allow_fixtures', true) is distinct from 'yes' then
    raise exception 'Staging-only test fixture opt-in is required';
  end if;
  a := current_setting('my_closet_test.user_a')::uuid;
  b := current_setting('my_closet_test.user_b')::uuid;
  if a = b or not exists (select 1 from auth.users where id = a)
     or not exists (select 1 from auth.users where id = b) then
    raise exception 'Two different existing disposable Auth users are required';
  end if;
  if exists (select 1 from public.user_preferences where user_id in (a,b))
     or exists (select 1 from public.garments where user_id in (a,b))
     or exists (select 1 from public.garments where id in ('00000000-0000-4000-8000-000000000101'::uuid,'00000000-0000-4000-8000-000000000102'::uuid)) then
    raise exception 'Use fresh staging accounts and unused fixture IDs';
  end if;
  if pg_has_role('authenticated','service_role','MEMBER') then
    raise exception 'authenticated must not be a member of service_role';
  end if;
  if not exists (select 1 from pg_roles where rolname='service_role' and rolbypassrls) then
    raise exception 'Expected managed service_role BYPASSRLS attribute is absent';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object('sub',current_setting('my_closet_test.user_a'),'role','authenticated','is_anonymous',false)::text, true);
insert into public.user_preferences(user_id) values (auth.uid());
insert into public.garments(id,user_id,local_id,name,category,image_width,image_height)
values ('00000000-0000-4000-8000-000000000101',auth.uid(),'sql-review-a','A fixture','tops',1,1);
reset role;

set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object('sub',current_setting('my_closet_test.user_b'),'role','authenticated','is_anonymous',false)::text, true);
insert into public.user_preferences(user_id) values (auth.uid());
insert into public.garments(id,user_id,local_id,name,category,image_width,image_height)
values ('00000000-0000-4000-8000-000000000102',auth.uid(),'sql-review-b','B fixture','tops',1,1);
reset role;

set local role anon;
select set_config('request.jwt.claims', '{}', true);
do $$
begin
  begin
    perform 1 from public.garments;
    raise exception 'FAIL: anon could read garments';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.user_preferences;
    raise exception 'FAIL: anon could read preferences';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object('sub',current_setting('my_closet_test.user_a'),'role','authenticated','is_anonymous',false)::text, true);
do $$
declare affected integer;
begin
  if (select count(*) from public.garments) <> 1 then raise exception 'FAIL: RLS did not isolate A'; end if;
  if (select count(*) from public.user_preferences) <> 1 then raise exception 'FAIL: preferences RLS did not isolate A'; end if;
  update public.user_preferences set design='modern' where user_id=current_setting('my_closet_test.user_b')::uuid;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: cross-user preferences update succeeded'; end if;
  delete from public.user_preferences where user_id=current_setting('my_closet_test.user_b')::uuid;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: cross-user preferences delete succeeded'; end if;
  update public.garments set name='denied cross-user' where id='00000000-0000-4000-8000-000000000102';
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: cross-user update succeeded'; end if;
  delete from public.garments where id='00000000-0000-4000-8000-000000000102';
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: cross-user delete succeeded'; end if;

  -- Garment CAS: only the first writer with revision=1 succeeds.
  update public.garments set name='A first writer' where id='00000000-0000-4000-8000-000000000101' and revision=1;
  get diagnostics affected = row_count;
  if affected <> 1 then raise exception 'FAIL: initial garment CAS failed'; end if;
  update public.garments set name='stale overwrite' where id='00000000-0000-4000-8000-000000000101' and revision=1;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: stale garment CAS was not rejected'; end if;
  if (select revision from public.garments where id='00000000-0000-4000-8000-000000000101') <> 2 then raise exception 'FAIL: garment revision wrong'; end if;

  -- Preferences use the SAME CAS requirement.
  update public.user_preferences set design='lovely' where user_id=auth.uid() and revision=1;
  get diagnostics affected = row_count;
  if affected <> 1 then raise exception 'FAIL: initial preferences CAS failed'; end if;
  update public.user_preferences set design='modern' where user_id=auth.uid() and revision=1;
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'FAIL: stale preferences CAS was not rejected'; end if;

  -- Distinguish 0-row CAS above from actual SQLSTATE 42501 permission errors.
  begin
    update public.garments set photo_state='ready' where id='00000000-0000-4000-8000-000000000101';
    raise exception 'FAIL: client could set ready';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.garments set upload_path='forged' where id='00000000-0000-4000-8000-000000000101';
    raise exception 'FAIL: client could allocate upload slot';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.garments set photo_sha256=repeat('a',64),photo_size_bytes=100 where id='00000000-0000-4000-8000-000000000101';
    raise exception 'FAIL: client could change verified facts';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.garments set upload_state='client_confirmed' where id='00000000-0000-4000-8000-000000000101';
    raise exception 'FAIL: client acknowledged without reservation';
  exception when check_violation then null;
  end;
  begin
    insert into public.garments(user_id,local_id,name,category,image_width,image_height)
    values (current_setting('my_closet_test.user_b')::uuid,'forged-owner','invalid','tops',1,1);
    raise exception 'FAIL: ownership WITH CHECK did not reject insert';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

set local role service_role;
do $$
declare affected integer;
begin
  if has_table_privilege(current_user,'public.user_preferences','SELECT')
     or has_column_privilege(current_user,'public.garments','name','UPDATE')
     or has_column_privilege(current_user,'public.garments','notes','SELECT')
     or has_table_privilege(current_user,'public.garments','DELETE') then
    raise exception 'FAIL: photo worker privileges are too broad';
  end if;
  update public.garments set
    upload_path=user_id::text || '/' || id::text || '/' || repeat('a',64) || '.jpg',
    upload_size_bytes=100,upload_expires_at=clock_timestamp()+interval '10 minutes',upload_state='reserved'
  where id='00000000-0000-4000-8000-000000000101'
    and user_id=current_setting('my_closet_test.user_a')::uuid and revision=2;
  get diagnostics affected = row_count;
  if affected <> 1 then raise exception 'FAIL: worker reservation CAS failed'; end if;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object('sub',current_setting('my_closet_test.user_a'),'role','authenticated','is_anonymous',false)::text, true);
do $$
declare affected integer;
begin
  update public.garments set upload_state='client_confirmed'
  where id='00000000-0000-4000-8000-000000000101' and revision=3;
  get diagnostics affected = row_count;
  if affected <> 1 then raise exception 'FAIL: client acknowledgement CAS failed'; end if;
  if (select photo_state from public.garments where id='00000000-0000-4000-8000-000000000101') <> 'pending' then
    raise exception 'FAIL: client acknowledgement incorrectly meant ready';
  end if;
end;
$$;
reset role;

-- TRUST-BOUNDARY SIMULATION ONLY: there is NO physical Storage object here.
-- This proves service-only state/ACL behavior, NOT real byte verification.
-- Real worker tests MUST first download/decode/hash the uploaded fixture.
set local role service_role;
do $$
declare affected integer;
begin
  begin
    update public.garments set
      photo_path=upload_path,photo_sha256=repeat('a',64),photo_size_bytes=100,
      photo_state='ready',photo_verified_at=clock_timestamp(),upload_state='none',
      upload_path=null,upload_size_bytes=null,upload_expires_at=null
    where id='00000000-0000-4000-8000-000000000101' and revision=4;
    raise exception 'FAIL: activation skipped the server checking step';
  exception when check_violation then null;
  end;
  update public.garments set upload_state='checking'
  where id='00000000-0000-4000-8000-000000000101'
    and user_id=current_setting('my_closet_test.user_a')::uuid and revision=4;
  get diagnostics affected = row_count;
  if affected <> 1 then raise exception 'FAIL: worker checking CAS failed'; end if;
  update public.garments set
    photo_path=upload_path, photo_sha256=repeat('a',64),photo_size_bytes=100,
    photo_verified_at=clock_timestamp(),photo_state='ready',
    upload_state='none',upload_path=null,upload_size_bytes=null,upload_expires_at=null,upload_error_code=null
  where id='00000000-0000-4000-8000-000000000101'
    and user_id=current_setting('my_closet_test.user_a')::uuid and revision=5;
  get diagnostics affected = row_count;
  if affected <> 1 then raise exception 'FAIL: service attestation CAS failed'; end if;
  begin
    update public.garments set
      retired_photo_path=user_id::text || '/' || id::text || '/' || repeat('b',64) || '.jpg',
      retired_cleanup_after=clock_timestamp()+interval '24 hours',
      upload_path=user_id::text || '/' || id::text || '/' || repeat('c',64) || '.jpg',
      upload_size_bytes=100,upload_expires_at=clock_timestamp()+interval '10 minutes',upload_state='reserved'
    where id='00000000-0000-4000-8000-000000000101';
    raise exception 'FAIL: candidate allocated before retired cleanup';
  exception when check_violation then null;
  end;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object('sub',current_setting('my_closet_test.user_a'),'role','authenticated','is_anonymous',true)::text, true);
do $$
begin
  if exists (select 1 from public.garments) or exists (select 1 from public.user_preferences) then
    raise exception 'FAIL: anonymous Auth user could read private data';
  end if;
end;
$$;
reset role;

-- No fixture is committed. Rollback is not a substitute for staging-only use.
rollback;
