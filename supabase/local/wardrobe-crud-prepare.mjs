// Local-only synthetic fixtures. No reset, migrations, Storage writes or old-row edits.
import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { ROOT, API, guard, http, sql, save, sha } from './integration.mjs';

const {status} = guard();
const run = `crud-${Date.now()}`;
const folder = join(ROOT, 'build', 'supabase-wardrobe-crud', run);
mkdirSync(folder, {recursive:true});
const baseline = {};
for (const table of ['public.garments','public.user_preferences','storage.objects','storage.buckets','auth.users']) {
  baseline[table] = JSON.parse(sql(`select coalesce(json_agg(json_build_object('id',${table==='public.user_preferences'?'user_id':'id'},'digest',md5(row_to_json(t)::text))),'[]'::json) from ${table} t;`));
}
save(join(folder,'baseline.json'),baseline);
const users = {};
for (const name of ['a','b']) {
  const email = `${run}-${name}@example.test`, password = randomBytes(24).toString('base64url');
  const response = await http('/auth/v1/signup',status.PUBLISHABLE_KEY,null,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email,password})});
  assert.equal(response.status,200);
  const body=await response.json(); assert(body.access_token && body.user.id);
  users[name]={email,password,id:body.user.id};
}
save(join(folder,'private-fixtures.json'),{run,users,publishableKey:status.PUBLISHABLE_KEY,api:API});
const config = {MY_CLOSET_SUPABASE_ENABLED:true,MY_CLOSET_SERVER_WARDROBE_ENABLED:true,MY_CLOSET_SUPABASE_URL:API,MY_CLOSET_SUPABASE_PUBLISHABLE_KEY:status.PUBLISHABLE_KEY};
const configPath=join(ROOT,'config','supabase.crud.local.json');
if(existsSync(configPath)) assert.deepEqual(JSON.parse(readFileSync(configPath,'utf8')),config,'Existing CRUD config preserved; differs from local runtime');
else writeFileSync(configPath,JSON.stringify(config,null,2)+'\n',{flag:'wx'});
const protectedFiles=['lib/models/garment.dart','lib/services/wardrobe_repository.dart','lib/services/preferences_service.dart','lib/services/storage/indexeddb_wardrobe_repository.dart','supabase/drafts/01_database.draft.sql','supabase/drafts/02_storage_policies.draft.sql','supabase/functions/verify-garment-photo/index.ts'];
save(join(folder,'protected-files.json'),Object.fromEntries(protectedFiles.map(p=>[p,sha(readFileSync(join(ROOT,p)))])));
console.log(JSON.stringify({folder,api:API,db:'127.0.0.1:54322',remote_link:false,synthetic_users_created:2,baseline_counts:Object.fromEntries(Object.entries(baseline).map(([k,v])=>[k,v.length]))},null,2));
