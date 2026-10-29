// Deterministic real DB/Storage race integration. No test hooks in the Edge endpoint.
import assert from 'node:assert/strict';
import { readFileSync,existsSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import * as m from '../../build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/index.js';
import { verifyPhoto,VerificationError } from '../functions/verify-garment-photo/core.ts';
import { client } from '../functions/verify-garment-photo/adapter.ts';
import { magickDecoder } from '../functions/verify-garment-photo/image.ts';
import { ROOT,API,guard,http,sql,sqlRole,lit,sha,save } from './integration.mjs';
const dir=join(ROOT,'build/supabase-local/20261029-worker-2');assert(!existsSync(join(dir,'race-results.json')));
const ctx=JSON.parse(readFileSync(join(dir,'http-context-1.private.json'),'utf8'));
const {status}=guard();const admin=status.SERVICE_ROLE_KEY,key=status.PUBLISHABLE_KEY||status.ANON_KEY;
const a=ctx.users.a;const bytes=readFileSync(join(dir,'synthetic.png'));
await m.initializeImageMagick(readFileSync(join(ROOT,'build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/x86/magick.wasm')));
const decode=magickDecoder(m);const api=client({url:API,anonKey:status.ANON_KEY,serviceKey:admin});
await api.authenticate(new Request(API,{headers:{Authorization:`Bearer ${a.jwt}`}}));
const checks=[],fixtures=[];
const js=(method,body)=>({method,headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
const row=id=>JSON.parse(sql(`select row_to_json(g) from public.garments g where id=${lit(id)};`));
async function check(name,fn){try{const detail=await fn();checks.push({name,status:'PASS',detail});console.log('PASS',name);}catch(e){checks.push({name,status:'FAIL',detail:String(e.stderr||e.message)});console.log('FAIL',name,String(e.stderr||e.message));}}
async function fixture(label){const id=randomUUID(),path=`${a.id}/${id}/${sha(bytes)}.png`;
 let res=await http('/rest/v1/garments',key,a.jwt,js('POST',{id,user_id:a.id,local_id:`worker-race-${label}`,name:`Synthetic race ${label}`,category:'tops',image_width:1,image_height:1,image_mime_type:'image/png'}));assert.equal(res.status,201);
 sqlRole('service_role',null,`update public.garments set upload_path=${lit(path)},upload_state='reserved',upload_size_bytes=${bytes.length},upload_expires_at=clock_timestamp()+interval '10 minutes' where id=${lit(id)};`,true);
 res=await http(`/storage/v1/object/garment-photos/${path}`,key,a.jwt,{method:'POST',headers:{'Content-Type':'image/png','x-upsert':'false'},body:bytes});assert([200,201].includes(res.status));
 res=await http(`/rest/v1/garments?id=eq.${id}`,key,a.jwt,js('PATCH',{upload_state:'client_confirmed'}));assert.equal(res.status,204);
 const f={id,path,label};fixtures.push(f);return f;
}
async function race(label,code,mutation){const f=await fixture(label);const p=api.ports(a.id,a.jwt,async(b,mime)=>{const info=await decode(b,mime);await mutation(f);return info;});
 await assert.rejects(()=>verifyPhoto(f.id,f.path,a.id,p),e=>e instanceof VerificationError&&e.code===code);
 const saved=row(f.id);assert.equal(saved.photo_state,'pending');assert.equal(saved.photo_path,null);return {error:code,ready:false,upload_state:saved.upload_state};
}
try {
 await check('Actual Storage object replaced between validation reads',()=>race('replace','object_changed',async f=>{
  const replacement=readFileSync(join(dir,'synthetic.jpg'));
  const res=await http(`/storage/v1/object/garment-photos/${f.path}`,admin,admin,{method:'PUT',headers:{'Content-Type':'image/jpeg'},body:replacement});assert.equal(res.status,200);
 }));
 await check('Actual Storage candidate deleted during verification',()=>race('delete','not_found',async f=>{
  // This path was created above in this test, never a pre-existing wardrobe photo.
  assert(f.path.startsWith(`${a.id}/${f.id}/`));const res=await http(`/storage/v1/object/garment-photos/${f.path}`,admin,admin,{method:'DELETE'});assert.equal(res.status,200);
 }));
 await check('Actual reservation replacement cannot be overwritten by stale worker',()=>race('reservation','revision_conflict',async f=>{
  const next=`${a.id}/${f.id}/${'b'.repeat(64)}.png`;
  sqlRole('service_role',null,`update public.garments set upload_state='none',upload_path=null,upload_size_bytes=null,upload_expires_at=null where id=${lit(f.id)};
   update public.garments set upload_state='reserved',upload_path=${lit(next)},upload_size_bytes=10,upload_expires_at=clock_timestamp()+interval '10 minutes' where id=${lit(f.id)};`,true);
 }));
 await check('Actual metadata revision conflict blocks stale attestation',()=>race('metadata','revision_conflict',async f=>{
  const res=await http(`/rest/v1/garments?id=eq.${f.id}`,key,a.jwt,js('PATCH',{name:'Concurrent edit preserved'}));assert.equal(res.status,204);
 }));
 await check('Real elapsed lease recovers through the Edge HTTP endpoint',async()=>{
  const f=ctx.stale_fixture;const saved=row(f.id);const age=Date.now()-Date.parse(saved.server_updated_at);
  if(age<61000)await new Promise(r=>setTimeout(r,61000-age));
  const res=await http('/functions/v1/verify-garment-photo',key,a.jwt,js('POST',{garment_id:f.id,upload_path:f.path}));const body=await res.json();assert.equal(res.status,200,JSON.stringify(body));assert.equal(row(f.id).photo_state,'ready');return {http:200,lease_expiry:'real elapsed time; no timestamp override'};
 });
}finally{save(join(dir,'race-fixtures.json'),fixtures);save(join(dir,'race-results.json'),{checks,mode:'production core+adapter+decoder with real local DB/Storage; deterministic mutations injected at decoder boundary',summary:{pass:checks.filter(c=>c.status==='PASS').length,fail:checks.filter(c=>c.status==='FAIL').length}});console.log(JSON.stringify({pass:checks.filter(c=>c.status==='PASS').length,fail:checks.filter(c=>c.status==='FAIL').length}));if(checks.some(c=>c.status==='FAIL'))process.exitCode=1;}
