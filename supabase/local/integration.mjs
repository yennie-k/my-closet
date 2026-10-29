// Local-only integration harness. No cloud CLI commands, external URLs or resets.
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { resolve, join, relative } from 'node:path';
import { createHash, randomUUID, randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';

export const ROOT = resolve(fileURLToPath(new URL('../..', import.meta.url)));
export const LOCAL = 'C:\\Projects\\my_closet_supabase_local';
export const PROJECT = 'my_closet_supabase_local';
export const DB = `supabase_db_${PROJECT}`;
export const API = 'http://127.0.0.1:54321';
const CLI = join(LOCAL, 'node_modules/@supabase/cli-windows-x64/bin/supabase.exe');
const DOCKER = join(process.env.LOCALAPPDATA, 'Programs/DockerDesktop/resources/bin/docker.exe');
export const sha = value => createHash('sha256').update(value).digest('hex');
export const lit = value => `'${String(value).replaceAll("'", "''")}'`;

export function command(exe, args, input, binary = false) {
  return execFileSync(exe, args, { input, encoding: binary ? undefined : 'utf8',
    timeout: 60000, maxBuffer: 64 * 1024 * 1024, windowsHide: true,
    stdio: ['pipe', 'pipe', 'pipe'], cwd: LOCAL });
}
export const docker = (args, input, binary = false) => command(DOCKER, args, input, binary);
export function sql(text) {
  return docker(['exec', '-i', DB, 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
    '-v', 'VERBOSITY=verbose', '-U', 'postgres', '-d', 'postgres'], text).trim();
}
export function jsonSql(text) { return JSON.parse(sql(text).split('\n').at(-1)); }
export function sqlRole(role, uid, text, commit = false) {
  assert(['authenticated', 'anon', 'service_role'].includes(role));
  const claims = { role, ...(uid ? { sub: uid, is_anonymous: false } : {}) };
  return sql(`begin; set local role ${role}; set local request.jwt.claims=${lit(JSON.stringify(claims))};\n${text}\n${commit ? 'commit' : 'rollback'};`);
}
export function guard() {
  assert.equal(resolve(LOCAL), 'C:\\Projects\\my_closet_supabase_local');
  for (const name of ['DOCKER_HOST','DOCKER_CONTEXT','SUPABASE_WORKDIR','SUPABASE_ACCESS_TOKEN',
    'PGHOST','PGSERVICE','PGSERVICEFILE','DATABASE_URL']) assert(!process.env[name], `Unexpected environment: ${name}`);
  for (const root of [LOCAL, ROOT]) assert(!existsSync(join(root, 'supabase/.temp/project-ref')), 'Remote project link found; STOP');
  const config = readFileSync(join(LOCAL, 'supabase/config.toml'), 'utf8');
  assert.match(config, /^project_id\s*=\s*"my_closet_supabase_local"/m);
  assert.match(config, /\[db\][\s\S]*?\bport\s*=\s*54322/);
  assert.equal(docker(['context', 'show']).trim(), 'desktop-linux');
  const context = JSON.parse(docker(['context','inspect']));
  assert.equal(context[0].Endpoints.docker.Host, 'npipe:////./pipe/dockerDesktopLinuxEngine');
  const inspected = JSON.parse(docker(['inspect', DB]))[0];
  assert.equal(inspected.Name, `/${DB}`);
  assert(inspected.State.Running);
  assert(inspected.NetworkSettings.Ports['5432/tcp'].some(v => v.HostPort === '54322'));
  const status = JSON.parse(command(CLI, ['status','--output','json']));
  const api = new URL(status.API_URL); const db = new URL(status.DB_URL);
  assert.equal(api.origin, API); assert.equal(db.hostname, '127.0.0.1');
  assert.equal(db.port, '54322'); assert.equal(db.pathname, '/postgres');
  return { status, inspected };
}
export async function http(path, key, jwt, init = {}) {
  assert(path.startsWith('/') && !path.startsWith('//'));
  const url = new URL(path, API); assert.equal(url.origin, API);
  return fetch(url, { ...init, redirect: 'error', signal: AbortSignal.timeout(20000),
    headers: { ...(key ? { apikey: key } : {}), ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}), ...init.headers } });
}
export function protectedHashes() {
  const files = [];
  function walk(folder) { for (const entry of readdirSync(folder, { withFileTypes: true })) {
    const p = join(folder, entry.name); if(entry.isDirectory()) walk(p); else files.push(p);
  } }
  for (const name of ['lib','test','supabase/drafts','supabase/tests']) walk(join(ROOT,name));
  files.push(join(ROOT,'pubspec.yaml'),join(ROOT,'pubspec.lock'),join(ROOT,'supabase/local/README.md'),join(LOCAL,'supabase/config.toml'));
  return Object.fromEntries(files.map(p => [relative(ROOT,p),sha(readFileSync(p))]));
}
export function save(path, value) { writeFileSync(path, JSON.stringify(value, null, 2)+'\n', { flag:'wx' }); }

async function inspect() {
  const { status, inspected } = guard();
  const state = jsonSql(`select json_build_object('version',version(),'database',current_database(),
    'auth_users',(select count(*) from auth.users),'buckets',(select count(*) from storage.buckets),
    'objects',(select count(*) from storage.objects),'garments',to_regclass('public.garments'),
    'preferences',to_regclass('public.user_preferences'),'private_schema',to_regnamespace('my_closet_private'),
    'operation',to_regprocedure('storage.operation()'),'only_operation',to_regprocedure('storage.allow_only_operation(text)'),
    'any_operation',to_regprocedure('storage.allow_any_operation(text[])'),
    'storage_rls',(select relrowsecurity from pg_class where oid='storage.objects'::regclass),
    'storage_authenticated_select',has_table_privilege('authenticated','storage.objects','SELECT'),
    'storage_authenticated_insert',has_table_privilege('authenticated','storage.objects','INSERT'),
    'storage_authenticated_delete',has_table_privilege('authenticated','storage.objects','DELETE'));`);
  console.log(JSON.stringify({ target: API, db:'127.0.0.1:54322', remote_link:false,
    cli:command(CLI,['--version']).trim(), db_image:inspected.Config.Image,
    credential_fields_present:Object.keys(status).filter(k=>/KEY/.test(k)),state },null,2));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv[2], 'inspect', 'Only read-only inspect supported in this entry point');
  await inspect();
}
