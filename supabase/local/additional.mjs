// Additional local fixtures and non-destructive assertions before deletion approval.
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT, API, guard, sql, jsonSql, sqlRole, lit, sha, save, http } from './integration.mjs';
const dir=join(ROOT,'build/supabase-local/20261029-run1');
assert(!existsSync(join(dir,'additional-results.json')));
const {status}=guard();const key=status.PUBLISHABLE_KEY||status.ANON_KEY;const admin=status.SERVICE_ROLE_KEY;
const ctx=JSON.parse(readFileSync(join(dir,'context.private.json'),'utf8'));
assert.equal(ctx.run,'20261029-run1');assert.equal(ctx.target,API);
const a=ctx.users.a,b=ctx.users.b;const image=readFileSync(join(dir,'synthetic-1x1.png'));
const checks=[];async function check(group,name,fn){try{const detail=await fn();checks.push({group,name,status:'PASS',...(detail?{detail}:{})});console.log(`PASS [${group}] ${name}`);}catch(e){checks.push({group,name,status:'FAIL',detail:String(e.stderr||e.message)});console.log(`FAIL [${group}] ${name}: ${String(e.stderr||e.message)}`);}}
const req=(path,jwt,init={})=>http(path,key,jwt,init);
const js=(method,body)=>({method,headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
async function r(res){const text=await res.text();let data;try{data=JSON.parse(text);}catch{data=text;}return {status:res.status,data};}
const upload=(bucket,path,jwt)=>req(`/storage/v1/object/${bucket}/${path}`,jwt,{method:'POST',headers:{'Content-Type':'image/png','x-upsert':'false'},body:image});
const download=(bucket,path,jwt)=>req(`/storage/v1/object/authenticated/${bucket}/${path}`,jwt);
const extra={run:ctx.run,retiredPath:ctx.photos.active,controlBucket:'mc-control-20261029-run1',controlPath:`${a.id}/synthetic-control.png`};
function replacementPng() {
 const data=Buffer.from('Comment\0local-policy-fixture-replacement');const typed=Buffer.concat([Buffer.from('tEXt'),data]);
 let crc=0xffffffff;for(const byte of typed){crc^=byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}
 const size=Buffer.alloc(4);size.writeUInt32BE(data.length);const sum=Buffer.alloc(4);sum.writeUInt32BE((crc^0xffffffff)>>>0);
 return Buffer.concat([image.subarray(0,-12),size,typed,sum,image.subarray(-12)]);
}
try {
 await check('rls','Forged JWT subject rejected by real API signature validation',async()=>{
  const parts=a.jwt.split('.');const payload=JSON.parse(Buffer.from(parts[1],'base64url').toString());payload.sub=b.id;parts[1]=Buffer.from(JSON.stringify(payload)).toString('base64url');
  const res=await r(await req('/rest/v1/garments',parts.join('.')));assert.equal(res.status,401);return {http:res.status};
 });
 await check('rls','anon has no table CRUD grants and no insert/update column grants',()=>{
  const v=jsonSql(`select json_agg(json_build_object('table',t,'select',has_table_privilege('anon',t,'SELECT'),'insert',has_any_column_privilege('anon',t,'INSERT'),'update',has_any_column_privilege('anon',t,'UPDATE'),'delete',has_table_privilege('anon',t,'DELETE'))) from unnest(array['public.garments','public.user_preferences']) t;`);
  for(const row of v)for(const k of ['select','insert','update','delete'])assert.equal(row[k],false);
 });
 await check('storage','Replacement activates with retired grace (POLICY SIMULATION ONLY)',async()=>{
  const id=ctx.garments['active-policy-simulation'].id;
  // Valid ancillary tEXt chunk changes the content hash without external image assets.
  const replacement=replacementPng();
  const path=`${a.id}/${id}/${sha(replacement)}.png`;extra.activeReplacement=path;
  const n=sqlRole('service_role',null,`with c as(update public.garments set upload_state='reserved',upload_path=${lit(path)},upload_size_bytes=${replacement.length},upload_expires_at=clock_timestamp()+interval '10 minutes' where id=${lit(id)} and revision=(select revision from public.garments where id=${lit(id)}) returning id)select count(*) from c;`,true);assert.equal(n,'1');
  const res=await r(await req(`/storage/v1/object/garment-photos/${path}`,a.jwt,{method:'POST',headers:{'Content-Type':'image/png','x-upsert':'false'},body:replacement}));assert([200,201].includes(res.status),JSON.stringify(res));
  sqlRole('service_role',null,`update public.garments set upload_state='checking' where id=${lit(id)};
   update public.garments set retired_photo_path=photo_path,retired_cleanup_after=clock_timestamp()+interval '24 hours 1 minute',photo_path=upload_path,photo_sha256=${lit(sha(replacement))},photo_size_bytes=upload_size_bytes,photo_verified_at=clock_timestamp(),upload_state='none',upload_path=null,upload_size_bytes=null,upload_expires_at=null where id=${lit(id)};`,true);
  const state=jsonSql(`select json_build_object('active',photo_path,'retired',retired_photo_path,'future',retired_cleanup_after>now()) from public.garments where id=${lit(id)};`);assert.equal(state.active,path);assert.equal(state.retired,extra.retiredPath);assert.equal(state.future,true);
  return 'Server-role fixture attestation only; no implemented verification worker.';
 });
 await check('storage','New candidate blocked until retired cleanup',()=>{
  let failed=false;try{sqlRole('service_role',null,`update public.garments set upload_state='reserved',upload_path=user_id::text||'/'||id::text||'/'||repeat('c',64)||'.png',upload_size_bytes=10,upload_expires_at=clock_timestamp()+interval '10 minutes' where id=${lit(ctx.garments['active-policy-simulation'].id)};`);}catch(e){failed=true;assert.match(String(e.stderr),/23514/);}assert(failed);
 });
 await check('storage','Other-bucket policy control: create scoped fixture policy and upload/download',async()=>{
  const res=await r(await http('/storage/v1/bucket',admin,admin,js('POST',{id:extra.controlBucket,name:extra.controlBucket,public:false,file_size_limit:2097152,allowed_mime_types:['image/png']})));assert([200,201].includes(res.status),JSON.stringify(res));
  sql(`create policy mc_local_control_20261029_run1 on storage.objects for all to authenticated using (bucket_id=${lit(extra.controlBucket)} and name like ${lit(a.id+'/%')}) with check (bucket_id=${lit(extra.controlBucket)} and name like ${lit(a.id+'/%')});`);
  const up=await r(await upload(extra.controlBucket,extra.controlPath,a.jwt));assert([200,201].includes(up.status),JSON.stringify(up));
  const get=await download(extra.controlBucket,extra.controlPath,a.jwt);assert.equal(get.status,200);assert.equal(sha(Buffer.from(await get.arrayBuffer())),sha(image));
 });
} finally {
 save(join(dir,'additional-context.json'),extra);
 const deletionManifest={run:ctx.run,target:API,only_synthetic:true,
  photos:[ctx.photos['orphan-single'],ctx.photos['orphan-many-1'],ctx.photos['orphan-many-2'],extra.retiredPath].map(path=>({bucket:'garment-photos',path})).concat({bucket:extra.controlBucket,path:extra.controlPath}),
  garment_id:ctx.garments['orphan-single'].id,preferences_user_id:a.id,
  protected_photos:[ctx.photos.candidate,extra.activeReplacement],
  no_auth_user_or_bucket_deletion:true};
 save(join(dir,'deletion-manifest.json'),deletionManifest);
 save(join(dir,'additional-results.json'),{checks,worker_verified:false});
 console.log(JSON.stringify({pass:checks.filter(c=>c.status==='PASS').length,fail:checks.filter(c=>c.status==='FAIL').length,deletion_manifest:join(dir,'deletion-manifest.json'),planned_photo_deletions:deletionManifest.photos.length},null,2));
 if(checks.some(c=>c.status==='FAIL'))process.exitCode=1;
}
