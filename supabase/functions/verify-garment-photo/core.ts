// Pure verification workflow. All privileged I/O is injected and guarded by CAS.
export const BUCKET = 'garment-photos';
export const MAX_BYTES = 2_097_152;
export const LEASE_MS = 60_000; // A stale process can never commit after a takeover revision.
export type PhotoRow = {
  id: string; user_id: string; revision: number; server_updated_at: string;
  photo_state: string; photo_path: string | null; photo_verified_at: string | null;
  photo_sha256: string | null; photo_size_bytes: number | null;
  upload_state: string; upload_path: string | null; upload_size_bytes: number | null;
  upload_expires_at: string | null; upload_error_code: string | null;
  retired_photo_path: string | null; retired_cleanup_after: string | null;
};
export type ImageInfo = { mime: string; width: number; height: number };
export type StoredObject = { bytes: Uint8Array; etag: string | null; modified: string | null };
export interface Ports {
  now(): number;
  read(id: string): Promise<PhotoRow | null>; // MUST use the verified caller's RLS context.
  cas(row: PhotoRow, patch: Record<string, unknown>, live?: boolean): Promise<PhotoRow | null>;
  object(path: string): Promise<StoredObject>; // fixed bucket; bounded, uncached GET.
  decode(bytes: Uint8Array, mime: string): Promise<ImageInfo>;
}
export class VerificationError extends Error {
  code: string; status: number; retryable: boolean;
  constructor(code: string, status = 422, retryable = false) {
    super(code); this.name = 'VerificationError'; this.code = code;
    this.status = status; this.retryable = retryable;
  }
}
export const fail = (code: string, status = 422, retryable = false): never => {
  throw new VerificationError(code, status, retryable);
};
export async function digest(bytes: Uint8Array): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes as BufferSource)))
    .map(v => v.toString(16).padStart(2, '0')).join('');
}
export function sniff(bytes: Uint8Array): string {
  if (bytes.length >= 8 && [137,80,78,71,13,10,26,10].every((v,i) => bytes[i] === v)) return 'image/png';
  if (bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return 'image/jpeg';
  if (bytes.length >= 12 && new TextDecoder().decode(bytes.subarray(0,4)) === 'RIFF' &&
      new TextDecoder().decode(bytes.subarray(8,12)) === 'WEBP') return 'image/webp';
  return fail('invalid_image');
}
export function containerCheck(b: Uint8Array, mime: string) {
  const v=new DataView(b.buffer,b.byteOffset,b.byteLength);
  if(mime==='image/jpeg') {
    if(b.length<4 || b[b.length-2]!==255 || b[b.length-1]!==217) fail('invalid_image');
  } else if(mime==='image/png') {
    let offset=8,ended=false;
    while(offset+12<=b.length) {
      const n=v.getUint32(offset);if(n>b.length-offset-12)fail('invalid_image');
      const name=new TextDecoder().decode(b.subarray(offset+4,offset+8));
      if(name==='acTL')fail('invalid_image'); // animated images are outside this MVP
      let crc=0xffffffff;
      for(const byte of b.subarray(offset+4,offset+8+n)){crc^=byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}
      if(((crc^0xffffffff)>>>0)!==v.getUint32(offset+8+n))fail('invalid_image');
      offset+=n+12;if(name==='IEND'){if(n!==0)fail('invalid_image');ended=true;break;}
    }
    if(!ended||offset!==b.length)fail('invalid_image');
  } else if(mime==='image/webp') {
    if(v.getUint32(4,true)+8!==b.length)fail('invalid_image');
    let offset=12,pixels=false;
    while(offset+8<=b.length){const name=new TextDecoder().decode(b.subarray(offset,offset+4));const n=v.getUint32(offset+4,true);
      if(n>b.length-offset-8 || ['ANIM','ANMF'].includes(name))fail('invalid_image');
      if(name==='VP8 '||name==='VP8L')pixels=true;offset+=8+n+(n%2);}
    if(offset!==b.length||!pixels)fail('invalid_image');
  }
}
const MIME: Record<string,string> = { jpg:'image/jpeg', png:'image/png', webp:'image/webp' };
const DB_ERRORS = new Set(['not_found','hash_mismatch','size_mismatch','mime_mismatch','invalid_image','expired','cancelled']);
function retryableCode(code: string) { return code === 'not_found'; }
function expired(row: PhotoRow, now: number) {
  return !row.upload_expires_at || !Number.isFinite(Date.parse(row.upload_expires_at)) || Date.parse(row.upload_expires_at) <= now;
}
function ready(row: PhotoRow, path: string) {
  return row.photo_state === 'ready' && row.photo_path === path && !!row.photo_verified_at;
}
function result(row: PhotoRow, already = false) {
  return { status:'ready', garment_id:row.id, revision:row.revision,
    verified_at:row.photo_verified_at, already_verified:already };
}
async function conflict(p: Ports, id: string, path: string): Promise<ReturnType<typeof result>> {
  const current = await p.read(id);
  if (current && ready(current,path)) return result(current,true);
  return fail('revision_conflict',409,true);
}

export async function verifyPhoto(id: string, path: string, uid: string, p: Ports) {
  const row = await p.read(id);
  if (!row || row.user_id !== uid) return fail('not_found_or_not_owned',404);
  // This is the previous attestation's snapshot, not a promise of perpetual object existence.
  if (ready(row,path)) return result(row,true);
  const scoped = new RegExp(`^${uid}/${id}/([0-9a-f]{64})[.](jpg|png|webp)$`).exec(path);
  if (!scoped || row.upload_path !== path) return fail('reservation_mismatch',409);
  if (!Number.isSafeInteger(row.upload_size_bytes) || !row.upload_size_bytes || row.upload_size_bytes > MAX_BYTES)
    return fail('invalid_reservation',409);
  if (expired(row,p.now())) {
    // Do not interfere with another process's live checking lease.
    if (row.upload_state !== 'checking') await p.cas(row,{upload_state:'failed',upload_error_code:'expired'});
    return fail('expired',409);
  }
  const staleLease = row.upload_state === 'checking' &&
    p.now() - Date.parse(row.server_updated_at) > LEASE_MS;
  if (row.upload_state === 'checking' && !staleLease) return fail('verification_in_progress',409,true);
  if (row.upload_state === 'failed' && !retryableCode(row.upload_error_code || ''))
    return fail(row.upload_error_code || 'invalid_image');
  if (!['client_confirmed','failed'].includes(row.upload_state) && !staleLease)
    return fail('client_confirmation_required',409);

  // The returned revision is this attempt's lease token; never use an unconditioned UPDATE.
  const claimed = await p.cas(row,{upload_state:'checking',upload_error_code:null},true);
  if (!claimed) return conflict(p,id,path);
  try {
    const first = await p.object(path);
    if (first.bytes.length !== claimed.upload_size_bytes) return fail('size_mismatch');
    const mime = sniff(first.bytes);
    if (mime !== MIME[scoped[2]]) return fail('mime_mismatch');
    const hash = await digest(first.bytes);
    if (hash !== scoped[1]) return fail('hash_mismatch');
    containerCheck(first.bytes,mime);
    const image = await p.decode(first.bytes,mime); // actual pixels, not a header-only attestation
    if (image.mime !== mime || !Number.isSafeInteger(image.width) || !Number.isSafeInteger(image.height) ||
        image.width < 1 || image.height < 1) return fail('invalid_image');
    // Do not attest a different/deleted object after decoding. Standard clients cannot
    // overwrite/delete the referenced checking candidate under the existing policies.
    const final = await p.object(path);
    if (final.bytes.length !== first.bytes.length || await digest(final.bytes) !== hash ||
        final.etag !== first.etag || final.modified !== first.modified)
      return fail('object_changed',409,true);
    if (expired(claimed,p.now())) return fail('expired',409);
    const patch: Record<string,unknown> = {
      photo_state:'ready',photo_path:path,photo_sha256:hash,photo_size_bytes:final.bytes.length,
      photo_verified_at:new Date(p.now()).toISOString(),image_mime_type:mime,
      image_width:image.width,image_height:image.height,upload_state:'none',upload_path:null,
      upload_size_bytes:null,upload_expires_at:null,upload_error_code:null,
    };
    if (claimed.photo_path) {
      if (claimed.retired_photo_path) return fail('cleanup_required',409);
      patch.retired_photo_path = claimed.photo_path;
      // Margin covers app/DB clock drift and request latency above the SQL's >=24h guard.
      patch.retired_cleanup_after = new Date(p.now()+25*60*60*1000).toISOString();
    }
    const committed = await p.cas(claimed,patch,true);
    if (!committed) return conflict(p,id,path);
    return result(committed);
  } catch (error) {
    const e = error instanceof VerificationError ? error : new VerificationError('verification_unavailable',503,true);
    // A transient failure releases only OUR exact revision. A stale worker never writes
    // errors into a changed reservation or another worker's attempt.
    const patch = DB_ERRORS.has(e.code)
      ? {upload_state:'failed',upload_error_code:e.code}
      : {upload_state:'client_confirmed',upload_error_code:null};
    try { await p.cas(claimed,patch); } catch { /* outage: lease expires, then CAS takeover */ }
    throw e;
  }
}
