import { BUCKET, MAX_BYTES, VerificationError, fail, type PhotoRow, type Ports } from './core.ts';
export const COLUMNS = 'id,user_id,revision,server_updated_at,photo_state,photo_path,photo_verified_at,photo_sha256,photo_size_bytes,upload_state,upload_path,upload_size_bytes,upload_expires_at,upload_error_code,retired_photo_path,retired_cleanup_after';
export type Config = {url:string;anonKey:string;serviceKey:string};
export function client(config: Config, requestFetch: typeof fetch = fetch) {
  const base = new URL(config.url);
  if (base.protocol !== 'https:' && !['127.0.0.1','localhost','kong','host.docker.internal'].includes(base.hostname) &&
      !/^supabase_kong_[a-z0-9_]+$/.test(base.hostname)) fail('server_configuration',503);
  async function call(path: string, token: string, admin = false, init: RequestInit = {}) {
    const url = new URL(path,base);
    if (url.origin !== base.origin) return fail('server_configuration',503);
    return requestFetch(url,{...init,redirect:'error',signal:AbortSignal.timeout(10_000),
      headers:{apikey:admin?config.serviceKey:config.anonKey,Authorization:`Bearer ${token}`,
        'Cache-Control':'no-cache',...init.headers}});
  }
  async function authenticate(request: Request): Promise<{uid:string;token:string}> {
    const header=request.headers.get('authorization') || '';
    if (header.length>16384 || !/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/i.test(header))
      return fail('unauthorized',401);
    const token=header.slice(7);
    let response: Response;
    try { response=await call('/auth/v1/user',token); } catch { return fail('authentication_unavailable',503,true); }
    if (response.status>=500 || response.status===429) return fail('authentication_unavailable',503,true);
    if (!response.ok) return fail('unauthorized',401);
    const user=await response.json();
    // Parse claims ONLY AFTER the Auth server has verified the token/signature/user.
    let claims;try {claims=JSON.parse(atob(token.split('.')[1].replaceAll('-','+').replaceAll('_','/')));}catch{return fail('unauthorized',401);}
    if (!user.id || user.is_anonymous !== false || claims.sub!==user.id || claims.role!=='authenticated' ||
        !(Array.isArray(claims.aud)?claims.aud.includes('authenticated'):claims.aud==='authenticated') ||
        typeof claims.exp!=='number' || claims.exp*1000<=Date.now()) return fail('unauthorized',401);
    return {uid:user.id,token};
  }
  function ports(uid: string, token: string, decode: Ports['decode']): Ports {
    async function rows(path: string, admin = false, init: RequestInit = {}) {
      let res: Response;
      try {res=await call(path,admin?config.serviceKey:token,admin,init);}catch{return fail('database_unavailable',503,true);}
      if (res.status===401||res.status===403) return fail('database_permission_denied',503,false);
      if (res.status===400) return fail('database_constraint',503,false);
      if (!res.ok) return fail('database_unavailable',503,true);
      return await res.json() as PhotoRow[];
    }
    return {
      now:()=>Date.now(),decode,
      async read(id) {
        const q=new URLSearchParams({id:`eq.${id}`,user_id:`eq.${uid}`,select:COLUMNS});
        const values=await rows(`/rest/v1/garments?${q}`);return values[0]||null;
      },
      async cas(row,patch,live=false) {
        const q=new URLSearchParams({id:`eq.${row.id}`,user_id:`eq.${uid}`,revision:`eq.${row.revision}`,
          upload_state:`eq.${row.upload_state}`,upload_path:row.upload_path?`eq.${row.upload_path}`:'is.null',select:COLUMNS});
        if(live)q.set('upload_expires_at',`gt.${new Date().toISOString()}`);
        const values=await rows(`/rest/v1/garments?${q}`,true,{method:'PATCH',
          headers:{'Content-Type':'application/json',Prefer:'return=representation'},body:JSON.stringify(patch)});
        return values[0]||null;
      },
      async object(path) {
        const encoded=path.split('/').map(encodeURIComponent).join('/');
        let res: Response;
        try {res=await call(`/storage/v1/object/authenticated/${BUCKET}/${encoded}`,config.serviceKey,true);}
        catch {return fail('storage_unavailable',503,true);}
        if(!res.ok) {
          let body: any={};try{body=await res.json();}catch{/* do not log backend payloads */}
          if(res.status===404 || String(body.statusCode)==='404' || ['NoSuchKey','NotFound'].includes(body.code))
            return fail('not_found',404,true);
          return fail('storage_unavailable',503,true);
        }
        const n=Number(res.headers.get('content-length'));
        if(n>MAX_BYTES){await res.body?.cancel();return fail('size_mismatch');}
        if(!res.body)return fail('not_found',404,true);
        const reader=res.body.getReader();const chunks:Uint8Array[]=[];let total=0;
        try {while(true){const {value,done}=await reader.read();if(done)break;total+=value.length;
          if(total>MAX_BYTES){await reader.cancel();return fail('size_mismatch');}chunks.push(value);}}
        catch(e){if(e instanceof VerificationError)throw e;return fail('storage_unavailable',503,true);}
        finally{reader.releaseLock();}
        const bytes=new Uint8Array(total);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
        return {bytes,etag:res.headers.get('etag'),modified:res.headers.get('last-modified')};
      },
    };
  }
  return {authenticate,ports};
}
