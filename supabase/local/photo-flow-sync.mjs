// Only the new operations function is copied. Original worker/SQL/config untouched.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync,existsSync} from 'node:fs';
import {join} from 'node:path';
import {ROOT,LOCAL,guard,sha} from './integration.mjs';
guard();
for(const file of ['index.ts','core.ts','adapter.ts','image.ts']) {
  assert.equal(sha(readFileSync(join(ROOT,'supabase/functions/verify-garment-photo',file))),sha(readFileSync(join(LOCAL,'supabase/functions/verify-garment-photo',file))),'Existing verification function differs; stop');
}
const target=join(LOCAL,'supabase/functions/garment-photo-operations');
if(!existsSync(target))mkdirSync(target);
for(const file of ['index.ts','core.ts','adapter.ts']) {
  const source=readFileSync(join(ROOT,'supabase/functions/garment-photo-operations',file));
  const destination=join(target,file);
  if(existsSync(destination)&&sha(readFileSync(destination))!==sha(source)) {
    const backup=join(ROOT,'build',`photo-operations-source-${Date.now()}-${file}`);
    writeFileSync(backup,readFileSync(destination),{flag:'wx'});
  }
  writeFileSync(destination,source);
}
console.log('New local operations function synced; original worker, SQL and config unchanged.');
