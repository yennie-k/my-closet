// Reuse the unchanged 29/33 integration assertions with fresh, scoped fixtures.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync,writeFileSync,mkdirSync,existsSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { ROOT,guard,sql,save,sha,protectedHashes } from './integration.mjs';
guard();const run='20261029-worker-regression';const dir=join(ROOT,'build/supabase-local',run);
assert(!existsSync(dir),'No resets or overwrites');mkdirSync(dir,{recursive:true});
save(join(dir,'protected-before.json'),protectedHashes());
save(join(dir,'prepare-results.json'),{existing_schema:true,reapplied:false});
const before=JSON.parse(sql("select coalesce(json_agg(g order by id),'[]') from public.garments g;"));
save(join(dir,'preexisting-garments.json'),before);
const changes=[];let catalog=false;
try {
 sql("set my_closet_test.allow_fixtures='yes';\n"+readFileSync(join(ROOT,'supabase/tests/02_storage_contract.draft.sql'),'utf8'));catalog=true;
 for(const name of ['exercise','additional','delete-tests']){
  const path=join(ROOT,`supabase/local/${name}.mjs`),original=readFileSync(path,'utf8');
  let source=original.replaceAll("'./integration.mjs'",JSON.stringify(pathToFileURL(join(ROOT,'supabase/local/integration.mjs')).href))
   .replaceAll('20261029-run1',run).replaceAll('20261029_run1','20261029_worker_regression');
  if(name==='exercise'){
   const old="assert.equal(sql('select count(*) from public.garments;'),'0');";
   assert(source.includes(old));source=source.replace(old,"assert.equal(sql(`select count(*) from public.garments where user_id in (${lit(ctx.users.a.id)},${lit(ctx.users.b.id)});`),'0');");
   const oldPhoto='count(photo_state) from public.garments)';assert(source.includes(oldPhoto));
   source=source.replace(oldPhoto,'count(photo_state) from public.garments where user_id in (${lit(a.id)},${lit(b.id)}))');
  }
  const adapted=join(dir,`${name}.adapted.mjs`);writeFileSync(adapted,source,{flag:'wx'});
  changes.push({original:`supabase/local/${name}.mjs`,sha256:sha(readFileSync(path)),adapted:adapted,
   changes:['separate run IDs, paths and control bucket/policy','absolute import of original local guard',...(name==='exercise'?['two empty-DB fixture counts scoped to fresh A/B users; same RLS/ACL assertions']:[])]});
  const output=execFileSync(process.execPath,[adapted,...(name==='delete-tests'?['--approved-synthetic-manifest']:[])],{cwd:ROOT,encoding:'utf8',windowsHide:true,timeout:120000,maxBuffer:4*1024*1024});
  writeFileSync(join(dir,`${name}.stdout.log`),output,{flag:'wx'});console.log(output);
 }
}catch(e){save(join(dir,'runner-error.json'),{error:String(e.stderr||e.message)});process.exitCode=1;}
finally {
 const checks=[];
 for(const file of ['exercise-results.json','additional-results.json','deletion-results.json'])if(existsSync(join(dir,file)))checks.push(...JSON.parse(readFileSync(join(dir,file),'utf8')).checks);
 const after=JSON.parse(sql("select coalesce(json_agg(g order by id),'[]') from public.garments g;"));
 const previousRowsUnchanged=before.every(row=>JSON.stringify(after.find(v=>v.id===row.id))===JSON.stringify(row));
 const groups=Object.fromEntries([...new Set(checks.map(c=>c.group))].map(g=>[g,{pass:checks.filter(c=>c.group===g&&c.status==='PASS').length,fail:checks.filter(c=>c.group===g&&c.status==='FAIL').length}]));
 save(join(dir,'regression-results.json'),{groups,catalog_contract_passed:catalog,previous_rows_unchanged:previousRowsUnchanged,source_adaptations:changes,checks});
 console.log(JSON.stringify({groups,catalog_contract_passed:catalog,previous_rows_unchanged:previousRowsUnchanged},null,2));
 if(!previousRowsUnchanged||checks.some(c=>c.status==='FAIL'))process.exitCode=1;
}
