// Real Edge Function HTTP tests on the already-running loopback Supabase only.
import assert from 'node:assert/strict';
import { readFileSync,existsSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID,randomBytes } from 'node:crypto';
import { ROOT,API,guard,http,sql,sqlRole,lit,sha,save } from './integration.mjs';
const base=join(ROOT,'build/supabase-local/20261029-worker-2');
const attempt=process.argv[2]||'1';assert(/^[0-9]+$/.test(attempt));
assert(!existsSync(join(base,`http-results-${attempt}.json`)));
const {status}=guard();const key=status.PUBLISHABLE_KEY||status.ANON_KEY,admin=status.SERVICE_ROLE_KEY;
const run=`20261029-worker-http-${attempt}`;const ctx={run,users:{},fixtures:[]};const checks=[];
async function check(name,fn,expected_failure=false){try{const detail=await fn();checks.push({name,status:'PASS',expected_failure,...(detail?{detail}:{})});console.log(`PASS ${name}`);return true;}catch(e){checks.push({name,status:'FAIL',expected_failure,detail:String(e.stderr||e.message)});console.log(`FAIL ${name}: ${String(e.stderr||e.message)}`);return false;}}
const req=(path,jwt,init={})=>http(path,key,jwt,init);
const js=(method,body)=>({method,headers:{'Content-Type':'application/json',Prefer:'return=representation'},body:JSON.stringify(body)});
async function value(res){const text=await res.text();let data;try{data=JSON.parse(text);}catch{data=text;}return {http:res.status,data};}
function ok(r,statuses=[200]){assert(statuses.includes(r.http),JSON.stringify(r));}
const row=id=>JSON.parse(sql(`select row_to_json(g) from public.garments g where id=${lit(id)};`));
async function reqPromise(f,jwt,patch){return req('/functions/v1/verify-garment-photo',jwt,js('POST',{garment_id:f.id,upload_path:f.path,...patch}));}
// value accepts a Response; keep all error reporting free of Authorization headers.
async function call(f,jwt=ctx.users.a.jwt,patch={}){return value(await reqPromise(f,jwt,patch));}
const bytes=ext=>Buffer.from(readFileSync(join(base,`synthetic.${ext}`)));
async function fixture(label,options={}) {
 const id=randomUUID(),u=ctx.users.a,ext=options.ext||'png',body=options.bytes||bytes('png');
 const hash=options.hash||sha(body),path=`${u.id}/${id}/${hash}.${ext}`;
 const insert=await value(await req('/rest/v1/garments',u.jwt,js('POST',{id,user_id:u.id,local_id:`${run}-${label}`,name:`Synthetic ${label}`,category:'tops',image_mime_type:ext==='jpg'?'image/jpeg':`image/${ext}`,image_width:1,image_height:1})));ok(insert,[201]);
 const seconds=options.seconds||600;
 assert.equal(sqlRole('service_role',null,`with c as(update public.garments set upload_path=${lit(path)},upload_state='reserved',upload_size_bytes=${options.size||body.length},upload_expires_at=clock_timestamp()+interval '${seconds} seconds' where id=${lit(id)} and user_id=${lit(u.id)} and revision=1 returning id)select count(*) from c;`,true),'1');
 if(options.upload!==false){const up=await value(await req(`/storage/v1/object/garment-photos/${path}`,u.jwt,{method:'POST',headers:{'Content-Type':ext==='jpg'?'image/jpeg':`image/${ext}`,'x-upsert':'false'},body}));ok(up,[200,201]);}
 if(options.confirm!==false){const ack=await value(await req(`/rest/v1/garments?id=eq.${id}&revision=eq.2`,u.jwt,js('PATCH',{upload_state:'client_confirmed'})));ok(ack);assert.equal(ack.data.length,1);}
 const f={id,path,label,hash,size:body.length,ext};ctx.fixtures.push(f);return f;
}
try {
 for(const name of ['a','b']){
  const password=randomBytes(24).toString('base64url')+'Aa1!';const email=`${run}-${name}-${randomUUID()}@example.test`;
  const created=await value(await http('/auth/v1/admin/users',admin,admin,js('POST',{email,password,email_confirm:true,user_metadata:{test_run:run,synthetic:true}})));ok(created,[200,201]);
  const logged=await value(await req('/auth/v1/token?grant_type=password',null,js('POST',{email,password})));ok(logged);
  ctx.users[name]={id:created.data.id,jwt:logged.data.access_token};
 }
 ctx.jwt_algorithm=JSON.parse(Buffer.from(ctx.users.a.jwt.split('.')[0],'base64url').toString()).alg;
 for(const ext of ['jpg','png','webp']){
  const f=await fixture(`valid-${ext}`,{ext,bytes:bytes(ext)});
  const passed=await check(`Edge ${ext.toUpperCase()} actual decode + ready`,async()=>{const res=await call(f);ok(res);assert.equal(res.data.status,'ready');
   const saved=row(f.id);assert.equal(saved.photo_state,'ready');assert.equal(saved.photo_sha256,f.hash);assert.equal(saved.photo_size_bytes,f.size);assert.equal(saved.image_width,4);assert.equal(saved.image_height,3);assert.equal(saved.upload_path,null);assert(saved.photo_verified_at);return res;});
  if(!passed)throw new Error('Normal-image smoke test failed; stop before creating further fixtures');
 }
 const good=ctx.fixtures[0];
 await check('Unauthenticated request denied',async()=>{const res=await call(good,null);assert([400,401].includes(res.http));return res;},true);
 await check('Other user cannot verify owner photo',async()=>{const res=await call(good,ctx.users.b.jwt);ok(res,[404]);assert.equal(res.data.error,'not_found_or_not_owned');return res;},true);
 await check('Forged JWT signature rejected',async()=>{const parts=ctx.users.a.jwt.split('.');const payload=JSON.parse(Buffer.from(parts[1],'base64url').toString());payload.sub=ctx.users.b.id;parts[1]=Buffer.from(JSON.stringify(payload)).toString('base64url');const res=await call(good,parts.join('.'));ok(res,[401]);return res;},true);
 await check('service_role JWT is not accepted as user identity',async()=>{const res=await call(good,admin);ok(res,[401]);return res;},true);
 await check('Client-supplied bucket/hash/ready fields rejected',async()=>{const res=await call(good,ctx.users.a.jwt,{bucket:'other',photo_state:'ready',sha256:'forged'});ok(res,[400]);return res;},true);
 await check('Client cannot set ready through Data API',async()=>{const res=await value(await req(`/rest/v1/garments?id=eq.${good.id}`,ctx.users.a.jwt,js('PATCH',{photo_state:'ready'})));ok(res,[403]);assert.equal(res.data.code,'42501');return {http:res.http,code:res.data.code};},true);
 await check('Completed duplicate request is idempotent',async()=>{const before=row(good.id).revision;const res=await call(good);ok(res);assert.equal(res.data.already_verified,true);assert.equal(row(good.id).revision,before);return res;});
 for(const [label,options,code] of [
  ['size-mismatch',{size:bytes('png').length+7},'size_mismatch'],
  ['hash-mismatch',{hash:'a'.repeat(64)},'hash_mismatch'],
  ['mime-mismatch',{ext:'jpg',bytes:bytes('png')},'mime_mismatch'],
  ['missing-object',{upload:false},'not_found'],
  ['corrupt-image',{bytes:Buffer.concat([bytes('png').subarray(0,-1),Buffer.from([1])])},'invalid_image'],
 ]){
  const f=await fixture(label,options);
  await check(`Reject ${label} without ready`,async()=>{const res=await call(f);ok(res,code==='not_found'?[404]:[422]);assert.equal(res.data.error,code);const saved=row(f.id);assert.equal(saved.photo_state,'pending');assert.equal(saved.photo_path,null);assert.equal(saved.upload_error_code,code);assert.equal(saved.upload_state,'failed');return res;},true);
  if(label==='size-mismatch')await check('Terminal failure retry keeps revision unchanged',async()=>{const rev=row(f.id).revision;const res=await call(f);ok(res,[422]);assert.equal(row(f.id).revision,rev);});
  if(label==='missing-object'){
   await check('Missing object can safely retry after object becomes available',async()=>{
    // Only this new fixture is populated by server privilege, since the client slot is now failed.
    const up=await value(await http(`/storage/v1/object/garment-photos/${f.path}`,admin,admin,{method:'POST',headers:{'Content-Type':'image/png','x-upsert':'false'},body:bytes('png')}));ok(up,[200,201]);
    const res=await call(f);ok(res);assert.equal(row(f.id).photo_state,'ready');return res;
   });
  }
 }
 const expires=await fixture('expired',{seconds:1});await new Promise(r=>setTimeout(r,1200));
 await check('Expired reservation rejected',async()=>{const res=await call(expires);ok(res,[409]);assert.equal(res.data.error,'expired');assert.equal(row(expires.id).photo_state,'pending');return res;},true);
 const unconfirmed=await fixture('not-confirmed',{confirm:false});
 await check('reserved upload cannot bypass client_confirmed',async()=>{const res=await call(unconfirmed);ok(res,[409]);assert.equal(res.data.error,'client_confirmation_required');assert.equal(row(unconfirmed.id).photo_state,'pending');return res;},true);
 const pending=await fixture('bad-path');
 await check('Exact server reservation path required',async()=>{const res=await call({...pending,path:pending.path.replace('.png','.webp')});ok(res,[409]);assert.equal(res.data.error,'reservation_mismatch');assert.equal(row(pending.id).upload_state,'client_confirmed');return res;},true);
 const concurrent=await fixture('concurrent');
 await check('Concurrent Edge invocations commit a single attestation',async()=>{
  const before=row(concurrent.id).revision;const responses=await Promise.all(Array.from({length:8},()=>call(concurrent)));
  for(const res of responses){assert([200,409].includes(res.http),JSON.stringify(res));if(res.http===409)assert(['verification_in_progress','revision_conflict'].includes(res.data.error));}
  assert(responses.some(r=>r.http===200));const saved=row(concurrent.id);assert.equal(saved.photo_state,'ready');assert.equal(saved.revision,before+2);
  return {responses:responses.map(v=>({http:v.http,...v.data})),revision_increments:2};
 });
 const stale=await fixture('stale-lease');sqlRole('service_role',null,`update public.garments set upload_state='checking' where id=${lit(stale.id)};`,true);
 await check('Fresh checking lease reports retryable in-progress',async()=>{const res=await call(stale);ok(res,[409]);assert.equal(res.data.error,'verification_in_progress');assert.equal(res.data.retryable,true);return res;},true);
 // Real lease expiry is tested by waiting, without changing protected timestamps in SQL.
 ctx.stale_fixture=stale;
} catch(e){checks.push({name:'HTTP suite prerequisites',status:'FAIL',expected_failure:false,detail:String(e.stderr||e.message)});console.log('Suite stopped:',String(e.stderr||e.message));}
finally {
 save(join(base,`http-context-${attempt}.private.json`),ctx);
 save(join(base,`http-results-${attempt}.json`),{run,checks,jwt_algorithm:ctx.jwt_algorithm,summary:{pass:checks.filter(c=>c.status==='PASS').length,fail:checks.filter(c=>c.status==='FAIL').length}});
 console.log(JSON.stringify({pass:checks.filter(c=>c.status==='PASS').length,fail:checks.filter(c=>c.status==='FAIL').length,jwt_algorithm:ctx.jwt_algorithm},null,2));
 if(checks.some(c=>c.status==='FAIL'))process.exitCode=1;
}
