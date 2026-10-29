// Sync only files created by this worker run; preserve the previous source revision.
import assert from 'node:assert/strict';
import { readFileSync,writeFileSync,mkdirSync,existsSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT,LOCAL,guard,sha,save } from './integration.mjs';
guard();const dir=join(ROOT,'build/supabase-local/20261029-worker-2');
const revision=process.argv[2]||'1';assert(/^[0-9]+$/.test(revision));
const backup=join(dir,`source-before-sync-${revision}`);assert(!existsSync(backup));mkdirSync(backup);
const manifest=JSON.parse(readFileSync(join(dir,revision==='1'?'source-manifest.json':`synced-${Number(revision)-1}.json`),'utf8'));
const next=[];
for(const entry of manifest){const path=join(LOCAL,'supabase/functions/verify-garment-photo',entry.file);const old=readFileSync(path);
 assert.equal(sha(old),entry.sha256,'External worker source was changed by someone else; stop');
 writeFileSync(join(backup,entry.file),old,{flag:'wx'});const bytes=readFileSync(join(ROOT,'supabase/functions/verify-garment-photo',entry.file));
 writeFileSync(path,bytes);next.push({file:entry.file,sha256:sha(bytes)});
}
save(join(dir,`synced-${revision}.json`),next);console.log('Synced only this run\'s worker source files; SQL/config/data untouched.');
