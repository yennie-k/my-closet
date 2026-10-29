// Applies reviewed ORIGINAL drafts only to the verified, initially empty local stack.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { ROOT, LOCAL, DB, API, guard, docker, sql, jsonSql, sha, save, protectedHashes, http } from './integration.mjs';

const RUN = '20261029-run1';
const output = join(ROOT, 'build/supabase-local', RUN);
const migrationDir = join(LOCAL, 'rehearsals', RUN);
const result = { run:RUN, target:API, cloud_connection:false, checks:[] };
assert(!existsSync(output) && !existsSync(migrationDir), 'Run path exists; never overwrite or reset');
const { status } = guard();
const initial = jsonSql(`select json_build_object('users',(select count(*) from auth.users),
 'objects',(select count(*) from storage.objects),'buckets',(select count(*) from storage.buckets),
 'garments',to_regclass('public.garments'),'preferences',to_regclass('public.user_preferences'),
 'private_schema',to_regnamespace('my_closet_private'));`);
assert.deepEqual(initial, {users:0,objects:0,buckets:0,garments:null,preferences:null,private_schema:null}, 'Local target is not empty; review before mutation');
mkdirSync(output,{recursive:true}); mkdirSync(migrationDir,{recursive:true});
save(join(output,'protected-before.json'),protectedHashes());
save(join(output,'initial-state.json'),initial);
// Full logical DB backup; no pre-existing objects exist in Storage. Secrets remain ignored.
const backup = docker(['exec',DB,'pg_dump','-U','postgres','-d','postgres','--format=custom'],undefined,true);
writeFileSync(join(output,'before.dump'),backup,{flag:'wx'});
const listing = docker(['exec','-i',DB,'pg_restore','--list'],backup);
assert.match(listing,/dbname: postgres/);
writeFileSync(join(output,'backup-toc.txt'),listing,{flag:'wx'});
result.backup={path:join(output,'before.dump'),sha256:sha(backup),toc_valid:true,physical_storage_backup_needed:false};
const restore = `# NOT EXECUTED. Restoration is destructive and REQUIRES separate user approval.\n\n`+
 `Only target the verified local Docker container ${DB} (host 127.0.0.1:54322).\n`+
 `Logical backup: ${join(output,'before.dump')}\n`+
 `Verify SHA-256 ${sha(backup)} and pg_restore --list before planning restore.\n`+
 `Do not blindly restore into a live managed Supabase DB: preserve managed owners/roles, stop API writers, and review object conflicts.\n`+
 `Prefer restoring into a new isolated recovery instance. Reset/drop/--clean/volume deletion were NOT performed.\n`+
 `Original Storage objects/buckets/Auth users: 0. Future synthetic objects require Storage API cleanup, not storage.objects DML.\n`;
writeFileSync(join(output,'RESTORE-REQUIRES-APPROVAL.txt'),restore,{flag:'wx'});
const manifest=[];
for (const file of ['01_database','02_storage_policies']) {
 const source=join(ROOT,`supabase/drafts/${file}.draft.sql`);
 const bytes=readFileSync(source);const target=join(migrationDir,`${file}.local.sql`);
 writeFileSync(target,bytes,{flag:'wx'});manifest.push({source,target,sha256:sha(bytes)});
}
save(join(migrationDir,'manifest.json'),{run:RUN,target:API,db:'127.0.0.1:54322',execution:'direct psql rehearsal; not CLI migration history',files:manifest});
function apply(name,file) {
 try {const out=sql(readFileSync(file,'utf8'));writeFileSync(join(output,`${name}.log`),out,{flag:'wx'});result.checks.push({name,status:'PASS'});}
 catch(e) {const error=String(e.stderr||e.message);result.checks.push({name,status:'FAIL',error});throw new Error(`${name}: ${error}`);}
}
try {
 apply('01_database',manifest[0].target);
 const bucket=await http('/storage/v1/bucket',status.SERVICE_ROLE_KEY,status.SERVICE_ROLE_KEY,{method:'POST',
  headers:{'Content-Type':'application/json'},body:JSON.stringify({id:'garment-photos',name:'garment-photos',public:false,
   file_size_limit:2097152,allowed_mime_types:['image/jpeg','image/png','image/webp']})});
 assert(bucket.ok,`Bucket creation failed: ${bucket.status} ${await bucket.text()}`);
 result.checks.push({name:'private_bucket',status:'PASS'});
 apply('02_storage_policies',manifest[1].target);
} catch(e) {
 result.error=e.message;
}
// Execute catalog assertions separately, preserving the original opt-in checks.
if(result.checks.some(c=>c.name==='02_storage_policies'&&c.status==='PASS')) {
 try {sql(`set my_closet_test.allow_fixtures='yes';\n`+readFileSync(join(ROOT,'supabase/tests/02_storage_contract.draft.sql'),'utf8'));
  result.checks.push({name:'02_storage_contract_actual',status:'PASS'});
 } catch(e) {result.checks.push({name:'02_storage_contract_actual',status:'FAIL',error:String(e.stderr||e.message)});}
}
result.protected_files_unchanged=JSON.stringify(protectedHashes())===JSON.stringify(JSON.parse(readFileSync(join(output,'protected-before.json'),'utf8')));
save(join(output,'prepare-results.json'),result);
console.log(JSON.stringify(result,null,2));
if(result.error||result.checks.some(c=>c.status==='FAIL')||!result.protected_files_unchanged) process.exitCode=1;
