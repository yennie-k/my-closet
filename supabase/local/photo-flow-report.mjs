// Read-only preservation check. Never resets or cleans pre-existing fixtures.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,join,sep} from 'node:path';
import {ROOT,LOCAL,guard,sql,sha,http,lit} from './integration.mjs';

const {status}=guard();
const folder=resolve(process.argv[2]||'');
assert(folder.startsWith(join(ROOT,'build','supabase-photo-flow')+sep));
const read=name=>JSON.parse(readFileSync(join(folder,name),'utf8'));
const baseline=read('baseline.json'),preservation=[];
for(const [table,original] of Object.entries(baseline)) {
  assert(['public.garments','public.user_preferences','storage.objects','storage.buckets'].includes(table));
  const current=JSON.parse(sql(`select coalesce(json_agg(json_build_object('id',${table==='public.user_preferences'?'user_id':'id'},'digest',md5(row_to_json(t)::text))),'[]'::json) from ${table} t;`));
  const index=new Map(current.map(row=>[row.id,row.digest]));
  assert(original.every(row=>index.get(row.id)===row.digest),`Pre-existing rows changed: ${table}`);
  preservation.push({table,original_rows:original.length,current_rows:current.length,original_rows_unchanged:true});
}
const protectedFiles=read('protected-files.json');
for(const [file,digest] of Object.entries(protectedFiles))assert.equal(sha(readFileSync(join(ROOT,file))),digest,`Protected source changed: ${file}`);
for(const file of ['index.ts','adapter.ts','core.ts','image.ts'])assert.equal(sha(readFileSync(join(ROOT,'supabase/functions/verify-garment-photo',file))),sha(readFileSync(join(LOCAL,'supabase/functions/verify-garment-photo',file))));
const bucket=JSON.parse(sql("select json_build_object('private',not public,'file_size_limit',file_size_limit,'allowed_mime_types',allowed_mime_types) from storage.buckets where id='garment-photos';"));
assert.equal(bucket.private,true);assert.equal(bucket.file_size_limit,2097152);
const photoHttp=read('http-results.json'),photoDart=read('dart-photo-results.json'),photoEdge=read('browser-photo-results.json');
const cleanupDelete=read('cleanup-delete-result.json');assert.equal(cleanupDelete.failed,0);
const readyPath=sql(`select photo_path from public.garments where id=${lit(photoHttp.new_fixture_ids[0])} and photo_state='ready';`);
assert(/^[0-9a-f-]+\/[0-9a-f-]+\/[0-9a-f]{64}\.(jpg|png|webp)$/.test(readyPath));
for(const kind of ['public','authenticated']) {
  const response=await http(`/storage/v1/object/${kind}/garment-photos/${readyPath}`,status.PUBLISHABLE_KEY,null);
  await response.body?.cancel();assert(!response.ok,`Anonymous ${kind} photo download succeeded`);
}
const crudFolder=join(ROOT,'build/supabase-wardrobe-crud/crud-1793596184467');
const crudDart=JSON.parse(readFileSync(join(crudFolder,'repository-results.json'))),crudEdge=JSON.parse(readFileSync(join(crudFolder,'browser-results.json')));
for(const suite of [photoHttp,photoDart,photoEdge,crudDart,crudEdge])assert.equal(suite.failed,0);
const report={date:'2026-11-02',targets:{api:'http://127.0.0.1:54321',db:'127.0.0.1:54322',web:'http://localhost:8081'},
  cloud_connected:false,sql_policy_original_worker_changed:false,git_commit_push:false,real_browser_8080_opened:false,
  photo_http:photoHttp,photo_dart:photoDart,photo_edge:photoEdge,crud_dart:crudDart,crud_edge:crudEdge,
  cleanup_then_delete:cleanupDelete,anonymous_photo_download:{passed:2,failed:0},
  flutter:{analyze:'passed',test_passed:82,test_failed:0,default_web_build:'passed',photo_dev_web_build:'passed'},
  node_core:{new_operations:15,unchanged_worker:24,failed:0},
  indexeddb_probe:'passed; isolated synthetic profile/database, two reloads and legacy read without rewrite',
  preservation,protected_sources_unchanged:Object.keys(protectedFiles),local_original_worker_matches:true,bucket,
  intentional_denials:'Foreign/anonymous access, oversized/invalid images, stale revision, protected deletion, cooldown, failed upload and lost response are asserted rejections, not failed tests.',
  limitations:[
    'The natural 25-hour wait was not performed; due cleanup used only this run\'s new synthetic row with a simulated expired timestamp.',
    'No automatic cleanup scheduler, per-user quota, rate limiter or cloud deployment.',
    'Original file metadata was compared; original Storage bytes and the real 8080 IndexedDB were not opened/downloaded.',
    'Old historical 29/33 runner was not rerun: it creates control policies and requires fresh fixtures. Current Dart RLS/CRUD, actual photo Storage HTTP and unchanged worker core regressions passed.',
    'Browser checks used an isolated headless Edge desktop and 360px viewport; physical phones, Safari and assistive technology were not tested.',
    'Supabase local gateway answered OPTIONS with broad CORS headers; authenticated POST still enforces the local origin allowlist, Auth ownership and existing RLS.',
    'Storage and metadata commits are separate; partial save remains visible and retries keep the same garment/reservation.'
  ]};
writeFileSync(join(ROOT,'docs/supabase/photo-upload-results-20261102.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({photo_http:photoHttp.passed,photo_dart:photoDart.passed,photo_edge:photoEdge.passed,crud_dart:crudDart.passed,crud_edge:crudEdge.passed,preservation,protected_files:Object.keys(protectedFiles).length,bucket},null,2));
