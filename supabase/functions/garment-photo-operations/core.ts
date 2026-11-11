// Existing schema/state machine only. Privileged writes are photo-column CAS;
// all physical deletes must use the caller's JWT and existing Storage RLS.
import {fail, LEASE_MS, MAX_BYTES, type PhotoRow} from '../verify-garment-photo/core.ts';

export type Command = {action:string;garment_id:string;revision:number;sha256?:string;size_bytes?:number;mime_type?:string;path?:string;upload_path?:string};
export interface OperationsPorts {
  now():number;
  read(id:string):Promise<PhotoRow|null>;
  cas(row:PhotoRow,patch:Record<string,unknown>):Promise<PhotoRow|null>;
  removeUnreferenced(path:string):Promise<void>;
  verify(id:string,path:string):Promise<unknown>;
}
const extensions:Record<string,string>={'image/jpeg':'jpg','image/png':'png','image/webp':'webp'};
const uuid=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
export function validateCommand(value:any):Command {
  const fields:Record<string,string[]>={reserve:['sha256','size_bytes','mime_type'],verify:['upload_path'],cancel:['path'],remove:['path'],cleanup:['path']};
  if(!value || typeof value!=='object'||Array.isArray(value)||typeof value.action!=='string'||!Object.hasOwn(fields,value.action)||
      Object.keys(value).some(k=>!['action','garment_id','revision',...fields[value.action]].includes(k))||
      typeof value.garment_id!=='string'||!uuid.test(value.garment_id)||!Number.isSafeInteger(value.revision)||value.revision<1)fail('invalid_request',400);
  if(value.action==='reserve') {
    if(typeof value.sha256!=='string'||!/^[0-9a-f]{64}$/.test(value.sha256)||!Number.isSafeInteger(value.size_bytes)||value.size_bytes<1||value.size_bytes>MAX_BYTES||!Object.hasOwn(extensions,value.mime_type))fail('invalid_request',400);
  } else {
    const path=value.action==='verify'?value.upload_path:value.path;
    if(typeof path!=='string'||path.length>200)fail('invalid_request',400);
  }
  return value;
}
export async function operate(command:Command,uid:string,p:OperationsPorts):Promise<unknown> {
  const row=await p.read(command.garment_id);
  if(!row||row.user_id!==uid)fail('not_found_or_not_owned',404);
  const scoped=(path:string)=>new RegExp(`^${uid}/${row.id}/[0-9a-f]{64}[.](jpg|png|webp)$`).test(path);
  const matchRevision=()=>{if(row.revision!==command.revision)fail('revision_conflict',409,true);};
  async function patch(value:Record<string,unknown>) {
    const next=await p.cas(row!,value);if(!next)fail('revision_conflict',409,true);return next;
  }
  const result=(next:PhotoRow,status:string)=>({status,revision:next.revision,upload_path:next.upload_path,cleanup_after:next.retired_cleanup_after});
  if(command.action==='verify') {
    if(!scoped(command.upload_path!)||!(row.upload_path===command.upload_path||row.photo_path===command.upload_path))fail('reservation_mismatch',409);
    return p.verify(row.id,command.upload_path!); // original Edge Function, same user JWT
  }
  if(command.action==='reserve') {
    const path=`${uid}/${row.id}/${command.sha256}.${extensions[command.mime_type!]}`;
    if(row.photo_state==='ready'&&row.photo_path===path&&row.photo_verified_at&&row.photo_size_bytes===command.size_bytes)return result(row,'already_verified');
    if(row.upload_path===path&&row.upload_size_bytes===command.size_bytes&&['reserved','client_confirmed','checking'].includes(row.upload_state)&&Date.parse(row.upload_expires_at||'')>p.now())return result(row,'already_reserved');
    matchRevision();
    if(row.retired_photo_path)fail('cleanup_pending',409);
    if(row.upload_path)fail('pending_upload_exists',409);
    return result(await patch({upload_state:'reserved',upload_path:path,upload_size_bytes:command.size_bytes,upload_expires_at:new Date(p.now()+10*60_000).toISOString(),upload_error_code:null}),'reserved');
  }
  const path=command.path!;if(!scoped(path))fail('reservation_mismatch',409);
  if(command.action==='cancel') {
    if(row.photo_path===path)fail('object_referenced',409);
    if(row.retired_photo_path&&row.retired_photo_path!==path)fail('cleanup_pending',409);
    if(row.retired_photo_path===path&&Date.parse(row.retired_cleanup_after||'')>p.now())fail('cleanup_not_due',409);
    if(row.upload_path!==null&&row.upload_path!==path)fail('reservation_mismatch',409);
    let next=row;
    if(row.upload_path) {
      matchRevision();
      if(row.upload_state==='checking'&&p.now()-Date.parse(row.server_updated_at)<=LEASE_MS)fail('verification_in_progress',409,true);
      // Reuse the existing cleanup slot for this unverified candidate. It has
      // no active-photo grace period; failures remain discoverable after reload.
      next=await patch({upload_state:'none',upload_path:null,upload_size_bytes:null,upload_expires_at:null,upload_error_code:null,
        retired_photo_path:path,retired_cleanup_after:new Date(p.now()).toISOString()});
    }
    // If a concurrent reservation/reference appears, Storage RLS refuses the
    // delete. Never retry deletion using service-role privileges.
    await p.removeUnreferenced(path);
    if(next.retired_photo_path===path) {
      const cleared=await p.cas(next,{retired_photo_path:null,retired_cleanup_after:null});
      if(!cleared)fail('revision_conflict',409,true);next=cleared;
    }
    return result(next,'cancelled');
  }
  if(command.action==='remove') {
    if(row.photo_path===null&&row.retired_photo_path===path)return result(row,'removal_scheduled');
    matchRevision();
    if(row.photo_state!=='ready'||row.photo_path!==path)fail('reservation_mismatch',409);
    if(row.upload_path||row.retired_photo_path)fail('cleanup_pending',409);
    return result(await patch({photo_state:'pending',photo_path:null,photo_sha256:null,photo_size_bytes:null,photo_verified_at:null,
      retired_photo_path:path,retired_cleanup_after:new Date(p.now()+25*3600_000).toISOString()}),'removal_scheduled');
  }
  if(command.action==='cleanup') {
    if(!row.retired_photo_path)return result(row,'already_clean');
    matchRevision();
    if(row.retired_photo_path!==path)fail('reservation_mismatch',409);
    if(!row.retired_cleanup_after||Date.parse(row.retired_cleanup_after)>p.now())fail('cleanup_not_due',409);
    await p.removeUnreferenced(path);
    return result(await patch({retired_photo_path:null,retired_cleanup_after:null}),'cleaned');
  }
  return fail('invalid_request',400);
}
