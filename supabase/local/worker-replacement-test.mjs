// Exercise replacement of THIS worker run's verified photos, never prior-run data.
import assert from 'node:assert/strict';
import { readFileSync,existsSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT,guard,http,sql,sqlRole,lit,sha,save } from './integration.mjs';
const dir=join(ROOT,'build/supabase-local/20261029-worker-2');assert(!existsSync(join(dir,'replacement-results.json')));
const ctx=JSON.parse(readFileSync(join(dir,'http-context-1.private.json'),'utf8'));
const {status}=guard();const key=status.PUBLISHABLE_KEY||status.ANON_KEY,u=ctx.users.a;
const checks=[];const row=id=>JSON.parse(sql(`select row_to_json(g) from public.garments g where id=${lit(id)};`));
const js=(method,body)=>({method,headers:{'Content-Type':'application/json',Prefer:'return=representation'},body:JSON.stringify(body)});
async function check(name,fn){try{const detail=await fn();checks.push({name,status:'PASS',detail});console.log('PASS',name);}catch(e){checks.push({name,status:'FAIL',detail:String(e.stderr||e.message)});console.log('FAIL',name,String(e.stderr||e.message));}}
async function candidate(f,ext,hash){const bytes=readFileSync(join(dir,`synthetic.${ext}`));const path=`${u.id}/${f.id}/${hash||sha(bytes)}.${ext}`;
 assert(f.label.startsWith('valid-')&&ctx.fixtures.some(v=>v.id===f.id));
 const rev=row(f.id).revision;
 assert.equal(sqlRole('service_role',null,`with c as(update public.garments set upload_path=${lit(path)},upload_size_bytes=${bytes.length},upload_state='reserved',upload_expires_at=clock_timestamp()+interval '10 minutes' where id=${lit(f.id)} and user_id=${lit(u.id)} and revision=${rev} returning id)select count(*) from c;`,true),'1');
 let res=await http(`/storage/v1/object/garment-photos/${path}`,key,u.jwt,{method:'POST',headers:{'Content-Type':`image/${ext}`,'x-upsert':'false'},body:bytes});assert([200,201].includes(res.status));
 res=await http(`/rest/v1/garments?id=eq.${f.id}`,key,u.jwt,js('PATCH',{upload_state:'client_confirmed'}));assert.equal(res.status,200);
 return {path,bytes};
}
try {
 await check('Real worker replacement changes MIME and retires old verified photo',async()=>{
  const f=ctx.fixtures.find(v=>v.label==='valid-png'),before=row(f.id),c=await candidate(f,'webp');
  const res=await http('/functions/v1/verify-garment-photo',key,u.jwt,js('POST',{garment_id:f.id,upload_path:c.path}));const body=await res.json();assert.equal(res.status,200,JSON.stringify(body));
  const after=row(f.id);assert.equal(after.photo_path,c.path);assert.equal(after.photo_sha256,sha(c.bytes));assert.equal(after.image_mime_type,'image/webp');assert.equal(after.retired_photo_path,before.photo_path);assert(Date.parse(after.retired_cleanup_after)>Date.now()+24*3600000);
  const old=await http(`/storage/v1/object/authenticated/garment-photos/${before.photo_path}`,key,u.jwt);assert.equal(old.status,200);assert.equal(sha(Buffer.from(await old.arrayBuffer())),before.photo_sha256);return {http:200,retired_old_photo_preserved:true};
 });
 await check('Failed replacement preserves previous real attestation',async()=>{
  const f=ctx.fixtures.find(v=>v.label==='valid-webp'),before=row(f.id),c=await candidate(f,'png','c'.repeat(64));
  const res=await http('/functions/v1/verify-garment-photo',key,u.jwt,js('POST',{garment_id:f.id,upload_path:c.path}));const body=await res.json();assert.equal(res.status,422);assert.equal(body.error,'hash_mismatch');
  const after=row(f.id);for(const k of ['photo_state','photo_path','photo_sha256','photo_size_bytes','photo_verified_at','image_mime_type'])assert.equal(after[k],before[k]);assert.equal(after.upload_state,'failed');return {http:422,error:'hash_mismatch',old_ready_preserved:true,new_candidate_activated:false};
 });
}finally{save(join(dir,'replacement-results.json'),{checks,summary:{pass:checks.filter(c=>c.status==='PASS').length,fail:checks.filter(c=>c.status==='FAIL').length}});console.log(JSON.stringify({pass:checks.filter(c=>c.status==='PASS').length,fail:checks.filter(c=>c.status==='FAIL').length}));if(checks.some(c=>c.status==='FAIL'))process.exitCode=1;}
