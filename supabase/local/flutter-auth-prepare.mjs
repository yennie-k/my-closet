// Local fixtures only. No migrations, cloud connections, resets or existing-row writes.
import assert from 'node:assert/strict';
import { mkdirSync, writeFileSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID, randomBytes } from 'node:crypto';
import { ROOT, API, guard, http, sql, save } from './integration.mjs';

const { status } = guard();
assert.match(status.PUBLISHABLE_KEY, /^sb_publishable_/);
const run = `auth-${Date.now()}`;
const folder = join(ROOT, 'build', 'supabase-flutter-auth', run);
mkdirSync(folder, { recursive: true });
const baseline = {};
for (const table of ['public.garments', 'public.user_preferences', 'storage.objects', 'storage.buckets', 'auth.users']) {
  const rows = JSON.parse(sql(`select coalesce(json_agg(json_build_object('id',${table === 'public.user_preferences' ? 'user_id' : 'id'},'digest',md5(row_to_json(t)::text))), '[]'::json) from ${table} t;`));
  baseline[table] = rows;
}
const checks = [];
const record = (name, condition) => { assert(condition, name); checks.push({ name, passed: true }); };
const users = {};
for (const name of ['a', 'b']) {
  const email = `${run}-${name}@example.test`;
  const password = randomBytes(24).toString('base64url');
  const response = await http('/auth/v1/signup', status.PUBLISHABLE_KEY, null, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }),
  });
  assert.equal(response.status, 200, 'Local signup must succeed (email confirmations must be off for these API fixtures)');
  const body = await response.json();
  assert(body.access_token && body.refresh_token && body.user.id);
  users[name] = { email, password, id: body.user.id, accessToken: body.access_token, refreshToken: body.refresh_token };
  record(`signup_${name}`, true);
  record(`es256_${name}`, JSON.parse(Buffer.from(body.access_token.split('.')[0], 'base64url')).alg === 'ES256');
}
const weak = await http('/auth/v1/signup', status.PUBLISHABLE_KEY, null, {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: `${run}-weak@example.test`, password: '123' }),
});
record('weak_password_rejected', weak.status === 422 || weak.status === 400);
const bad = await http('/auth/v1/token?grant_type=password', status.PUBLISHABLE_KEY, null, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: users.a.email, password: 'incorrect-password' }),
});
record('wrong_password_rejected', bad.status === 400);
const good = await http('/auth/v1/token?grant_type=password', status.PUBLISHABLE_KEY, null, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: users.a.email, password: users.a.password }),
});
record('password_login', good.status === 200);
const session = await good.json();
for (const name of ['a', 'b']) {
  const response = await http('/rest/v1/garments', status.PUBLISHABLE_KEY, users[name].accessToken, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Prefer: 'return=representation' },
    body: JSON.stringify({ local_id: randomUUID(), name: `AUTH TEST ${name.toUpperCase()} ${run}`, category: 'tops', subtype: '니트', image_width: 1, image_height: 1 }),
  });
  assert.equal(response.status, 201);
  const [garment] = await response.json();
  users[name].garment = { id: garment.id, name: garment.name };
}
for (const name of ['a', 'b']) {
  const own = await http(`/rest/v1/garments?select=id,name&user_id=eq.${users[name].id}`, status.PUBLISHABLE_KEY, users[name].accessToken);
  record(`own_read_${name}`, own.status === 200 && (await own.json()).length === 1);
  const other = users[name === 'a' ? 'b' : 'a'];
  // Intentionally omit user_id filter: server RLS must enforce ownership.
  const denied = await http(`/rest/v1/garments?select=id,name&id=eq.${other.garment.id}`, status.PUBLISHABLE_KEY, users[name].accessToken);
  record(`cross_user_read_${name}_empty`, denied.status === 200 && (await denied.json()).length === 0);
}
const anonymous = await http('/rest/v1/garments?select=id', status.PUBLISHABLE_KEY, null);
const deniedBody = await anonymous.json();
record('anonymous_read_denied', anonymous.status === 401 && deniedBody.code === '42501');
const userResponse = await http('/auth/v1/user', status.PUBLISHABLE_KEY, session.access_token);
record('auth_get_user_validates_jwt', userResponse.status === 200 && (await userResponse.json()).id === users.a.id);
const logout = await http('/auth/v1/logout?scope=local', status.PUBLISHABLE_KEY, session.access_token, { method: 'POST' });
record('logout', logout.status === 204);
const refreshAfterLogout = await http('/auth/v1/token?grant_type=refresh_token', status.PUBLISHABLE_KEY, null, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ refresh_token: session.refresh_token }),
});
record('logged_out_refresh_token_rejected', refreshAfterLogout.status === 400);

save(join(folder, 'private-fixtures.json'), { run, users });
save(join(folder, 'baseline.json'), baseline);
save(join(folder, 'api-results.json'), { api: API, run, checks, passed: checks.length, failed: 0, baseline_counts: Object.fromEntries(Object.entries(baseline).map(([k,v]) => [k,v.length])) });
const config = join(ROOT, 'config', 'supabase.local.json');
const value = JSON.stringify({ MY_CLOSET_SUPABASE_ENABLED: true, MY_CLOSET_SUPABASE_URL: API, MY_CLOSET_SUPABASE_PUBLISHABLE_KEY: status.PUBLISHABLE_KEY }, null, 2) + '\n';
if (!existsSync(config)) writeFileSync(config, value, { flag: 'wx' });
else assert.deepEqual(JSON.parse(readFileSync(config, 'utf8')), JSON.parse(value), 'Existing config differs; preserved without overwriting');
// The only printed values are non-secret test counts and ignored output paths.
console.log(JSON.stringify({ folder, passed: checks.length, failed: 0, baseline_counts: Object.fromEntries(Object.entries(baseline).map(([k,v]) => [k,v.length])) }, null, 2));
