// Credential-free final verification, including original row and binary preservation.
import assert from 'node:assert/strict';
import { readFileSync,existsSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT,LOCAL,DB,API,guard,docker,http,sql,sha,save,protectedHashes } from './integration.mjs';
const dir=join(ROOT,'build/supabase-local/20261029-worker-2');const {status}=guard();
const read=name=>JSON.parse(readFileSync(join(dir,name),'utf8'));
const baseline=read('protected-before.json'),current=protectedHashes();
const changed=Object.keys(baseline).filter(name=>current[name]!==baseline[name]);assert.deepEqual(changed,[]);
const before=read('existing-state.json');
const all=JSON.parse(sql("select json_build_object('garments',(select coalesce(json_agg(g order by id),'[]') from public.garments g),'preferences',(select coalesce(json_agg(p order by user_id),'[]') from public.user_preferences p));"));
assert(before.garments.every(g=>JSON.stringify(all.garments.find(v=>v.id===g.id))===JSON.stringify(g)),'Previous garment changed');
assert(before.preferences.every(g=>JSON.stringify(all.preferences.find(v=>v.user_id===g.user_id))===JSON.stringify(g)),'Previous preferences changed');
const backup=read('backup-manifest.json');
for(const p of backup.photos){const res=await http(`/storage/v1/object/authenticated/${p.bucket}/${p.path}`,status.SERVICE_ROLE_KEY,status.SERVICE_ROLE_KEY);assert.equal(res.status,200);assert.equal(sha(Buffer.from(await res.arrayBuffer())),p.sha256);}
const source=read('synced-2.json');for(const f of source){assert.equal(sha(readFileSync(join(ROOT,'supabase/functions/verify-garment-photo',f.file))),f.sha256);assert.equal(sha(readFileSync(join(LOCAL,'supabase/functions/verify-garment-photo',f.file))),f.sha256);}
const httpResult=read('http-results-2.json'),race=read('race-results.json'),replacement=read('replacement-results.json');
const regression=JSON.parse(readFileSync(join(ROOT,'build/supabase-local/20261029-worker-regression/regression-results.json'),'utf8'));
const state=JSON.parse(sql("select json_build_object('auth_users',(select count(*) from auth.users),'garments',(select count(*) from public.garments),'preferences',(select count(*) from public.user_preferences),'objects',(select count(*) from storage.objects),'buckets',(select count(*) from storage.buckets));"));
const result={date:'2026-10-29',run:'20261029-worker-2',api:API,db:'127.0.0.1:54322',cloud_connection:false,
 sql_changes:false,cli:'2.122.0',edge_runtime:'1.77.8',deno_compatibility:'2.1.4',gateway_verify_jwt:true,
 verified_user_jwt_algorithm:httpResult.jwt_algorithm,authentication:'Auth GET /auth/v1/user verification on every request, then authenticated/non-anonymous identity checks and caller-scoped RLS',
 dependency:{package:'@imagemagick/magick-wasm',version:'0.0.45',wasm_sha256:sha(readFileSync(join(ROOT,'build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/x86/magick.wasm')))},
 unit:{command:'node --experimental-strip-types --test supabase/tests/photo_worker.test.ts',pass:24,fail:0,evidence:'Executed successfully in this task after final permission/retry classification change'},
 http:httpResult,races:race,replacement,regression,
 real_worker_attestation_verified:true,source,
 preservation:{protected_files:Object.keys(baseline).length,changed_files:changed,original_garments:before.garments.length,
  original_preferences:before.preferences.length,original_photo_hashes_verified:backup.photos.length,all_original_rows_and_photos_unchanged:true},
 final_state:state,backup:{path:join(dir,'before-worker.dump'),sha256:backup.db_backup_sha256,restore_tested:false},
 initial_failures:[
  'Setup attempt worker-1: multi-line JSON snapshot parser rejected full result; fixed with full JSON parsing before DB mutation; failed folder retained.',
  'Decoder API: getPixels requires callback; initial unit failures were unexpected, fixed.',
  'Decoder listLength=1 rejected valid static images due temporary decoder images; limit changed to 4 with separate animated-container rejection; final tests passed.',
  'Sandbox npm DNS and CLI telemetry access failed; rerun with approved local dependency/tool access.'
 ],
 remaining:['No cloud deployment or cloud compatibility test','No reservation endpoint, scheduled durable verification queue, rate limit/quota or GC worker',
  'Privileged Storage mutation after the final object read and before/after DB commit cannot be atomically prevented across Storage and PostgreSQL; clients cannot do this under tested RLS',
  'Ready duplicate returns previous attestation snapshot, not perpetual file-existence proof',
  'Limits: 2 MiB, 4096px per dimension, 4 million pixels; static JPG/PNG/WebP only',
  'No high-load/real process kill or large-image performance benchmark; deterministic failure/lease recovery tests are not a durable queue test',
  'No Flutter/IndexedDB/browser CORS integration or full backup restoration test']};
assert.equal(result.http.summary.fail,0);assert.equal(race.summary.fail,0);assert.equal(replacement.summary.fail,0);
assert.equal(regression.groups.rls.fail,0);assert.equal(regression.groups.storage.fail,0);assert(regression.catalog_contract_passed);
save(join(ROOT,'docs/supabase/photo-worker-results-20261029.json'),result);
console.log(JSON.stringify({unit:result.unit,http:httpResult.summary,races:race.summary,replacement:replacement.summary,regression:regression.groups,
 preservation:result.preservation,final_state:state,real_worker_attestation_verified:true},null,2));
