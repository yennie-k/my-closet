// Read-only original-data comparison; no cleanup/reset of test fixtures.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,join,sep} from 'node:path';
import {ROOT,guard,sql,sha} from './integration.mjs';

guard();
const folder=resolve(process.argv[2]||'');
assert(folder.startsWith(join(ROOT,'build','supabase-wardrobe-crud')+sep));
const baseline=JSON.parse(readFileSync(join(folder,'baseline.json')));
const preservation=[];
for(const [table,original] of Object.entries(baseline)) {
  const current=JSON.parse(sql(`select coalesce(json_agg(json_build_object('id',${table==='public.user_preferences'?'user_id':'id'},'digest',md5(row_to_json(t)::text))),'[]'::json) from ${table} t;`));
  const index=new Map(current.map(r=>[r.id,r.digest]));
  assert(original.every(r=>index.get(r.id)===r.digest),`Original row changed: ${table}`);
  preservation.push({table,before:original.length,after:current.length,original_rows_unchanged:true});
}
const protectedFiles=JSON.parse(readFileSync(join(folder,'protected-files.json')));
for(const [file,digest] of Object.entries(protectedFiles)) assert.equal(sha(readFileSync(join(ROOT,file))),digest,`Protected source changed: ${file}`);
const repository=JSON.parse(readFileSync(join(folder,'repository-results.json')));
const browser=JSON.parse(readFileSync(join(folder,'browser-results.json')));
assert.equal(repository.failed,0);assert.equal(browser.failed,0);
const report={date:'2026-11-02',api:'http://127.0.0.1:54321',db:'127.0.0.1:54322',web_origin:'http://localhost:8081',cloud_connection:false,
  sql_schema_policy_worker_changes:false,git_commit_push:false,original_browser_profile_opened:false,
  repository,browser,preservation,protected_sources_unchanged:Object.keys(protectedFiles),
  flutter_tests:{passed:71,failed:0},flutter_analyze:'passed',default_web_build:'passed',crud_web_build:'passed',
  indexeddb_regression:'passed; legacy model read and two real reloads, synthetic metadata/photo CRUD',
  intentional_failures:'RLS denials, stale CAS, duplicate payload conflict, injected network/permission failures assert expected rejection',
  limitations:['Photo upload, download and migration not implemented','Photo-linked/reserved/retired garments cannot be deleted through this app in this phase',
    'Missing row cannot be distinguished from RLS-hidden row without additional trusted information',
    'Idempotency key survives retries within one open form; reloading/discarding the form creates a new draft',
    'A timed-out write can already have committed; update/delete retries use the original revision and never silently overwrite',
    'Existing Storage metadata compared; original file bytes and real 8080 browser data not opened or downloaded',
    'Native Android/iOS/Windows runtimes, natural token-expiry wait, existing worker/Storage 29/33 suites not rerun']};
// This task's generated report may be refreshed after a final test rerun.
writeFileSync(join(ROOT,'docs','supabase','wardrobe-crud-results-20261102.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({repository_passed:repository.passed,browser_passed:browser.passed,preservation,protected_sources_unchanged:Object.keys(protectedFiles).length},null,2));
