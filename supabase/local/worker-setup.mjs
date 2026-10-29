// Additive local setup: preserves the previous integration run and every existing row/photo.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync, copyFileSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT,LOCAL,DB,API,guard,docker,sql,jsonSql,sha,save,http,protectedHashes } from './integration.mjs';
import * as m from '../../build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/index.js';
const RUN='20261029-worker-2';const dir=join(ROOT,'build/supabase-local',RUN);
const target=join(LOCAL,'supabase/functions/verify-garment-photo');
assert(!existsSync(dir)&&!existsSync(target),'Existing worker/run folder; stop instead of overwrite');
const {status}=guard();mkdirSync(dir,{recursive:true});
save(join(dir,'protected-before.json'),protectedHashes());
const state=JSON.parse(sql(`select json_build_object('garments',(select coalesce(json_agg(g order by id),'[]') from public.garments g),
 'preferences',(select coalesce(json_agg(p order by user_id),'[]') from public.user_preferences p),
 'photos',(select coalesce(json_agg(json_build_object('bucket',bucket_id,'path',name) order by bucket_id,name),'[]') from storage.objects));`));
save(join(dir,'existing-state.json'),state);
const dump=docker(['exec',DB,'pg_dump','-U','postgres','-d','postgres','--format=custom'],undefined,true);
writeFileSync(join(dir,'before-worker.dump'),dump,{flag:'wx'});docker(['exec','-i',DB,'pg_restore','--list'],dump);
const photos=[];
for(const [i,p] of state.photos.entries()){
 const res=await http(`/storage/v1/object/authenticated/${p.bucket}/${p.path}`,status.SERVICE_ROLE_KEY,status.SERVICE_ROLE_KEY);
 assert.equal(res.status,200);const bytes=Buffer.from(await res.arrayBuffer());
 writeFileSync(join(dir,`existing-photo-${i}.bin`),bytes,{flag:'wx'});photos.push({...p,sha256:sha(bytes)});
}
save(join(dir,'backup-manifest.json'),{run:RUN,db_backup_sha256:sha(dump),photos,restore_executed:false});
await m.initializeImageMagick(readFileSync(join(ROOT,'build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/x86/magick.wasm')));
for(const [extension,format] of [['jpg',m.MagickFormat.Jpeg],['png',m.MagickFormat.Png],['webp',m.MagickFormat.WebP]]){
 const bytes=m.ImageMagick.read(new m.MagickColor('#bf8a55'),4,3,img=>img.write(format,data=>Uint8Array.from(data)));
 writeFileSync(join(dir,`synthetic.${extension}`),bytes,{flag:'wx'});
}
const source=join(ROOT,'supabase/functions/verify-garment-photo');mkdirSync(target,{recursive:true});
const manifest=[];
for(const name of readdirSync(source)){if(!/\.(ts|json)$/.test(name)||name.endsWith('.test.ts'))continue;
 const bytes=readFileSync(join(source,name));writeFileSync(join(target,name),bytes,{flag:'wx'});manifest.push({file:name,sha256:sha(bytes)});
}
save(join(dir,'source-manifest.json'),manifest);
console.log(JSON.stringify({run:RUN,source_files:manifest.map(v=>v.file),preserved_rows:state.garments.length,preserved_photos:photos.length,
 synthetic_formats:['jpg','png','webp'],target,sql_changes:false,cloud_connection:false},null,2));
