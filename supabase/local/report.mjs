// Produces a credential-free, reproducible report from the local run artifacts.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT,LOCAL,API,guard,docker,sql,jsonSql,save,protectedHashes } from './integration.mjs';
const dir=join(ROOT,'build/supabase-local/20261029-run1');
const read=name=>JSON.parse(readFileSync(join(dir,name),'utf8'));
const {status,inspected}=guard(); // Local status secrets deliberately never included below.
const prepare=read('prepare-results.json');
const exercise=read('exercise-results.json');
const additional=read('additional-results.json');
const deletion=read('deletion-results.json');
const checks=[...exercise.checks,...additional.checks,...deletion.checks];
const groups=Object.fromEntries([...new Set(checks.map(c=>c.group))].map(group=>[group,{pass:checks.filter(c=>c.group===group&&c.status==='PASS').length,fail:checks.filter(c=>c.group===group&&c.status==='FAIL').length}]));
const images=docker(['ps','--format','{{.Names}}|{{.Image}}|{{.Status}}']).trim().split('\n').filter(v=>v.includes('_my_closet_supabase_local')).map(v=>{const[name,image,state]=v.split('|');return{name,image,state};});
const helpers=jsonSql(`select json_agg(json_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid))) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='storage' and p.proname in ('operation','allow_only_operation','allow_any_operation');`);
const before=read('protected-before.json');const after=protectedHashes();
const changes=Object.keys(before).filter(k=>before[k]!==after[k]);assert.deepEqual(changes,[]);
const result={date:'2026-10-29',run:'20261029-run1',api:API,db:'127.0.0.1:54322',local_project:LOCAL,
 cloud_connected:false,cli:'2.122.0',postgres:sql('select version();'),images,remote_link_marker_present:false,
 docker_context:'desktop-linux (local Windows named pipe)',port_publication:inspected.NetworkSettings.Ports,
 prepare,groups,checks,helpers,finalState:deletion.finalState,
 protected_files:{count:Object.keys(before).length,changed:changes},
 worker_verified:false,active_photo_fixture:'server-role policy simulation; not verification worker output',
 original_storage_http_script_executed:false,
 local_http_adapter:'supabase/local/exercise.mjs + additional.mjs + delete-tests.mjs; adapted original assertions with loopback/redirect/fixture guards',
 unverified:['Real verification/reservation/GC worker and caller validation','Hash/size/MIME/decode mismatch handling by a worker',
  'Process/network crash recovery and durable orphan queue','Quota/account rate limits and high concurrency','Real 24-hour elapsed grace (fixture clock used)',
  'Storage list_v2 HTTP, metadata GET/HEAD, TUS, S3 and transformed images','Cloud version/config compatibility','Actual backup restoration','Flutter conflict UI and IndexedDB migration']};
save(join(ROOT,'docs/supabase/local-integration-results-20261029.json'),result);
console.log(JSON.stringify({groups,prepare:prepare.checks,protected_files:result.protected_files,finalState:result.finalState,worker_verified:false},null,2));
