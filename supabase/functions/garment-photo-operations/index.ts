import {VerificationError} from '../verify-garment-photo/core.ts';
import {operationsClient} from './adapter.ts';
import {operate,validateCommand} from './core.ts';

const api=operationsClient({url:Deno.env.get('SUPABASE_URL')!,anonKey:Deno.env.get('SUPABASE_ANON_KEY')!,serviceKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!});
const allowed=new Set(['http://localhost:8081','http://127.0.0.1:8081']);
Deno.serve(async(request:Request)=>{
  const origin=request.headers.get('origin');
  const headers:Record<string,string>={'Cache-Control':'no-store',Vary:'Origin'};
  if(origin&&!allowed.has(origin))return Response.json({error:'origin_not_allowed',retryable:false},{status:403,headers});
  if(origin)headers['Access-Control-Allow-Origin']=origin;
  headers['Access-Control-Allow-Methods']='POST, OPTIONS';
  headers['Access-Control-Allow-Headers']='authorization, apikey, x-client-info, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version';
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
  try {
    if(request.method!=='POST')throw new VerificationError('method_not_allowed',405);
    const {uid,token}=await api.authenticate(request);
    if(!request.headers.get('content-type')?.startsWith('application/json'))throw new VerificationError('invalid_request',400);
    const reader=request.body?.getReader();if(!reader)throw new VerificationError('invalid_request',400);
    const chunks:Uint8Array[]=[];let length=0;
    while(true){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>2048){await reader.cancel();throw new VerificationError('invalid_request',400);}chunks.push(value);}
    const bytes=new Uint8Array(length);let at=0;for(const c of chunks){bytes.set(c,at);at+=c.length;}
    let body;try{body=JSON.parse(new TextDecoder().decode(bytes));}catch{throw new VerificationError('invalid_request',400);}
    return Response.json(await operate(validateCommand(body),uid,api.ports(uid,token)),{headers});
  } catch(error) {
    const e=error instanceof VerificationError?error:new VerificationError('operations_unavailable',503,true);
    return Response.json({error:e.code,retryable:e.retryable},{status:e.status,headers});
  }
});
