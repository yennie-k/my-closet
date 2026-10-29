// PREPARED, NOT EXECUTED. Writes only disposable staging fixtures when explicitly
// enabled. No service/secret key is accepted. Requires a real server-reserved
// upload slot plus separately prepared unreferenced delete fixtures.
import { readFile } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';

const env = process.env;
assert.equal(env.MY_CLOSET_ALLOW_REMOTE_TESTS, 'yes', 'Explicit staging opt-in required');
assert.equal(env.MY_CLOSET_TARGET_KIND, 'disposable-staging', 'Disposable staging only');
const base = new URL(env.SUPABASE_URL);
assert.equal(base.host, env.MY_CLOSET_EXPECTED_STAGING_HOST, 'Unexpected target host');
assert(base.protocol === 'https:' || ['127.0.0.1', 'localhost'].includes(base.hostname));
const key = env.SUPABASE_PUBLISHABLE_KEY;
assert(key?.startsWith('sb_publishable_'), 'Only a publishable key is accepted');
assert(env.TEST_USER_A_JWT && env.TEST_USER_B_JWT && process.argv[2]);
const fixture = JSON.parse(await readFile(process.argv[2], 'utf8'));
assert.equal(fixture.approvedTestRun, env.MY_CLOSET_TEST_RUN_ID, 'Wrong fixture/test-run marker');
assert(fixture.approvedTestRun, 'A nonempty test-run marker is required');
const bucket = 'garment-photos';
const a = env.TEST_USER_A_JWT, b = env.TEST_USER_B_JWT;

async function request(path, jwt, init = {}) {
  return fetch(new URL(path, base), { ...init, headers: {
    apikey: key, ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}), ...init.headers,
  }, signal: AbortSignal.timeout(20000) });
}
async function user(jwt) {
  const res = await request('/auth/v1/user', jwt);
  assert.equal(res.status, 200, 'Real user JWT validation failed');
  const value = await res.json(); assert.equal(value.is_anonymous, false);
  return value.id;
}
function objectPath(path) { return `/storage/v1/object/${bucket}/${path.split('/').map(encodeURIComponent).join('/')}`; }
function authenticatedPath(path) { return `/storage/v1/object/authenticated/${bucket}/${path.split('/').map(encodeURIComponent).join('/')}`; }
function denied(res, description) { assert(res.status >= 400 && res.status < 500, `${description}: expected 4xx, got ${res.status}`); }
async function bytes(path, jwt) {
  const res = await request(authenticatedPath(path), jwt);
  assert.equal(res.status, 200, 'Authenticated download failed');
  return Buffer.from(await res.arrayBuffer());
}
function sha(value) { return createHash('sha256').update(value).digest('hex'); }

const uidA = await user(a), uidB = await user(b);
assert.notEqual(uidA, uidB);
const owned = [fixture.uploadPath, fixture.activePath, fixture.deleteSinglePath, ...fixture.deleteManyPaths];
assert.equal(fixture.deleteManyPaths.length, 2);
assert.equal(new Set(owned).size, owned.length);
for (const path of owned) assert(path.startsWith(`${uidA}/`), 'Only A-owned fixtures allowed');

const photo = await readFile(fixture.uploadFile);
assert(photo.length > 0 && photo.length <= 2097152);
assert(fixture.uploadPath.endsWith(`/${sha(photo)}.${fixture.extension}`), 'Fixture bytes/hash path differ');
const mime = { jpg: 'image/jpeg', png: 'image/png', webp: 'image/webp' }[fixture.extension];
assert(mime);
const upload = (path, jwt, upsert = false) => request(objectPath(path), jwt, {
  method: 'POST', headers: { 'Content-Type': mime, 'x-upsert': String(upsert) }, body: photo,
});

let res = await upload(fixture.uploadPath, a);
assert([200, 201].includes(res.status), 'Reserved owner upload failed');
console.log('PASS: reserved owner upload');
assert.equal(sha(await bytes(fixture.uploadPath, a)), sha(photo));
console.log('PASS: authenticated owner download with byte hash');
denied(await request(authenticatedPath(fixture.uploadPath), b), 'Cross-user download');
denied(await request(authenticatedPath(fixture.uploadPath), null), 'Logged-out download');
denied(await request(`/storage/v1/object/public/${bucket}/${fixture.uploadPath}`, null), 'Public download');
denied(await upload(fixture.uploadPath, b), 'Cross-user upload');
denied(await upload(fixture.uploadPath, a, true), 'Overwrite');
denied(await request(`/storage/v1/object/sign/${bucket}/${fixture.uploadPath}`,a,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({expiresIn:60})}),'Signed URL creation');
res = await request(objectPath(fixture.uploadPath),a,{method:'DELETE'});
assert(res.status < 500); assert.equal(sha(await bytes(fixture.uploadPath,a)),sha(photo),'Reserved candidate was deleted');

const noGarmentId = randomUUID();
const query = new URLSearchParams({select:'id',id:`eq.${noGarmentId}`});
res = await request(`/rest/v1/garments?${query}`, a);
assert.equal(res.status, 200); assert.equal((await res.json()).length, 0);
denied(await upload(`${uidA}/${noGarmentId}/${sha(photo)}.${fixture.extension}`, a), 'No garment reservation');
const sameGarmentDifferentPath = `${fixture.uploadPath.slice(0, fixture.uploadPath.lastIndexOf('/') + 1)}${'f'.repeat(64)}.${fixture.extension}`;
assert.notEqual(sameGarmentDifferentPath, fixture.uploadPath);
denied(await upload(sameGarmentDifferentPath, a), 'Unreserved file in existing garment folder');

res = await request(`/storage/v1/object/list/${bucket}`, a, {
  method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({prefix:fixture.uploadPath.slice(0,fixture.uploadPath.lastIndexOf('/')),limit:100}),
});
assert.equal(res.status, 200); assert((await res.json()).some(v => v.name === fixture.uploadPath.split('/').at(-1)));
res = await request(`/storage/v1/object/list/${bucket}`, b, {
  method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefix:uidA,limit:100}),
});
if (res.ok) assert.equal((await res.json()).length, 0, 'Foreign folder/list leaked'); else denied(res, 'Foreign list');
console.log('PASS: own list and foreign-list isolation');

const activeBefore = sha(await bytes(fixture.activePath, a));
res = await request(objectPath(fixture.activePath), a, {method:'DELETE'});
// RLS filtering may report not-found or a zero-deletion success; verify bytes.
assert(res.status < 500); assert.equal(sha(await bytes(fixture.activePath,a)),activeBefore);

const singleBefore = sha(await bytes(fixture.deleteSinglePath,a));
res = await request(objectPath(fixture.deleteSinglePath),b,{method:'DELETE'});
assert(res.status < 500); assert.equal(sha(await bytes(fixture.deleteSinglePath,a)),singleBefore);
res = await request(objectPath(fixture.deleteSinglePath),a,{method:'DELETE'});
assert(res.ok,'Owner single orphan delete failed');
denied(await request(authenticatedPath(fixture.deleteSinglePath),a),'Deleted single object');
console.log('PASS: single delete, foreign denial, active-reference protection');

for (const path of fixture.deleteManyPaths) await bytes(path,a);
res = await request(`/storage/v1/object/${bucket}`,b,{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefixes:fixture.deleteManyPaths})});
assert(res.status < 500);
for (const path of fixture.deleteManyPaths) await bytes(path,a); // Foreign batch must change nothing.
res = await request(`/storage/v1/object/${bucket}`,a,{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefixes:fixture.deleteManyPaths})});
assert(res.ok,'Owner multi orphan delete failed');
for (const path of fixture.deleteManyPaths) denied(await request(authenticatedPath(path),a),'Deleted multi object');
console.log('PASS: multi delete');
console.log('STAGING FIXTURES CONSUMED. Reserved upload remains for verifier/GC tests; no local data was touched.');
