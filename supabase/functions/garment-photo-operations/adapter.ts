import {client, type Config} from '../verify-garment-photo/adapter.ts';
import {BUCKET,fail} from '../verify-garment-photo/core.ts';
import type {OperationsPorts} from './core.ts';

export function operationsClient(config:Config,requestFetch:typeof fetch=fetch) {
  const api=client(config,requestFetch),base=new URL(config.url);
  return {
    authenticate:api.authenticate,
    ports(uid:string,token:string):OperationsPorts {
      const existing=api.ports(uid,token,async()=>fail('invalid_request',400));
      async function userCall(path:string,init:RequestInit={}) {
        const url=new URL(path,base);if(url.origin!==base.origin)fail('server_configuration',503);
        try{return await requestFetch(url,{...init,redirect:'error',signal:AbortSignal.timeout(70_000),headers:{apikey:config.anonKey,Authorization:`Bearer ${token}`,...init.headers}});}
        catch{return fail('storage_unavailable',503,true);}
      }
      async function absent(path:string) {
        const encoded=path.split('/').map(encodeURIComponent).join('/');
        const res=await userCall(`/storage/v1/object/authenticated/${BUCKET}/${encoded}`);
        if(res.ok){await res.body?.cancel();return false;}
        const body=await res.json().catch(()=>({}));
        if(res.status===404||String(body.statusCode)==='404'||['NoSuchKey','NotFound'].includes(body.code))return true;
        return fail('storage_unavailable',503,true);
      }
      return {
        now:existing.now,read:existing.read,cas:existing.cas,
        async removeUnreferenced(path) {
          const res=await userCall(`/storage/v1/object/${BUCKET}`,{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefixes:[path]})});
          if(!res.ok)fail('cleanup_unavailable',503,true);
          if(!await absent(path))fail('object_referenced',409,true);
        },
        async verify(id,path) {
          const res=await userCall('/functions/v1/verify-garment-photo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({garment_id:id,upload_path:path})});
          const body=await res.json().catch(()=>({error:'verification_unavailable',retryable:true}));
          if(!res.ok)fail(typeof body.error==='string'?body.error:'verification_unavailable',res.status,body.retryable===true);
          // Never forward upstream headers, credentials or arbitrary backend data.
          if(body.status!=='ready')fail('verification_unavailable',503,true);
          return {status:'ready',garment_id:id,revision:body.revision,already_verified:body.already_verified===true};
        },
      };
    },
  };
}
