// DESTRUCTIVE ONLY TO THE REVIEWED SYNTHETIC MANIFEST. Requires explicit approval.
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT,API,guard,http,sql,jsonSql,sqlRole,lit,sha,save,protectedHashes } from './integration.mjs';
const dir=join(ROOT,'build/supabase-local/20261029-run1');
assert.equal(process.argv[2],'--approved-synthetic-manifest','Explicit approval argument required');
assert(!existsSync(join(dir,'deletion-results.json')),'Never overwrite a test run');
const {status}=guard();const key=status.PUBLISHABLE_KEY||status.ANON_KEY;
const ctx=JSON.parse(readFileSync(join(dir,'context.private.json'),'utf8'));
const extra=JSON.parse(readFileSync(join(dir,'additional-context.json'),'utf8'));
const manifest=JSON.parse(readFileSync(join(dir,'deletion-manifest.json'),'utf8'));
assert.equal(manifest.run,'20261029-run1');assert.equal(manifest.target,API);
assert.equal(manifest.photos.length,5);assert.equal(manifest.no_auth_user_or_bucket_deletion,true);
const a=ctx.users.a,b=ctx.users.b;
assert.equal(manifest.garment_id,ctx.garments['orphan-single'].id);assert.equal(manifest.preferences_user_id,a.id);
const allowed=new Set(manifest.photos.map(v=>`${v.bucket}/${v.path}`));
assert.equal(allowed.size,5);for(const row of manifest.photos)assert(row.path.startsWith(a.id+'/'));
assert.equal(sql(`select count(*) from auth.users where id in (${lit(a.id)},${lit(b.id)}) and raw_user_meta_data->>'test_run'='20261029-run1';`),'2');
assert.equal(sql(`select count(*) from public.garments where id=${lit(manifest.garment_id)} and user_id=${lit(a.id)} and local_id='20261029-run1-orphan-single';`),'1');
const checks=[];
async function check(group,name,fn){try{const detail=await fn();checks.push({group,name,status:'PASS',...(detail?{detail}:{})});console.log(`PASS [${group}] ${name}`);}catch(e){checks.push({group,name,status:'FAIL',detail:String(e.stderr||e.message)});console.log(`FAIL [${group}] ${name}: ${String(e.stderr||e.message)}`);}}
const req=(path,jwt,init={})=>http(path,key,jwt,init);
async function r(res){const text=await res.text();let data;try{data=JSON.parse(text);}catch{data=text;}return {status:res.status,data};}
async function bytes(bucket,path){const res=await req(`/storage/v1/object/authenticated/${bucket}/${path}`,a.jwt);assert.equal(res.status,200);return Buffer.from(await res.arrayBuffer());}
async function removeOne(bucket,path,jwt){assert(allowed.has(`${bucket}/${path}`)||[ctx.photos.candidate,extra.activeReplacement].includes(path),'Path outside approved manifest');return r(await req(`/storage/v1/object/${bucket}/${path}`,jwt,{method:'DELETE'}));}
function gone(bucket,path){assert.equal(sql(`select count(*) from storage.objects where bucket_id=${lit(bucket)} and name=${lit(path)};`),'0');}
async function preserved(path,jwt=a.jwt){const before=sha(await bytes('garment-photos',path));const res=await removeOne('garment-photos',path,jwt);assert(res.status<500,JSON.stringify(res));assert.equal(sha(await bytes('garment-photos',path)),before);return {http:res.status,response:res.data,bytes_preserved:true};}
try {
 await check('rls','Cross-user garment DELETE affects 0 and preserves row',async()=>{
  const id=ctx.garments.main.id;const res=await r(await req(`/rest/v1/garments?id=eq.${id}`,b.jwt,{method:'DELETE',headers:{Prefer:'return=representation'}}));assert.equal(res.status,200);assert.deepEqual(res.data,[]);assert.equal(sqlRole('authenticated',a.id,`select count(*) from public.garments where id=${lit(id)};`),'1');
 });
 await check('rls','Cross-user preferences DELETE affects 0 and preserves row',async()=>{
  const res=await r(await req(`/rest/v1/user_preferences?user_id=eq.${a.id}`,b.jwt,{method:'DELETE',headers:{Prefer:'return=representation'}}));assert.equal(res.status,200);assert.deepEqual(res.data,[]);assert.equal(sqlRole('authenticated',a.id,'select count(*) from public.user_preferences;'),'1');
 });
 await check('storage','Acknowledged candidate cannot be deleted',()=>preserved(ctx.photos.candidate));
 await check('storage','Active photo cannot be deleted (policy simulation fixture)',()=>preserved(extra.activeReplacement));
 await check('storage','Retired photo protected during grace',()=>preserved(extra.retiredPath));
 await check('storage','Foreign single DELETE preserves orphan bytes',()=>preserved(ctx.photos['orphan-single'],b.jwt));
 const many=[ctx.photos['orphan-many-1'],ctx.photos['orphan-many-2']];
 await check('storage','Foreign multi DELETE preserves both orphan objects',async()=>{
  const hashes=await Promise.all(many.map(async p=>sha(await bytes('garment-photos',p))));
  const res=await r(await req('/storage/v1/object/garment-photos',b.jwt,{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefixes:many})}));assert(res.status<500);
  assert.deepEqual(await Promise.all(many.map(async p=>sha(await bytes('garment-photos',p)))),hashes);return {http:res.status,response:res.data,bytes_preserved:true};
 });
 await check('rls','Owner garment DELETE completes CRUD; B row retained',async()=>{
  const res=await r(await req(`/rest/v1/garments?id=eq.${manifest.garment_id}`,a.jwt,{method:'DELETE',headers:{Prefer:'return=representation'}}));assert.equal(res.status,200);assert.equal(res.data.length,1);assert.equal(res.data[0].id,manifest.garment_id);
  assert.equal(sql(`select count(*) from public.garments where id=${lit(manifest.garment_id)};`),'0');assert.equal(sqlRole('authenticated',b.id,`select count(*) from public.garments where id=${lit(ctx.garments['b-main'].id)};`),'1');
 });
 await check('storage','Owner single orphan DELETE succeeds after garment row deletion',async()=>{
  const res=await removeOne('garment-photos',ctx.photos['orphan-single'],a.jwt);assert(res.status>=200&&res.status<300,JSON.stringify(res));gone('garment-photos',ctx.photos['orphan-single']);return {http:res.status};
 });
 await check('storage','Owner multi orphan DELETE succeeds',async()=>{
  for(const p of many)assert(allowed.has('garment-photos/'+p));
  const res=await r(await req('/storage/v1/object/garment-photos',a.jwt,{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefixes:many})}));assert(res.status>=200&&res.status<300,JSON.stringify(res));for(const p of many)gone('garment-photos',p);return {http:res.status};
 });
 await check('storage','Retired grace expiry allows owner cleanup (clock fixture)',async()=>{
  const id=ctx.garments['active-policy-simulation'].id;
  assert.equal(sqlRole('service_role',null,`with c as(update public.garments set retired_cleanup_after=clock_timestamp()-interval '1 second' where id=${lit(id)} and user_id=${lit(a.id)} and retired_photo_path=${lit(extra.retiredPath)} and revision=(select revision from public.garments where id=${lit(id)}) returning id)select count(*) from c;`,true),'1');
  const res=await removeOne('garment-photos',extra.retiredPath,a.jwt);assert(res.status>=200&&res.status<300,JSON.stringify(res));gone('garment-photos',extra.retiredPath);
  assert.equal(sqlRole('service_role',null,`with c as(update public.garments set retired_photo_path=null,retired_cleanup_after=null where id=${lit(id)} and user_id=${lit(a.id)} and revision=(select revision from public.garments where id=${lit(id)}) returning id)select count(*) from c;`,true),'1');
  return {http:res.status,time_advanced_by_fixture:true};
 });
 await check('storage','Other bucket DELETE unaffected by garment guards',async()=>{
  const res=await removeOne(extra.controlBucket,extra.controlPath,a.jwt);assert(res.status>=200&&res.status<300,JSON.stringify(res));gone(extra.controlBucket,extra.controlPath);return {http:res.status};
 });
 await check('rls','Owner preferences DELETE completes CRUD; B preferences retained',async()=>{
  const res=await r(await req(`/rest/v1/user_preferences?user_id=eq.${a.id}`,a.jwt,{method:'DELETE',headers:{Prefer:'return=representation'}}));assert.equal(res.status,200);assert.equal(res.data.length,1);
  assert.equal(sqlRole('authenticated',a.id,'select count(*) from public.user_preferences;'),'0');assert.equal(sqlRole('authenticated',b.id,'select count(*) from public.user_preferences;'),'1');
 });
 await check('storage','Protected active and acknowledged photos remain byte-identical',async()=>{
  for(const path of manifest.protected_photos){assert.equal(sha(await bytes('garment-photos',path)),path.split('/').at(-1).split('.')[0]);}
 });
} finally {
 const baseline=JSON.parse(readFileSync(join(dir,'protected-before.json'),'utf8'));const unchanged=JSON.stringify(protectedHashes())===JSON.stringify(baseline);
 const finalState=jsonSql(`select json_build_object('auth_users',(select count(*) from auth.users),'garments',(select count(*) from public.garments),'preferences',(select count(*) from public.user_preferences),'objects',(select count(*) from storage.objects),'buckets',(select count(*) from storage.buckets));`);
 save(join(dir,'deletion-results.json'),{checks,finalState,protected_files_unchanged:unchanged,worker_verified:false});
 console.log(JSON.stringify({pass:checks.filter(c=>c.status==='PASS').length,fail:checks.filter(c=>c.status==='FAIL').length,finalState,protected_files_unchanged:unchanged},null,2));
 if(checks.some(c=>c.status==='FAIL')||!unchanged)process.exitCode=1;
}
