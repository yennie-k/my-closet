import test from 'node:test';
import assert from 'node:assert/strict';
import {operate,validateCommand,type OperationsPorts} from '../functions/garment-photo-operations/core.ts';
import type {PhotoRow} from '../functions/verify-garment-photo/core.ts';
const uid='11111111-1111-4111-8111-111111111111',id='22222222-2222-4222-8222-222222222222';
const path=`${uid}/${id}/${'a'.repeat(64)}.jpg`;
const previous=`${uid}/${id}/${'b'.repeat(64)}.png`;
const now=Date.parse('2026-11-02T00:00:00Z');
function fixture(patch:Partial<PhotoRow>={}) {
  let row:PhotoRow={id,user_id:uid,revision:1,server_updated_at:new Date(now).toISOString(),photo_state:'pending',photo_path:null,photo_sha256:null,photo_size_bytes:null,photo_verified_at:null,upload_state:'none',upload_path:null,upload_size_bytes:null,upload_expires_at:null,upload_error_code:null,retired_photo_path:null,retired_cleanup_after:null,...patch};
  let removed:string[]=[];let denyDelete=false;let casFail=false;let verifies=0;
  const ports:OperationsPorts={now:()=>now,read:async()=>({...row}),cas:async(before,values)=>{if(casFail||row.revision!==before.revision)return null;row={...row,...values,revision:row.revision+1};return {...row};},removeUnreferenced:async p=>{if(denyDelete)throw Object.assign(new Error('object_referenced'),{code:'object_referenced'});removed.push(p);},verify:async(g,p)=>{assert.equal(g,id);assert.equal(p,path);verifies++;return {status:'ready'};}};
  return {ports,get row(){return row;},get removed(){return removed;},set deny(v:boolean){denyDelete=v;},set casFail(v:boolean){casFail=v;},get verifies(){return verifies;}};
}
const command=(action:string,extra:Record<string,unknown>={})=>validateCommand({action,garment_id:id,revision:1,...extra});
const rejected=(code:string)=>({code:actual}:{code:string})=>actual===code;
test('strict request rejects client attestation, oversized/empty size, unknown MIME and prototype actions',()=>{
  for(const extra of [{ready:true},{size_bytes:0},{size_bytes:2097153},{mime_type:'image/gif'},{action:'__proto__'}])assert.throws(()=>command('reserve',{sha256:'a'.repeat(64),size_bytes:100,mime_type:'image/jpeg',...extra}),rejected('invalid_request'));
});
test('reserve allocates exact scoped path and bounded TTL without ready facts',async()=>{
  const f=fixture();await operate(command('reserve',{sha256:'a'.repeat(64),size_bytes:100,mime_type:'image/jpeg'}),uid,f.ports);
  assert.equal(f.row.upload_path,path);assert.equal(f.row.upload_state,'reserved');assert.equal(f.row.photo_state,'pending');assert.equal(f.row.photo_verified_at,null);assert.equal(Date.parse(f.row.upload_expires_at!)-now,600000);
});
test('same reservation is idempotent across stale request revisions',async()=>{
  const f=fixture({revision:4,upload_state:'reserved',upload_path:path,upload_size_bytes:100,upload_expires_at:new Date(now+60000).toISOString()});
  await operate(command('reserve',{sha256:'a'.repeat(64),size_bytes:100,mime_type:'image/jpeg'}),uid,f.ports);assert.equal(f.row.revision,4);
});
test('already verified same bytes does not retire or reserve again',async()=>{
  const f=fixture({photo_state:'ready',photo_path:path,photo_size_bytes:100,photo_verified_at:new Date(now).toISOString()});
  await operate(command('reserve',{sha256:'a'.repeat(64),size_bytes:100,mime_type:'image/jpeg'}),uid,f.ports);assert.equal(f.row.revision,1);assert.equal(f.row.upload_path,null);
});
test('foreign user cannot reserve or invoke verifier',async()=>{
  const f=fixture();await assert.rejects(operate(command('verify',{upload_path:path}),'other',f.ports),rejected('not_found_or_not_owned'));assert.equal(f.verifies,0);
});
test('retired slot blocks next candidate; active picture preserved',async()=>{
  const f=fixture({photo_state:'ready',photo_path:previous,retired_photo_path:path});
  await assert.rejects(operate(command('reserve',{sha256:'c'.repeat(64),size_bytes:100,mime_type:'image/jpeg'}),uid,f.ports),rejected('cleanup_pending'));assert.equal(f.row.photo_path,previous);
});
test('reservation CAS conflict makes no changes',async()=>{
  const f=fixture();f.casFail=true;await assert.rejects(operate(command('reserve',{sha256:'a'.repeat(64),size_bytes:100,mime_type:'image/jpeg'}),uid,f.ports),rejected('revision_conflict'));assert.equal(f.row.upload_path,null);
});
test('fresh checking lease cannot be cancelled',async()=>{
  const f=fixture({upload_path:path,upload_state:'checking'});await assert.rejects(operate(command('cancel',{path}),uid,f.ports),rejected('verification_in_progress'));assert.equal(f.removed.length,0);
});
test('cancel of stale/failed candidate preserves active image and clears only candidate',async()=>{
  const f=fixture({photo_state:'ready',photo_path:previous,upload_path:path,upload_state:'failed'});await operate(command('cancel',{path}),uid,f.ports);
  assert.equal(f.row.photo_path,previous);assert.equal(f.row.upload_path,null);assert.equal(f.row.retired_photo_path,null);assert.deepEqual(f.removed,[path]);
});
test('failed physical cleanup keeps durable candidate path in existing cleanup slot',async()=>{
  const f=fixture({photo_state:'ready',photo_path:previous,upload_path:path,upload_state:'failed'});f.deny=true;
  await assert.rejects(operate(command('cancel',{path}),uid,f.ports));assert.equal(f.row.photo_path,previous);assert.equal(f.row.retired_photo_path,path);assert.equal(f.row.upload_path,null);
  f.deny=false;await operate(command('cleanup',{path,revision:f.row.revision}),uid,f.ports);assert.equal(f.row.retired_photo_path,null);
});
test('cancel cannot delete active image',async()=>{
  const f=fixture({photo_state:'ready',photo_path:path});await assert.rejects(operate(command('cancel',{path}),uid,f.ports),rejected('object_referenced'));assert.equal(f.removed.length,0);
});
test('remove schedules 25h retirement without physical deletion',async()=>{
  const f=fixture({photo_state:'ready',photo_path:path,photo_sha256:'a'.repeat(64),photo_size_bytes:100,photo_verified_at:new Date(now).toISOString()});
  await operate(command('remove',{path}),uid,f.ports);assert.equal(f.row.photo_state,'pending');assert.equal(f.row.photo_path,null);assert.equal(f.row.retired_photo_path,path);assert.equal(Date.parse(f.row.retired_cleanup_after!)-now,25*3600000);assert.equal(f.removed.length,0);
  await operate(command('remove',{path}),uid,f.ports);assert.equal(f.row.revision,2);
});
test('protected retired photo cannot be cleaned early',async()=>{
  const f=fixture({retired_photo_path:path,retired_cleanup_after:new Date(now+1000).toISOString()});await assert.rejects(operate(command('cleanup',{path}),uid,f.ports),rejected('cleanup_not_due'));assert.equal(f.removed.length,0);
});
test('cleanup CAS conflict retains path for safe retry after object deletion',async()=>{
  const f=fixture({retired_photo_path:path,retired_cleanup_after:new Date(now-1000).toISOString()});f.casFail=true;
  await assert.rejects(operate(command('cleanup',{path}),uid,f.ports),rejected('revision_conflict'));assert.equal(f.row.retired_photo_path,path);assert.deepEqual(f.removed,[path]);
});
test('verify delegates only exact owned active/candidate path',async()=>{
  const f=fixture({upload_path:path,upload_state:'client_confirmed'});await operate(command('verify',{upload_path:path}),uid,f.ports);assert.equal(f.verifies,1);
  await assert.rejects(operate(command('verify',{upload_path:previous}),uid,f.ports),rejected('reservation_mismatch'));assert.equal(f.verifies,1);
});
