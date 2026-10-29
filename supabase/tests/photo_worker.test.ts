// Deterministic workflow races; real pinned decoder, injected I/O. No cloud calls.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as m from '../../build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/index.js';
import { verifyPhoto,digest,VerificationError,LEASE_MS,type PhotoRow,type Ports } from '../functions/verify-garment-photo/core.ts';
import { magickDecoder } from '../functions/verify-garment-photo/image.ts';
import { client } from '../functions/verify-garment-photo/adapter.ts';
await m.initializeImageMagick(readFileSync(new URL('../../build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/x86/magick.wasm',import.meta.url)));
const decode=magickDecoder(m);
const uid='00000000-0000-4000-8000-000000000001',id='00000000-0000-4000-8000-000000000002';
const png=new Uint8Array(readFileSync(new URL('../../build/supabase-local/20261029-worker-2/synthetic.png',import.meta.url)));
async function fixture(bytes=png,ext='png') {
 const path=`${uid}/${id}/${await digest(bytes)}.${ext}`;let now=Date.now();
 let row:PhotoRow={id,user_id:uid,revision:1,server_updated_at:new Date(now).toISOString(),photo_state:'pending',photo_path:null,photo_verified_at:null,photo_sha256:null,photo_size_bytes:null,
  upload_state:'client_confirmed',upload_path:path,upload_size_bytes:bytes.length,upload_expires_at:new Date(now+600000).toISOString(),upload_error_code:null,retired_photo_path:null,retired_cleanup_after:null};
 let reads=0,commits=0;
 const ports:Ports={now:()=>now,read:async()=>({...row}),cas:async(old,patch,live)=>{
  if(old.revision!==row.revision||old.upload_path!==row.upload_path||old.upload_state!==row.upload_state||
   (live&&Date.parse(row.upload_expires_at!)<=now))return null;
  row={...row,...patch,revision:row.revision+1,server_updated_at:new Date(now).toISOString()} as PhotoRow;
  if(patch.photo_state==='ready')commits++;return {...row};
 },object:async()=>{reads++;return {bytes,etag:'one',modified:'one'};},decode};
 return {path,ports,row:()=>row,change:(patch:Partial<PhotoRow>)=>{row={...row,...patch};},advance:(ms:number)=>{now+=ms;},reads:()=>reads,commits:()=>commits};
}
const rejects=(fn:()=>Promise<unknown>,code:string)=>assert.rejects(fn,(e:unknown)=>e instanceof VerificationError&&e.code===code);
for(const ext of ['jpg','png','webp'])test(`actual ${ext} decode and ready attestation`,async()=>{
 const bytes=new Uint8Array(readFileSync(new URL(`../../build/supabase-local/20261029-worker-2/synthetic.${ext}`,import.meta.url)));
 const f=await fixture(bytes,ext);const r=await verifyPhoto(id,f.path,uid,f.ports);assert.equal(r.status,'ready');assert.equal(f.row().photo_sha256,await digest(bytes));assert.equal(f.reads(),2);
});
test('size mismatch stays non-ready',async()=>{const f=await fixture();f.change({upload_size_bytes:png.length+1});await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'size_mismatch');assert.equal(f.row().photo_state,'pending');assert.equal(f.row().upload_state,'failed');});
test('content hash mismatch stays non-ready',async()=>{const f=await fixture();const p=f.path.replace(/[a-f0-9]{64}[.]png$/,'a'.repeat(64)+'.png');f.change({upload_path:p});await rejects(()=>verifyPhoto(id,p,uid,f.ports),'hash_mismatch');assert.equal(f.commits(),0);});
test('actual PNG with JPG extension rejected',async()=>{const f=await fixture(png,'jpg');await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'mime_mismatch');});
test('corrupt PNG with correct hash is rejected before ready',async()=>{const bad=png.slice();bad[bad.length-1]^=1;const f=await fixture(bad);await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'invalid_image');assert.equal(f.commits(),0);});
test('wrong owner denied before privileged object access',async()=>{const f=await fixture();await rejects(()=>verifyPhoto(id,f.path,'00000000-0000-4000-8000-000000000003',f.ports),'not_found_or_not_owned');assert.equal(f.reads(),0);});
test('reservation mismatch and unconfirmed slot rejected',async()=>{const f=await fixture();await rejects(()=>verifyPhoto(id,f.path+'x',uid,f.ports),'reservation_mismatch');f.change({upload_state:'reserved'});await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'client_confirmation_required');});
test('expired reservation rejected',async()=>{const f=await fixture();f.advance(600001);await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'expired');assert.equal(f.reads(),0);});
test('missing object can be retried safely',async()=>{const f=await fixture();const object=f.ports.object;f.ports.object=async()=>{throw new VerificationError('not_found',404,true);};await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'not_found');assert.equal(f.row().photo_state,'pending');f.ports.object=object;assert.equal((await verifyPhoto(id,f.path,uid,f.ports)).status,'ready');});
test('object replacement between reads rejected',async()=>{const f=await fixture();let n=0;const object=f.ports.object;f.ports.object=async p=>{const value=await object(p);if(++n===2)return {...value,etag:'new'};return value;};await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'object_changed');assert.equal(f.commits(),0);});
test('object deletion after decode rejected',async()=>{const f=await fixture();let n=0;const object=f.ports.object;f.ports.object=async p=>{if(++n===2)throw new VerificationError('not_found',404,true);return object(p);};await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'not_found');assert.equal(f.commits(),0);});
test('reservation/revision change during decode never overwritten',async()=>{const f=await fixture();f.ports.decode=async(b,mime)=>{const info=await decode(b,mime);f.change({revision:3,upload_path:f.path.replace('.png','.webp'),upload_state:'reserved'});return info;};await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'revision_conflict');assert.equal(f.row().upload_state,'reserved');assert.equal(f.commits(),0);});
test('expiry during validation never commits ready',async()=>{const f=await fixture();f.ports.decode=async(b,mime)=>{const info=await decode(b,mime);f.advance(600001);return info;};await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'expired');assert.equal(f.commits(),0);});
test('duplicate completed request does not increment revision',async()=>{const f=await fixture();await verifyPhoto(id,f.path,uid,f.ports);const rev=f.row().revision;const r=await verifyPhoto(id,f.path,uid,f.ports);assert.equal(r.already_verified,true);assert.equal(f.row().revision,rev);assert.equal(f.commits(),1);});
test('concurrent requests only one worker owns the lease',async()=>{
 const f=await fixture();let release!:()=>void,entered!:()=>void;const gate=new Promise<void>(r=>release=r),signal=new Promise<void>(r=>entered=r);
 f.ports.decode=async(b,mime)=>{entered();await gate;return decode(b,mime);};
 const first=verifyPhoto(id,f.path,uid,f.ports);await signal;await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'verification_in_progress');release();await first;assert.equal(f.commits(),1);
});
test('stale checking lease recovers after a terminated process',async()=>{const f=await fixture();f.change({upload_state:'checking',server_updated_at:new Date(f.ports.now()-LEASE_MS-1).toISOString()});await verifyPhoto(id,f.path,uid,f.ports);assert.equal(f.commits(),1);});
test('old worker cannot overwrite a takeover attestation',async()=>{
 const f=await fixture();let release!:()=>void,entered!:()=>void;const gate=new Promise<void>(r=>release=r),signal=new Promise<void>(r=>entered=r);let calls=0;
 f.ports.decode=async(b,mime)=>{if(++calls===1){entered();await gate;}return decode(b,mime);};
 const first=verifyPhoto(id,f.path,uid,f.ports);await signal;f.advance(LEASE_MS+1);const second=await verifyPhoto(id,f.path,uid,f.ports);assert.equal(second.status,'ready');release();await first;assert.equal(f.commits(),1);
});
test('transient storage outage releases own lease for retry',async()=>{const f=await fixture();const object=f.ports.object;f.ports.object=async()=>{throw new VerificationError('storage_unavailable',503,true);};await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'storage_unavailable');assert.equal(f.row().upload_state,'client_confirmed');f.ports.object=object;await verifyPhoto(id,f.path,uid,f.ports);});
test('failed terminal validation is idempotent and does not redownload',async()=>{const f=await fixture();f.change({upload_size_bytes:png.length+1});await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'size_mismatch');const rev=f.row().revision;await rejects(()=>verifyPhoto(id,f.path,uid,f.ports),'size_mismatch');assert.equal(f.row().revision,rev);});
test('auth adapter rejects missing JWT before a network call',async()=>{let calls=0;const api=client({url:'http://127.0.0.1:54321',anonKey:'unused',serviceKey:'unused'},async()=>{calls++;return new Response();});await rejects(()=>api.authenticate(new Request('http://localhost')),'unauthorized');assert.equal(calls,0);});
test('server permission failure is not classified as a normal retry',async()=>{const api=client({url:'http://127.0.0.1:54321',anonKey:'unused',serviceKey:'unused'},async()=>new Response('{}',{status:403}));await assert.rejects(()=>api.ports(uid,'unused',decode).read(id),(e:unknown)=>e instanceof VerificationError&&e.code==='database_permission_denied'&&!e.retryable);});
test('database outage is retryable',async()=>{const api=client({url:'http://127.0.0.1:54321',anonKey:'unused',serviceKey:'unused'},async()=>new Response('{}',{status:503}));await assert.rejects(()=>api.ports(uid,'unused',decode).read(id),(e:unknown)=>e instanceof VerificationError&&e.code==='database_unavailable'&&e.retryable);});
