// New synthetic rows/images only; existing accounts must be known local fixtures.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {join,resolve,sep} from 'node:path';
import {randomUUID} from 'node:crypto';
import * as magick from '../../build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/index.js';
import {ROOT,guard,http,sql,sqlRole,lit,sha,save} from './integration.mjs';

const {status}=guard();
const fixturePath=resolve(process.argv[2]||'');
assert(fixturePath.startsWith(join(ROOT,'build','supabase-wardrobe-crud')+sep));
const fixture=JSON.parse(readFileSync(fixturePath));assert.equal(fixture.api,'http://127.0.0.1:54321');
for(const u of Object.values(fixture.users))assert(/^crud-\d+-[ab]@example.test$/.test(u.email),'Synthetic accounts only');
const folder=join(ROOT,'build','supabase-photo-flow',`photos-${Date.now()}`);mkdirSync(folder,{recursive:true});
const baseline={};for(const table of ['public.garments','public.user_preferences','storage.objects','storage.buckets'])baseline[table]=JSON.parse(sql(`select coalesce(json_agg(json_build_object('id',${table==='public.user_preferences'?'user_id':'id'},'digest',md5(row_to_json(t)::text))),'[]'::json) from ${table} t;`));
save(join(folder,'baseline.json'),baseline);
const protectedFiles={};for(const file of ['supabase/drafts/01_database.draft.sql','supabase/drafts/02_storage_policies.draft.sql',...['index.ts','adapter.ts','core.ts','image.ts'].map(f=>'supabase/functions/verify-garment-photo/'+f),'lib/services/storage/indexeddb_wardrobe_repository.dart','lib/models/garment.dart'])protectedFiles[file]=sha(readFileSync(join(ROOT,file)));
save(join(folder,'protected-files.json'),protectedFiles);
const users=structuredClone(fixture.users),key=status.PUBLISHABLE_KEY;
for(const u of Object.values(users)){const r=await http('/auth/v1/token?grant_type=password',key,null,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:u.email,password:u.password})});assert.equal(r.status,200);u.jwt=(await r.json()).access_token;}
save(join(folder,'private-context.json'),{folder,api:fixture.api,publishableKey:key,users,source_fixture:fixturePath});
await magick.initializeImageMagick(readFileSync(join(ROOT,'build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/x86/magick.wasm')));
const images={};for(const [ext,format] of [['jpg',magick.MagickFormat.Jpeg],['png',magick.MagickFormat.Png],['webp',magick.MagickFormat.WebP]]){images[ext]=magick.ImageMagick.read(new magick.MagickColor('#a6d9c5'),24,18,img=>img.write(format,data=>Uint8Array.from(data)));writeFileSync(join(folder,`synthetic.${ext}`),images[ext]);}
const large=magick.ImageMagick.read(new magick.MagickColor('#bf8a55'),2001,2001,img=>img.write(magick.MagickFormat.Png,data=>Uint8Array.from(data)));
const checks=[],rows=[];
const json=body=>({method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
const row=id=>JSON.parse(sql(`select row_to_json(g) from public.garments g where id=${lit(id)};`));
async function command(action,r,extra={},u=users.a){const response=await http('/functions/v1/garment-photo-operations',key,u?.jwt,json({action,garment_id:r.id,revision:r.revision,...extra}));return {status:response.status,body:await response.json()};}
async function create(label){const response=await http('/rest/v1/garments',key,users.a.jwt,{...json({local_id:randomUUID(),name:`PHOTO FLOW ${label}`,category:'tops',image_width:1,image_height:1}),headers:{'Content-Type':'application/json',Prefer:'return=representation'}});assert.equal(response.status,201);const [r]=await response.json();rows.push(r.id);return r;}
async function reserve(r,ext,bytes=images[ext],hash=sha(bytes)){return command('reserve',row(r.id),{sha256:hash,size_bytes:bytes.length,mime_type:ext==='jpg'?'image/jpeg':`image/${ext}`});}
async function upload(path,bytes,ext='jpg',u=users.a){return http(`/storage/v1/object/garment-photos/${path}`,key,u.jwt,{method:'POST',headers:{'Content-Type':ext==='jpg'?'image/jpeg':`image/${ext}`,'x-upsert':'false'},body:bytes});}
async function download(path,u=users.a){return http(`/storage/v1/object/authenticated/garment-photos/${path}`,key,u.jwt);}
async function confirm(r){const current=row(r.id);const response=await http(`/rest/v1/garments?id=eq.${r.id}&revision=eq.${current.revision}`,key,users.a.jwt,{method:'PATCH',headers:{'Content-Type':'application/json',Prefer:'return=representation'},body:JSON.stringify({upload_state:'client_confirmed'})});assert.equal(response.status,200);assert.equal((await response.json()).length,1);}
async function ready(r,ext){const reserved=await reserve(r,ext);assert.equal(reserved.status,200);const path=reserved.body.upload_path;assert([200,201].includes((await upload(path,images[ext],ext)).status));await confirm(r);const verified=await command('verify',row(r.id),{upload_path:path});assert.equal(verified.status,200,verified.body.error);assert.equal(verified.body.status,'ready');return row(r.id);}
async function check(name,run){try{await run();checks.push({name,passed:true});console.log('PASS',name);}catch(e){checks.push({name,passed:false,error:e.message});throw e;}}
let jpg,png,webp,replacement;
try {
  await check('CORS allows 8081 preflight and rejects other origins',async()=>{
    let r=await http('/functions/v1/garment-photo-operations',key,null,{method:'OPTIONS',headers:{Origin:'http://localhost:8081','Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'authorization,content-type'}});assert([200,204].includes(r.status));assert(['http://localhost:8081','*'].includes(r.headers.get('access-control-allow-origin')));
    r=await http('/functions/v1/garment-photo-operations',key,users.a.jwt,{...json({}),headers:{Origin:'http://localhost:8080','Content-Type':'application/json'}});assert.equal(r.status,403);
  });
  await check('unauthenticated operations denied',async()=>{const r=await http('/functions/v1/garment-photo-operations',key,null,json({}));assert.equal(r.status,401);});
  for(const ext of ['jpg','png','webp'])await check(`actual ${ext} upload and original verifier ready`,async()=>{const r=await ready(await create(ext),ext);assert.equal(r.photo_sha256,sha(images[ext]));assert.equal(r.photo_size_bytes,images[ext].length);assert.equal(r.image_width,24);assert.equal(r.image_height,18);assert(r.photo_verified_at);if(ext==='jpg')jpg=r;if(ext==='png')png=r;if(ext==='webp')webp=r;});
  await check('authenticated bytes correct; other user download and reservation denied',async()=>{const r=await download(jpg.photo_path);assert.equal(r.status,200);assert.equal(sha(Buffer.from(await r.arrayBuffer())),jpg.photo_sha256);assert(!(await download(jpg.photo_path,users.b)).ok);const denied=await command('reserve',jpg,{sha256:sha(images.png),size_bytes:images.png.length,mime_type:'image/png'},users.b);assert.equal(denied.status,404);});
  await check('client cannot reserve paths or set ready directly',async()=>{for(const body of [{upload_path:jpg.photo_path},{photo_state:'ready'}]){const r=await http(`/rest/v1/garments?id=eq.${jpg.id}`,key,users.a.jwt,{method:'PATCH',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});assert.equal(r.status,403);}});
  await check('replacement succeeds; prior approved image remains protected',async()=>{const before=row(jpg.id);replacement=await ready(jpg,'png');assert.equal(replacement.retired_photo_path,before.photo_path);assert(Date.parse(replacement.retired_cleanup_after)>Date.now()+24*3600000);assert.equal((await download(before.photo_path)).status,200);await http('/storage/v1/object/garment-photos',key,users.a.jwt,{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefixes:[before.photo_path,replacement.photo_path]})});assert.equal((await download(before.photo_path)).status,200);assert.equal((await download(replacement.photo_path)).status,200);});
  await check('next replacement and cleanup blocked during 25-hour grace',async()=>{const reserved=await reserve(jpg,'webp');assert.equal(reserved.status,409);assert.equal(reserved.body.error,'cleanup_pending');const clean=await command('cleanup',row(jpg.id),{path:replacement.retired_photo_path});assert.equal(clean.status,409);assert.equal(clean.body.error,'cleanup_not_due');});
  await check('failed verification preserves previous approved photo; cancelled candidate removed safely',async()=>{
    const before=row(png.id),reserved=await reserve(png,'webp',images.webp,'d'.repeat(64));assert.equal(reserved.status,200);const path=reserved.body.upload_path;assert((await upload(path,images.webp,'webp')).ok);await confirm(png);
    const verified=await command('verify',row(png.id),{upload_path:path});assert.equal(verified.status,422);assert.equal(verified.body.error,'hash_mismatch');const failed=row(png.id);for(const k of ['photo_path','photo_sha256','photo_size_bytes','photo_verified_at'])assert.equal(failed[k],before[k]);
    const cancelled=await command('cancel',failed,{path});assert.equal(cancelled.status,200,cancelled.body.error);assert.equal(row(png.id).photo_path,before.photo_path);assert.equal(row(png.id).retired_photo_path,null);assert(!(await download(path)).ok);assert.equal((await download(before.photo_path)).status,200);
  });
  await check('non-image content rejected by original worker',async()=>{const r=await create('invalid'),bytes=new TextEncoder().encode('synthetic non-image'),reserved=await reserve(r,'png',bytes);assert.equal(reserved.status,200);assert((await upload(reserved.body.upload_path,bytes,'png')).ok);await confirm(r);const v=await command('verify',row(r.id),{upload_path:reserved.body.upload_path});assert.equal(v.status,422);assert.equal(row(r.id).photo_state,'pending');});
  await check('oversize reservation and actual >2MiB Storage upload rejected',async()=>{const r=await create('oversized');const bad=await command('reserve',r,{sha256:'e'.repeat(64),size_bytes:2097153,mime_type:'image/jpeg'});assert.equal(bad.status,400);const valid=await reserve(r,'jpg');assert.equal(valid.status,200);assert(!(await upload(valid.body.upload_path,new Uint8Array(2097153))).ok);assert.equal(row(r.id).photo_state,'pending');});
  await check('more than 4 million pixels rejected by original decoder',async()=>{const r=await create('pixels'),reserved=await reserve(r,'png',large);assert.equal(reserved.status,200);assert((await upload(reserved.body.upload_path,large,'png')).ok);await confirm(r);const v=await command('verify',row(r.id),{upload_path:reserved.body.upload_path});assert.equal(v.status,422);assert.equal(row(r.id).photo_state,'pending');});
  await check('duplicate reserve, lost upload response retry and verification idempotent',async()=>{const r=await create('retry'),one=await reserve(r,'jpg'),two=await reserve(r,'jpg');assert.equal(one.body.upload_path,two.body.upload_path);assert((await upload(one.body.upload_path,images.jpg)).ok);assert(!(await upload(one.body.upload_path,images.jpg)).ok);await confirm(r);const v=await command('verify',row(r.id),{upload_path:one.body.upload_path});assert.equal(v.status,200);const rev=row(r.id).revision;assert.equal((await command('verify',row(r.id),{upload_path:one.body.upload_path})).status,200);assert.equal(row(r.id).revision,rev);});
  await check('photo removal schedules retirement without deleting protected bytes',async()=>{const before=row(webp.id);const removed=await command('remove',before,{path:before.photo_path});assert.equal(removed.status,200);assert.equal(row(webp.id).photo_state,'pending');assert.equal(row(webp.id).retired_photo_path,before.photo_path);assert.equal((await download(before.photo_path)).status,200);});
  await check('due cleanup uses real Storage policy and clears slot (fixture clock simulation)',async()=>{
    // ONLY this run's new synthetic retired row; never change policies or old rows.
    assert(rows.includes(webp.id));const current=row(webp.id);
    sqlRole('service_role',null,`update public.garments set retired_cleanup_after=clock_timestamp()-interval '1 minute' where id=${lit(webp.id)} and user_id=${lit(users.a.id)} and revision=${current.revision};`,true);
    const clean=await command('cleanup',row(webp.id),{path:current.retired_photo_path});assert.equal(clean.status,200,clean.body.error);assert.equal(row(webp.id).retired_photo_path,null);assert(!(await download(current.retired_photo_path)).ok);
    const cleaned=row(webp.id);
    const deleted=await http(`/rest/v1/garments?id=eq.${cleaned.id}&revision=eq.${cleaned.revision}`,key,users.a.jwt,{method:'DELETE',headers:{Prefer:'return=representation'}});
    assert.equal(deleted.status,200);assert.equal((await deleted.json()).length,1);assert.equal(row(webp.id),null);
    save(join(folder,'cleanup-delete-result.json'),{passed:1,failed:0,check:'Owner revision-CAS garment deletion after real Storage cleanup; new synthetic WebP row only.'});
  });
} catch(e){console.error('Photo flow failed:',e.message);process.exitCode=1;}
finally {
  save(join(folder,'http-results.json'),{passed:checks.filter(v=>v.passed).length,failed:checks.filter(v=>!v.passed).length,checks,new_fixture_ids:rows});
  console.log(JSON.stringify({folder,passed:checks.filter(v=>v.passed).length,failed:checks.filter(v=>!v.passed).length}));
}
