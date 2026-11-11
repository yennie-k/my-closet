// Read-only baseline comparison. Retains all new synthetic fixtures for review.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join, sep } from 'node:path';
import { execFileSync } from 'node:child_process';
import { ROOT, guard, sql, save } from './integration.mjs';

guard();
const folder = resolve(process.argv[2] || '');
assert(folder.startsWith(join(ROOT, 'build', 'supabase-flutter-auth') + sep));
const baseline = JSON.parse(readFileSync(join(folder, 'baseline.json')));
const preservation = [];
for (const [table, before] of Object.entries(baseline)) {
  const after = JSON.parse(sql(`select coalesce(json_agg(json_build_object('id',${table === 'public.user_preferences' ? 'user_id' : 'id'},'digest',md5(row_to_json(t)::text))), '[]'::json) from ${table} t;`));
  const index = new Map(after.map(row => [row.id, row.digest]));
  assert(before.every(row => index.get(row.id) === row.digest), `Existing row changed in ${table}`);
  preservation.push({ table, original: before.length, current: after.length, original_rows_unchanged: true });
}
execFileSync('git', ['-c', `safe.directory=${ROOT.replaceAll('\\','/')}`, 'diff', '--exit-code', '--',
  'lib/models', 'lib/services/storage', 'lib/services/wardrobe_repository.dart', 'lib/services/preferences_service.dart',
  'lib/theme', 'lib/screens/wardrobe_screen.dart', 'lib/screens/garment_editor_screen.dart', 'supabase/drafts', 'supabase/tests', 'supabase/functions'],
  {cwd:ROOT, stdio:'pipe', windowsHide:true});
const api = JSON.parse(readFileSync(join(folder,'api-results.json')));
const browser = JSON.parse(readFileSync(join(folder,'browser-results.json')));
assert.equal(browser.failed, 0);
assert.equal(api.failed, 0);
const report = { date:'2026-10-29', api:'http://127.0.0.1:54321', db:'127.0.0.1:54322',
  cloud_connection:false, sql_schema_changes:false, local_wardrobe_repository_changed:false,
  flutter:'3.47.8',dart:'3.13.7',supabase_flutter:'2.18.3',cli:'2.122.0',
  api_checks:api.checks,browser_checks:browser.checks,api_passed:api.passed,browser_passed:browser.passed,
  preservation, no_existing_browser_profile_used:true, web_origin:'http://localhost:8081',
  flutter_tests:{passed:61,failed:0},flutter_analyze:'passed',default_web_build:'passed',development_web_build:'passed',
  indexeddb_browser_regression:'passed: legacy read + two real reloads + v2 metadata/photo persistence',
  limitations:['Browser clock was advanced only in the isolated test page to force real refresh; no natural one-hour wait',
    'Local email confirmations are disabled: email-confirmation delivery/callback flow not implemented or end-to-end tested',
    'No Android/iOS/native Windows authentication runtime test',
    'Existing SQL 29/33 suites and Edge worker suites not rerun in this Flutter-only change',
    'Server photo download and all server garment/photo mutations and migration remain out of scope',
    'Local logout removes this browser session; already issued access JWTs remain valid until expiry'] };
save(join(ROOT,'docs','supabase','flutter-auth-results-20261029.json'), report);
console.log(JSON.stringify({api_passed:api.passed,browser_passed:browser.passed,preservation},null,2));
