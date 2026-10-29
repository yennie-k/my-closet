// Real local SQL + JWT HTTP tests. Original draft/test files remain unchanged.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID, randomBytes } from 'node:crypto';
import { deflateSync } from 'node:zlib';
import { ROOT, LOCAL, DB, API, guard, docker, sql, jsonSql, sqlRole, lit, sha, save, http, protectedHashes } from './integration.mjs';

const RUN='20261029-run1';
const dir=join(ROOT,'build/supabase-local',RUN);
assert(existsSync(join(dir,'prepare-results.json')));
assert(!existsSync(join(dir,'exercise-results.json')), 'Use a new test run; never overwrite results');
const {status}=guard();
const key=status.PUBLISHABLE_KEY||status.ANON_KEY;
const admin=status.SERVICE_ROLE_KEY;
const checks=[];
const ctx={run:RUN,target:API,garments:{},photos:{},users:{}};
async function check(group,name,fn) {
 try {const detail=await fn();checks.push({group,name,status:'PASS',...(detail?{detail}: {})});console.log(`PASS [${group}] ${name}`);return true;}
 catch(e) {const detail=String(e.stderr||e.message);checks.push({group,name,status:'FAIL',detail});console.log(`FAIL [${group}] ${name}: ${detail}`);return false;}
}
const req=(path,jwt,init={})=>http(path,key,jwt,init);
async function response(res) {const text=await res.text();let data;try{data=JSON.parse(text);}catch{data=text;}return {status:res.status,data};}
function expectStatus(r,allowed) {assert(allowed.includes(r.status),`HTTP ${r.status}: ${JSON.stringify(r.data)}`);}
const json=(method,body)=>({method,headers:{'Content-Type':'application/json',Prefer:'return=representation'},body:JSON.stringify(body)});
function roleJson(role,uid,text) {return JSON.parse(sqlRole(role,uid,text).split('\n').at(-1));}
function expectSqlError(role,uid,text,code) {let failed=false;try{sqlRole(role,uid,text);}catch(e){failed=true;assert.match(String(e.stderr),new RegExp(code));}assert(failed,'SQL unexpectedly succeeded');}
const q=(id,extra='')=>`/rest/v1/garments?id=eq.${id}${extra}`;
const claims=(uid)=>`set local request.jwt.claims=${lit(JSON.stringify({sub:uid,role:'authenticated',is_anonymous:false}))};`;

// Generated PNGs: original code, no downloaded images and no real wardrobe photos.
function crc32(bytes) {let crc=0xffffffff;for(const b of bytes){crc^=b;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return (crc^0xffffffff)>>>0;}
function chunk(name,data) {const type=Buffer.from(name);const length=Buffer.alloc(4);length.writeUInt32BE(data.length);const crc=Buffer.alloc(4);crc.writeUInt32BE(crc32(Buffer.concat([type,data])));return Buffer.concat([length,type,data,crc]);}
function png(seed) {const h=Buffer.alloc(13);h.writeUInt32BE(1,0);h.writeUInt32BE(1,4);h[8]=8;h[9]=2;return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',h),chunk('IDAT',deflateSync(Buffer.from([0,seed,128,255-seed]))),chunk('IEND',Buffer.alloc(0))]);}
const image=png(42), otherImage=png(99);
writeFileSync(join(dir,'synthetic-1x1.png'),image,{flag:'wx'});
function object(path) {return `/storage/v1/object/garment-photos/${path}`;}
function download(path) {return `/storage/v1/object/authenticated/garment-photos/${path}`;}
async function upload(path,jwt,data=image,upsert=false) {return response(await req(object(path),jwt,{method:'POST',headers:{'Content-Type':'image/png','x-upsert':String(upsert)},body:data}));}
async function getImage(path,jwt=ctx.users.a.jwt) {const res=await req(download(path),jwt);assert.equal(res.status,200,`download HTTP ${res.status}`);return Buffer.from(await res.arrayBuffer());}
async function reserve(id,uid,bytes=image,seconds=600) {
 const path=`${uid}/${id}/${sha(bytes)}.png`;
 const n=sqlRole('service_role',null,`with changed as (update public.garments set upload_path=${lit(path)},upload_state='reserved',upload_size_bytes=${bytes.length},upload_expires_at=clock_timestamp()+interval '${seconds} seconds' where id=${lit(id)} and user_id=${lit(uid)} and revision=(select revision from public.garments where id=${lit(id)}) returning id) select count(*) from changed;`,true);
 assert.equal(n,'1');return path;
}
async function createGarment(label,owner='a') {
 const u=ctx.users[owner]; const id=randomUUID();
 const r=await response(await req('/rest/v1/garments',u.jwt,json('POST',{id,user_id:u.id,local_id:`${RUN}-${label}`,name:`Synthetic ${label}`,category:'tops',subtype:'사용자 지정 종류',
  image_mime_type:'image/png',image_width:1,image_height:1,material:'면 80% + 린넨 20%',materials:['면','린넨','사용자 소재'],primary_color:'카키',primary_color_hex:'#77794A',additional_colors:['민트'],additional_color_details:[{name:'민트',hex:'#A6D9C5'}],thickness:'thick',thickness_level:4} )));
 expectStatus(r,[201]);assert.equal(r.data[0].id,id);ctx.garments[label]={id,owner};return id;
}
async function createUsers() {
 for(const owner of ['a','b']) {
  const password=randomBytes(24).toString('base64url')+'Aa1!';
  const email=`${RUN}-${owner}-${randomUUID()}@example.test`;
  const r=await response(await http('/auth/v1/admin/users',admin,admin,json('POST',{email,password,email_confirm:true,user_metadata:{test_run:RUN,synthetic:true}})));
  expectStatus(r,[200,201]);const id=r.data.id;
  const login=await response(await req('/auth/v1/token?grant_type=password',null,json('POST',{email,password})));
  expectStatus(login,[200]);assert.equal(login.data.user.id,id);
  ctx.users[owner]={id,jwt:login.data.access_token};
 }
}

try {
 await createUsers();
 await check('contracts','original DB security SQL (transaction rollback)',()=>{
  const source=readFileSync(join(ROOT,'supabase/tests/01_security_contract.draft.sql'),'utf8');
  const output=sql(`set my_closet_test.allow_fixtures='yes';set my_closet_test.user_a=${lit(ctx.users.a.id)};set my_closet_test.user_b=${lit(ctx.users.b.id)};\n${source}`);
  writeFileSync(join(dir,'01-security-contract.log'),output,{flag:'wx'});
  assert.equal(sql('select count(*) from public.garments;'),'0');
  return 'Original assertions executed; no garment fixtures committed. Ready transition here is role simulation only.';
 });
 sql("notify pgrst,'reload schema';");
 await check('rls','A garment INSERT and complete v2 field roundtrip',async()=>{
  const id=await createGarment('main');const r=await response(await req(q(id),ctx.users.a.jwt));expectStatus(r,[200]);
  assert.equal(r.data.length,1);assert.deepEqual(r.data[0].materials,['면','린넨','사용자 소재']);assert.equal(r.data[0].thickness_level,4);assert.equal(r.data[0].additional_color_details[0].hex,'#A6D9C5');
 });
 await check('rls','B garment INSERT and own SELECT',async()=>{
  const id=await createGarment('b-main','b');const r=await response(await req(q(id),ctx.users.b.jwt));expectStatus(r,[200]);assert.equal(r.data.length,1);
 });
 const a=ctx.users.a,b=ctx.users.b,id=ctx.garments.main.id,bid=ctx.garments['b-main'].id;
 await check('rls','A cannot SELECT B garment',async()=>{const r=await response(await req(q(bid),a.jwt));expectStatus(r,[200]);assert.deepEqual(r.data,[]);});
 await check('rls','B cannot SELECT A garment',async()=>{const r=await response(await req(q(id),b.jwt));expectStatus(r,[200]);assert.deepEqual(r.data,[]);});
 await check('rls','A cannot UPDATE B garment (0 rows)',async()=>{const r=await response(await req(q(bid),a.jwt,json('PATCH',{name:'forbidden'})));expectStatus(r,[200]);assert.deepEqual(r.data,[]);});
 await check('rls','Forged user_id INSERT rejected by RLS',async()=>{const r=await response(await req('/rest/v1/garments',a.jwt,json('POST',{user_id:b.id,local_id:'forged',name:'forged',category:'tops',image_width:1,image_height:1})));expectStatus(r,[403]);assert.equal(r.data.code,'42501');});
 await check('rls','user_id UPDATE rejected by column ACL',async()=>{const r=await response(await req(q(id),a.jwt,json('PATCH',{user_id:b.id})));expectStatus(r,[403]);assert.equal(r.data.code,'42501');});
 await check('rls','anon garment SELECT rejected',async()=>{const r=await response(await req('/rest/v1/garments',null));expectStatus(r,[401,403]);assert.equal(r.data.code,'42501');});
 await check('rls','anon preferences SELECT rejected',async()=>{const r=await response(await req('/rest/v1/user_preferences',null));expectStatus(r,[401,403]);assert.equal(r.data.code,'42501');});
 for(const owner of ['a','b']) await check('rls',`${owner.toUpperCase()} preferences INSERT`,async()=>{
  const u=ctx.users[owner];const r=await response(await req('/rest/v1/user_preferences',u.jwt,json('POST',{user_id:u.id,styles:['미니멀'],onboarding_complete:true})));expectStatus(r,[201]);assert.equal(r.data[0].revision,1);
 });
 await check('rls','Preferences cross-user SELECT/UPDATE isolation',async()=>{
  let r=await response(await req(`/rest/v1/user_preferences?user_id=eq.${b.id}`,a.jwt));expectStatus(r,[200]);assert.deepEqual(r.data,[]);
  r=await response(await req(`/rest/v1/user_preferences?user_id=eq.${b.id}`,a.jwt,json('PATCH',{design:'modern'})));expectStatus(r,[200]);assert.deepEqual(r.data,[]);
 });
 await check('rls','Garment CAS first writer succeeds; stale update returns 0',async()=>{
  let r=await response(await req(q(id,'&revision=eq.1'),a.jwt,json('PATCH',{name:'CAS winner'})));expectStatus(r,[200]);assert.equal(r.data[0].revision,2);
  r=await response(await req(q(id,'&revision=eq.1'),a.jwt,json('PATCH',{name:'stale overwrite'})));expectStatus(r,[200]);assert.deepEqual(r.data,[]);
  r=await response(await req(q(id),a.jwt));assert.equal(r.data[0].name,'CAS winner');assert.equal(r.data[0].revision,2);
 });
 await check('rls','Preferences CAS first writer succeeds; stale update returns 0',async()=>{
  const path=`/rest/v1/user_preferences?user_id=eq.${a.id}&revision=eq.1`;
  let r=await response(await req(path,a.jwt,json('PATCH',{design:'lovely'})));expectStatus(r,[200]);assert.equal(r.data[0].revision,2);
  r=await response(await req(path,a.jwt,json('PATCH',{design:'modern'})));expectStatus(r,[200]);assert.deepEqual(r.data,[]);
 });
 await check('rls','Protected photo write gives 42501, distinct from 0-row conflict',async()=>{const r=await response(await req(q(id),a.jwt,json('PATCH',{photo_state:'ready'})));expectStatus(r,[403]);assert.equal(r.data.code,'42501');});
 await check('rls','Anonymous Auth claim sees no personal data (SQL simulation)',()=>{
  const out=sql(`begin;set local role authenticated;set local request.jwt.claims=${lit(JSON.stringify({sub:a.id,role:'authenticated',is_anonymous:true}))};select (select count(*) from public.garments)+(select count(*) from public.user_preferences);rollback;`);assert.equal(out,'0');
 });
 await check('rls','service_role cannot read preferences',()=>expectSqlError('service_role',null,'select * from public.user_preferences;','42501'));
 await check('rls','service_role cannot read ordinary garment notes',()=>expectSqlError('service_role',null,'select notes from public.garments;','42501'));
 await check('rls','service_role cannot UPDATE ordinary garment name',()=>expectSqlError('service_role',null,`update public.garments set name='forbidden' where id=${lit(id)};`,'42501'));
 await check('rls','service_role has explicit photo SELECT and no general INSERT/DELETE',()=>{
  const values=roleJson('service_role',null,`select json_build_object('photo',(select count(photo_state) from public.garments),'insert',has_table_privilege(current_user,'public.garments','INSERT'),'delete',has_table_privilege(current_user,'public.garments','DELETE'));`);
  assert.equal(values.photo,2);assert.equal(values.insert,false);assert.equal(values.delete,false);
 });
 // Two actual PostgreSQL sessions. Session 1 holds the row lock until session 2 is observed waiting.
 async function concurrent(table,where,patch) {
  const rev=Number(sql(`select revision from public.${table} where ${where};`));
  const firstSql=`begin;set local application_name='mc-local-first';set local role authenticated;${claims(a.id)}update public.${table} set ${patch} where ${where} and revision=${rev};select 'LOCK_HELD';\n`;
  const exe=join(process.env.LOCALAPPDATA,'Programs/DockerDesktop/resources/bin/docker.exe');
  const args=['exec','-i',DB,'psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'];
  const {spawn}=await import('node:child_process');
  function session() {const p=spawn(exe,args,{windowsHide:true,stdio:['pipe','pipe','pipe']});let out='',err='';p.stdout.on('data',v=>out+=v);p.stderr.on('data',v=>err+=v);const done=new Promise((res,rej)=>{p.on('error',rej);p.on('close',code=>code===0?res(out):rej(new Error(err)));});return {p,done,out:()=>out};}
  const first=session();let second;
  try {
   first.p.stdin.write(firstSql);
   const deadline=Date.now()+10000;while(!first.out().includes('LOCK_HELD')) {assert(Date.now()<deadline,'first session timeout');await new Promise(r=>setTimeout(r,50));}
   second=session();second.p.stdin.end(`begin;set local application_name='mc-local-second';set local lock_timeout='10s';set local role authenticated;${claims(a.id)}with changed as (update public.${table} set ${patch} where ${where} and revision=${rev} returning revision) select count(*) from changed;commit;`);
   let waiting=false;while(Date.now()<deadline) {if(sql("select count(*) from pg_stat_activity where application_name='mc-local-second' and wait_event_type='Lock';")==='1'){waiting=true;break;}await new Promise(r=>setTimeout(r,50));}
   assert(waiting,'second session did not wait on row lock');first.p.stdin.end('commit;\n');await first.done;assert.equal((await second.done).trim(),'0');
   assert.equal(Number(sql(`select revision from public.${table} where ${where};`)),rev+1);
   return 'Two connections: second UPDATE waited on lock, then affected 0 rows after first COMMIT.';
  } finally {first.p.stdin.destroy();first.p.kill();if(second){second.p.stdin.destroy();second.p.kill();}}
 }
 await check('rls','Concurrent garment CAS (two DB sessions)',()=>concurrent('garments',`id=${lit(id)}`,"name='concurrent winner'"));
 await check('rls','Concurrent preferences CAS (two DB sessions)',()=>concurrent('user_preferences',`user_id=${lit(a.id)}`,"design='modern'"));

 await check('storage','Private bucket with exact MIME/2 MiB limits',async()=>{
  const r=await response(await http('/storage/v1/bucket/garment-photos',admin,admin));expectStatus(r,[200]);assert.equal(r.data.public,false);assert.equal(Number(r.data.file_size_limit),2097152);assert.deepEqual([...r.data.allowed_mime_types].sort(),['image/jpeg','image/png','image/webp'].sort());
 });
 const candidate=await reserve(id,a.id);ctx.photos.candidate=candidate;
 await check('storage','Foreign upload to fresh reserved A path denied before owner upload',async()=>{const r=await upload(candidate,b.jwt);expectStatus(r,[400,401,403]);assert.equal(sql(`select count(*) from storage.objects where bucket_id='garment-photos' and name=${lit(candidate)};`),'0');});
 await check('storage','Owner reserved upload',async()=>{const r=await upload(candidate,a.jwt);expectStatus(r,[200,201]);});
 await check('storage','JWT owner download byte hash',async()=>assert.equal(sha(await getImage(candidate)),sha(image)));
 await check('storage','Cross-user authenticated download denied',async()=>{const r=await response(await req(download(candidate),b.jwt));expectStatus(r,[400,401,403,404]);});
 await check('storage','Unauthenticated and public downloads denied',async()=>{for(const path of [download(candidate),`/storage/v1/object/public/garment-photos/${candidate}`]){const r=await response(await req(path,null));expectStatus(r,[400,401,403,404]);}});
 await check('storage','Foreign path upload denied',async()=>{const r=await upload(candidate,b.jwt);expectStatus(r,[400,401,403,404,409]);});
 await check('storage','Missing garment path upload denied',async()=>{const r=await upload(`${a.id}/${randomUUID()}/${sha(image)}.png`,a.jwt);expectStatus(r,[400,401,403]);});
 await check('storage','Unreserved hash path in own garment denied',async()=>{const r=await upload(`${a.id}/${id}/${sha(otherImage)}.png`,a.jwt,otherImage);expectStatus(r,[400,401,403]);});
 await check('storage','Duplicate upload retry cannot overwrite bytes',async()=>{const r=await upload(candidate,a.jwt);expectStatus(r,[400,403,409]);assert.equal(sha(await getImage(candidate)),sha(image));return r;});
 await check('storage','Upsert cannot overwrite with different content',async()=>{const r=await upload(candidate,a.jwt,otherImage,true);expectStatus(r,[400,401,403]);assert.equal(sha(await getImage(candidate)),sha(image));return r;});
 await check('storage','Direct PUT replacement denied',async()=>{const r=await response(await req(object(candidate),a.jwt,{method:'PUT',headers:{'Content-Type':'image/png'},body:otherImage}));expectStatus(r,[400,401,403]);assert.equal(sha(await getImage(candidate)),sha(image));});
 await check('storage','Signed URL issuance denied',async()=>{const r=await response(await req(`/storage/v1/object/sign/garment-photos/${candidate}`,a.jwt,json('POST',{expiresIn:60})));expectStatus(r,[400,401,403,404]);});
 await check('storage','Own object list allowed',async()=>{const r=await response(await req('/storage/v1/object/list/garment-photos',a.jwt,json('POST',{prefix:`${a.id}/${id}`,limit:100})));expectStatus(r,[200]);assert(r.data.some(v=>v.name===candidate.split('/').at(-1)));});
 await check('storage','Foreign object list reveals no entries',async()=>{const r=await response(await req('/storage/v1/object/list/garment-photos',b.jwt,json('POST',{prefix:a.id,limit:100})));if(r.status===200)assert.deepEqual(r.data,[]);else expectStatus(r,[400,401,403,404]);});
 const expiredId=await createGarment('expired');const expired=await reserve(expiredId,a.id,image,1);ctx.photos.expired=expired;
 await new Promise(r=>setTimeout(r,1200));
 await check('storage','Expired reservation upload denied',async()=>{const r=await upload(expired,a.jwt);expectStatus(r,[400,401,403]);});
 await check('rls','Expired reservation acknowledgement rejected',async()=>{const r=await response(await req(q(expiredId),a.jwt,json('PATCH',{upload_state:'client_confirmed'})));expectStatus(r,[400]);assert.equal(r.data.code,'23514');});
 await check('storage','Client acknowledgement remains pending',async()=>{
  const r=await response(await req(q(id),a.jwt,json('PATCH',{upload_state:'client_confirmed'})));expectStatus(r,[200]);assert.equal(r.data[0].photo_state,'pending');assert.equal(r.data[0].upload_state,'client_confirmed');
 });
 await check('storage','Acknowledged slot rejects another upload',async()=>{const r=await upload(candidate,a.jwt);expectStatus(r,[400,401,403]);assert.equal(sha(await getImage(candidate)),sha(image));});
 // Policy fixture ONLY. There is no verification worker; never label this verified.
 const activeId=await createGarment('active-policy-simulation');const active=await reserve(activeId,a.id);ctx.photos.active=active;
 expectStatus(await upload(active,a.jwt),[200,201]);
 sqlRole('service_role',null,`update public.garments set upload_state='checking' where id=${lit(activeId)};
  update public.garments set photo_path=upload_path,photo_sha256=${lit(sha(image))},photo_size_bytes=upload_size_bytes,photo_verified_at=clock_timestamp(),photo_state='ready',upload_state='none',upload_path=null,upload_size_bytes=null,upload_expires_at=null where id=${lit(activeId)};`,true);
 ctx.active_fixture_is_simulation=true;
 await check('storage','Expired reservation cannot be acknowledged or imply ready',()=>{
  const r=roleJson('authenticated',a.id,`select json_build_object('state',photo_state,'path',photo_path) from public.garments where id=${lit(expiredId)};`);assert.equal(r.state,'pending');assert.equal(r.path,null);
 });
 // Three orphan fixtures are uploaded through real reserved paths, then only their slots are released.
 for(const label of ['orphan-single','orphan-many-1','orphan-many-2']) {
  const g=await createGarment(label);const p=await reserve(g,a.id);expectStatus(await upload(p,a.jwt),[200,201]);ctx.photos[label]=p;
  sqlRole('service_role',null,`update public.garments set upload_state='none',upload_path=null,upload_size_bytes=null,upload_expires_at=null where id=${lit(g)};`,true);
 }
 await check('storage','Unreferenced orphan fixtures remain owner-readable for cleanup',async()=>{for(const label of ['orphan-single','orphan-many-1','orphan-many-2'])assert.equal(sha(await getImage(ctx.photos[label])),sha(image));});
} catch(e) {
 checks.push({group:'setup',name:'exercise prerequisite',status:'FAIL',detail:String(e.stderr||e.message)});console.log('Exercise stopped:',String(e.stderr||e.message));
} finally {
 // JWTs are only in ignored build/. Never print this file or commit it.
 save(join(dir,'context.private.json'),ctx);
 const baseline=JSON.parse(readFileSync(join(dir,'protected-before.json'),'utf8'));
 const unchanged=JSON.stringify(protectedHashes())===JSON.stringify(baseline);
 const summary=Object.fromEntries([...new Set(checks.map(c=>c.group))].map(g=>[g,{pass:checks.filter(c=>c.group===g&&c.status==='PASS').length,fail:checks.filter(c=>c.group===g&&c.status==='FAIL').length}]));
 save(join(dir,'exercise-results.json'),{run:RUN,target:API,summary,checks,protected_files_unchanged:unchanged,worker_verified:false});
 console.log(JSON.stringify({summary,protected_files_unchanged:unchanged,worker_verified:false},null,2));
 if(checks.some(c=>c.status==='FAIL')||!unchanged)process.exitCode=1;
}
