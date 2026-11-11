// Prepare/compare only. No schema changes, resets, or pre-existing data writes.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {ROOT,guard,sql,sha,save} from './integration.mjs';
const {status}=guard();
const mode=process.argv[2],arg=path.resolve(process.argv[3]||'');
const tables=['public.garments','public.user_preferences','storage.objects','storage.buckets'];
function snapshot(table){return JSON.parse(sql(`select coalesce(json_agg(json_build_object('id',${table==='public.user_preferences'?'user_id':'id'},'digest',md5(row_to_json(t)::text))),'[]'::json) from ${table} t;`));}
if(mode==='prepare') {
  assert(arg.startsWith(path.join(ROOT,'build/supabase-wardrobe-crud')+path.sep));
  const old=JSON.parse(fs.readFileSync(arg));assert.equal(old.api,'http://127.0.0.1:54321');
  assert(/^crud-\d+-a@example.test$/.test(old.users.a.email));
  const folder=path.join(ROOT,'build/photo-preview-regression',`preview-${Date.now()}`);fs.mkdirSync(folder,{recursive:true});
  save(path.join(folder,'private-context.json'),{api:old.api,publishableKey:status.PUBLISHABLE_KEY,users:{a:old.users.a}});
  save(path.join(folder,'baseline.json'),Object.fromEntries(tables.map(t=>[t,snapshot(t)])));
  const files=['supabase/drafts/01_database.draft.sql','supabase/drafts/02_storage_policies.draft.sql',
    ...['index.ts','adapter.ts','core.ts','image.ts'].map(f=>'supabase/functions/verify-garment-photo/'+f),
    ...['index.ts','adapter.ts','core.ts'].map(f=>'supabase/functions/garment-photo-operations/'+f),
    'lib/services/storage/indexeddb_wardrobe_repository.dart','lib/models/garment.dart'];
  save(path.join(folder,'protected.json'),Object.fromEntries(files.map(f=>[f,sha(fs.readFileSync(path.join(ROOT,f)))])));
  console.log('Prepared isolated regression context:',folder);
} else if(mode==='report') {
  assert(arg.startsWith(path.join(ROOT,'build/photo-preview-regression')+path.sep));
  const before=JSON.parse(fs.readFileSync(path.join(arg,'baseline.json'))),preservation=[];
  for(const table of tables){const current=snapshot(table),index=new Map(current.map(r=>[r.id,r.digest]));assert(before[table].every(r=>index.get(r.id)===r.digest),`Original rows changed: ${table}`);preservation.push({table,original:before[table].length,current:current.length,original_rows_unchanged:true});}
  const files=JSON.parse(fs.readFileSync(path.join(arg,'protected.json')));
  for(const [file,digest] of Object.entries(files))assert.equal(sha(fs.readFileSync(path.join(ROOT,file))),digest,file);
  const server=JSON.parse(fs.readFileSync(path.join(arg,'server-results.json')));assert.equal(server.failed,0);
  const report={date:'2026-11-05',cloud:false,original_photo_read_or_copied:false,server,preservation,protected_files_unchanged:Object.keys(files)};
  fs.writeFileSync(path.join(ROOT,'docs/supabase/photo-preview-server-results-20261105.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({passed:server.passed,failed:server.failed,preservation,protected_files:Object.keys(files).length},null,2));
} else throw new Error('Use prepare or report with a scoped fixture path');
