import * as magick from 'npm:@imagemagick/magick-wasm@0.0.45';
import { client } from './adapter.ts';
import { verifyPhoto, VerificationError, fail } from './core.ts';
import { magickDecoder } from './image.ts';

// Local serving supplies these server-side values; no keys are part of source or responses.
const api=client({url:Deno.env.get('SUPABASE_URL')!,anonKey:Deno.env.get('SUPABASE_ANON_KEY')!,serviceKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!});
let decoder: Promise<ReturnType<typeof magickDecoder>> | undefined;
function decode(bytes:Uint8Array,mime:string) {
  decoder ??= (async()=>{
    const wasm=await Deno.readFile(new URL('x86/magick.wasm',import.meta.resolve('npm:@imagemagick/magick-wasm@0.0.45')));
    await magick.initializeImageMagick(wasm);return magickDecoder(magick);
  })().catch(error=>{decoder=undefined;throw error;});
  return decoder.then(d=>d(bytes,mime));
}
const uuid=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
Deno.serve(async(request:Request)=>{
  try {
    if(request.method!=='POST')return fail('method_not_allowed',405);
    const {uid,token}=await api.authenticate(request);
    if(!request.headers.get('content-type')?.startsWith('application/json'))return fail('invalid_request',400);
    if(Number(request.headers.get('content-length'))>2048)return fail('invalid_request',400);
    // Even a chunked request cannot allocate an unbounded JSON body.
    const reader=request.body?.getReader();if(!reader)return fail('invalid_request',400);
    const parts:Uint8Array[]=[];let length=0;
    while(true){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>2048){await reader.cancel();return fail('invalid_request',400);}parts.push(value);}
    const bytes=new Uint8Array(length);let at=0;for(const p of parts){bytes.set(p,at);at+=p.length;}
    let body;try{body=JSON.parse(new TextDecoder().decode(bytes));}catch{return fail('invalid_request',400);}
    if(!body || Object.keys(body).some(k=>!['garment_id','upload_path'].includes(k)) ||
      typeof body.garment_id!=='string'||!uuid.test(body.garment_id)||typeof body.upload_path!=='string'||body.upload_path.length>200)
      return fail('invalid_request',400);
    const result=await verifyPhoto(body.garment_id,body.upload_path,uid,api.ports(uid,token,decode));
    return Response.json(result,{headers:{'Cache-Control':'no-store'}});
  } catch(error) {
    const e=error instanceof VerificationError?error:new VerificationError('verification_unavailable',503,true);
    // Never log JWTs, service keys, object paths or untrusted backend error bodies.
    return Response.json({error:e.code,retryable:e.retryable},{status:e.status,headers:{'Cache-Control':'no-store'}});
  }
});
