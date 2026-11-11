// Actual production Flutter UI on localhost:8081, in a new disposable Chrome
// profile. Never opens 8080 or an existing profile. No application test hooks.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(fileURLToPath(new URL('..', import.meta.url)));
const folder = path.resolve(process.argv[2] || '');
assert(folder.startsWith(path.join(root, 'build', 'supabase-flutter-auth') + path.sep));
const fixtures = JSON.parse(fs.readFileSync(path.join(folder, 'private-fixtures.json')));
const build = path.join(root, 'build', 'web_auth');
const profile = fs.mkdtempSync(path.join(folder, 'chrome-'));
const url = 'http://localhost:8081/';
const blank = `${url}__test_blank`;
const checks = [];
const delay = ms => new Promise(r => setTimeout(r, ms));
const sha = value => createHash('sha256').update(value).digest('hex');
const record = (name, condition = true) => { assert(condition, name); checks.push({name, passed: true}); console.log(`PASS ${name}`); };
let chrome, ws;
const server = http.createServer((req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  if (req.url === '/__test_blank') { res.setHeader('Content-Type', 'text/html'); res.end('<!doctype html><html><body>Isolated test origin</body></html>'); return; }
  const filename = path.resolve(build, `.${decodeURIComponent(new URL(req.url, url).pathname)}`);
  if (!filename.startsWith(build + path.sep) && filename !== build) { res.writeHead(403); res.end(); return; }
  const file = fs.existsSync(filename) && fs.statSync(filename).isFile() ? filename : path.join(build, 'index.html');
  const types = {'.js':'text/javascript', '.wasm':'application/wasm', '.json':'application/json', '.html':'text/html; charset=utf-8', '.png':'image/png', '.woff2':'font/woff2'};
  res.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream');
  fs.createReadStream(file).pipe(res);
});

try {
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(8081, '127.0.0.1', resolve); });
  chrome = spawn(process.env.CHROME_EXECUTABLE || path.join(process.env.PROGRAMFILES || '', 'Google/Chrome/Application/chrome.exe'), [
    '--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--remote-debugging-port=0',
    `--user-data-dir=${profile}`, '--window-size=1280,1000', blank,
  ], {windowsHide: true, stdio: ['ignore','ignore','pipe']});
  let stderr = '';
  chrome.stderr.on('data', bytes => stderr += bytes.toString());
  const deadline = Date.now() + 30000;
  while (!/DevTools listening on (ws:\/\/[^\s]+)/.test(stderr)) {
    assert(Date.now() < deadline, 'Chrome startup timeout');
    await delay(100);
  }
  const debugPort = new URL(stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/)[1]).port;
  let target;
  while (!target) {
    const tabs = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json();
    target = tabs.find(tab => tab.url === blank);
    assert(Date.now() < deadline, 'Chrome tab timeout');
    if (!target) await delay(100);
  }
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {ws.addEventListener('open', resolve, {once: true}); ws.addEventListener('error', reject, {once: true});});
  let nextId = 0;
  const pending = new Map();
  const refreshResponses = [];
  let restoreClockOnRefresh = false;
  let loaded;
  ws.addEventListener('message', event => {
    const result = JSON.parse(event.data);
    if (result.method === 'Page.loadEventFired' && loaded) { loaded(); loaded = null; }
    if (result.method === 'Network.responseReceived' &&
        result.params.response.url.startsWith('http://127.0.0.1:54321/auth/v1/token?grant_type=refresh_token')) {
      refreshResponses.push(result.params.response.status);
      if (restoreClockOnRefresh) {
        restoreClockOnRefresh = false;
        void send('Runtime.evaluate', {expression:'window.__restoreAuthTestClock?.()'});
      }
    }
    if (result.id && pending.has(result.id)) {
      const {resolve, reject} = pending.get(result.id); pending.delete(result.id);
      result.error ? reject(new Error('CDP command failed')) : resolve(result.result);
    }
  });
  function send(method, params = {}) {
    return new Promise((resolve, reject) => {const id = ++nextId; pending.set(id, {resolve, reject}); ws.send(JSON.stringify({id, method, params}));});
  }
  await send('Network.enable');
  await send('Page.enable');
  async function reload() {
    let timeout;
    const load = new Promise((resolve, reject) => {
      timeout = setTimeout(() => reject(new Error('Actual page reload timed out')),30000);
      loaded = resolve;
    });
    try {
      await send('Page.reload', {ignoreCache:true});
      await load;
    } finally { clearTimeout(timeout); loaded = null; }
  }
  async function evaluate(expression) {
    const result = await send('Runtime.evaluate', {expression, returnByValue: true, awaitPromise: true});
    if (result.exceptionDetails) {
      // Only fixed browser exception text, with all known credentials redacted.
      let description = result.exceptionDetails.exception?.description?.split('\n')[0] || result.exceptionDetails.text;
      for (const user of Object.values(fixtures.users)) {
        for (const field of ['password','accessToken','refreshToken']) description = description.replaceAll(user[field], '[REDACTED]');
      }
      throw new Error(`Browser evaluation failed: ${description}`);
    }
    return result.result?.value;
  }
  const deepElements = `function all(root=document) { return [...root.querySelectorAll('*')].flatMap(e=>[e,...(e.shadowRoot ? all(e.shadowRoot):[])]); }`;
  async function semantics() {
    await evaluate(`(()=>{${deepElements} const p=all().find(e=>e.tagName==='FLT-SEMANTICS-PLACEHOLDER'); if(p)p.click(); return true;})()`);
  }
  async function text() {
    return evaluate(`(()=>{${deepElements} return all().filter(e=>e.tagName==='FLT-SEMANTICS').map(e=>[e.getAttribute('aria-label')||'',e.textContent||''].join(' ')).join(' ');})()`);
  }
  async function waitText(expected, absent = false) {
    const limit = Date.now() + 30000;
    while (Date.now() < limit) {
      await semantics();
      if ((await text()).includes(expected) !== absent) return;
      await delay(120);
    }
    // No form values, browser storage or network bodies in diagnostics.
    const labels = await evaluate(`(()=>{${deepElements} return all().filter(e=>e.tagName==='FLT-SEMANTICS').map(e=>({role:e.getAttribute('role'),label:e.getAttribute('aria-label'),text:e.children.length?null:e.textContent})).slice(0,120);})()`);
    fs.writeFileSync(path.join(folder, 'ui-timeout-labels.json'), JSON.stringify(labels, null, 2));
    throw new Error(`UI timeout: ${expected} (${absent ? 'absent':'present'})`);
  }
  async function click(label) {
    const point = await evaluate(`(()=>{${deepElements} const es=all().filter(e=>e.tagName==='FLT-SEMANTICS'); const label=${JSON.stringify(label)};const matches=e=>e.getAttribute('aria-label')===label||e.textContent===label;const e=es.find(e=>['button','tab'].includes(e.getAttribute('role'))&&matches(e))||es.find(matches)||es.find(e=>['button','tab'].includes(e.getAttribute('role'))&&(e.getAttribute('aria-label')?.startsWith(label)||e.textContent.startsWith(label+String.fromCharCode(10)))); if(!e)return null; e.scrollIntoView({block:'center'}); const r=e.getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2};})()`);
    if (!point) {
      const labels = await evaluate(`(()=>{${deepElements} return all().filter(e=>e.tagName==='FLT-SEMANTICS').map(e=>({role:e.getAttribute('role'),label:e.getAttribute('aria-label'),text:e.children.length?null:e.textContent}));})()`);
      fs.writeFileSync(path.join(folder, 'ui-timeout-labels.json'), JSON.stringify(labels,null,2));
      throw new Error(`Button not found: ${label}`);
    }
    await send('Input.dispatchMouseEvent', {type:'mousePressed', button:'left', clickCount:1, ...point});
    await send('Input.dispatchMouseEvent', {type:'mouseReleased', button:'left', clickCount:1, ...point});
    await delay(180);
  }
  async function fill(label, value) {
    const point = await evaluate(`(()=>{${deepElements} const e=all().find(e=>(e.tagName==='INPUT'||e.tagName==='TEXTAREA')&&e.getAttribute('aria-label')===${JSON.stringify(label)}); if(!e)return null; e.scrollIntoView({block:'center'});e.focus();const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()`);
    assert(point, `Input not found: ${label}`);
    await send('Input.dispatchMouseEvent', {type:'mousePressed', button:'left', clickCount:1, ...point});
    await send('Input.dispatchMouseEvent', {type:'mouseReleased', button:'left', clickCount:1, ...point});
    await send('Input.dispatchKeyEvent', {type:'keyDown', key:'a', code:'KeyA', modifiers:2, windowsVirtualKeyCode:65});
    await send('Input.dispatchKeyEvent', {type:'keyUp', key:'a', code:'KeyA', modifiers:2, windowsVirtualKeyCode:65});
    await send('Input.insertText', {text:value});
  }
  async function dbSnapshot() {
    return evaluate(`(async()=>{ const db=await new Promise((r,j)=>{const q=indexedDB.open('my_closet_wardrobe_v1');q.onsuccess=()=>r(q.result);q.onerror=j;}); const t=db.transaction(['garments','photos'],'readonly');const get=s=>new Promise((r,j)=>{const q=t.objectStore(s).getAll();q.onsuccess=()=>r(q.result);q.onerror=j;});const [rows,photos]=await Promise.all([get('garments'),get('photos')]);db.close();return {rows,photos:photos.map(p=>Array.from(p)),preferences:localStorage.getItem('my_closet.preferences.v1')};})()`);
  }

  const loadedBy = Date.now() + 15000;
  while (!(await evaluate(`location.href===${JSON.stringify(blank)} && document.readyState==='complete' && document.body?.textContent==='Isolated test origin'`))) {
    if (Date.now() > loadedBy) {
      const state = await evaluate(`({url:location.href,text:document.body?.textContent?.slice(0,300)})`);
      throw new Error(`Test origin did not load: ${JSON.stringify(state)}`);
    }
    await delay(100);
  }

  // Synthetic local fixture in this new profile/origin, not a user's wardrobe.
  await evaluate(`(async()=>{
    localStorage.setItem('my_closet.preferences.v1',JSON.stringify(JSON.stringify({version:1,design:'minimal',styles:['캐주얼'],temperature:'normal',onboardingComplete:true})));
    const db=await new Promise((r,j)=>{const q=indexedDB.open('my_closet_wardrobe_v1',1);q.onupgradeneeded=()=>{q.result.createObjectStore('garments');q.result.createObjectStore('photos');};q.onsuccess=()=>r(q.result);q.onerror=j;});
    const t=db.transaction(['garments','photos'],'readwrite');
    t.objectStore('garments').put({version:2,id:'local-auth-preservation',name:'로컬 보존 테스트 셔츠',category:'tops',createdAt:'2026-10-29T00:00:00Z',updatedAt:'2026-10-29T00:00:00Z',imageMimeType:'image/png',imageWidth:1,imageHeight:1,subtype:'셔츠',materials:['면','나만의 혼방'],additionalColors:['민트'],thicknessLevel:3},'local-auth-preservation');
    t.objectStore('photos').put(Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1kAAAAASUVORK5CYII='),c=>c.charCodeAt(0)),'local-auth-preservation');
    await new Promise((r,j)=>{t.oncomplete=r;t.onerror=j;});db.close();return true;
  })()`);
  const before = sha(JSON.stringify(await dbSnapshot()));
  await send('Page.navigate', {url});
  await waitText('마이페이지');
  await click('마이페이지');
  await waitText('로그인하지 않은 상태예요.');
  record('profile_signed_out');
  await click('서버 의류 조회 테스트');
  await waitText('로그인이 필요해요.');
  record('server_route_requires_login');
  await click('로그인 / 회원가입');
  await waitText('이메일로 로그인');
  await fill('이메일', fixtures.users.a.email);
  await fill('비밀번호', 'wrong-password');
  await click('이메일로 로그인');
  await waitText('이메일 또는 비밀번호가 올바르지 않아요.');
  record('ui_wrong_password');
  await fill('비밀번호', fixtures.users.a.password);
  await click('이메일로 로그인');
  await waitText(fixtures.users.a.garment.name);
  record('ui_login_and_own_server_read');
  record('foreign_garment_not_rendered', !(await text()).includes(fixtures.users.b.garment.name));
  await reload();
  await waitText(fixtures.users.a.garment.name);
  record('actual_reload_restores_session_and_server_read');
  // The SDK derives expiration from the signed JWT, ignoring cached expires_at.
  // Advance only this isolated page's clock to exercise the expiry branch;
  // restore it on the real refresh response. JWT/server/system time untouched.
  const clockScript = await send('Page.addScriptToEvaluateOnNewDocument', {source:`(()=>{const NativeDate=Date;let offset=7200000;window.__restoreAuthTestClock=()=>offset=0;window.Date=class extends NativeDate {constructor(...args){if(args.length)super(...args);else super(NativeDate.now()+offset);}static now(){return NativeDate.now()+offset;}};})()`});
  const refreshBefore = refreshResponses.length;
  restoreClockOnRefresh = true;
  await reload();
  await waitText(fixtures.users.a.garment.name);
  await send('Page.removeScriptToEvaluateOnNewDocument', {identifier:clockScript.identifier});
  record('browser_clock_expired_session_uses_real_refresh_api', refreshResponses.slice(refreshBefore).includes(200));
  await click('로그아웃');
  await waitText('로그인이 필요해요.');
  record('logout_removes_server_rows', !(await text()).includes(fixtures.users.a.garment.name));
  record('logout_removes_persisted_session', await evaluate(`localStorage.getItem('my_closet.local_supabase.auth.v1')===null`));
  await reload();
  await waitText('로그인이 필요해요.');
  record('reload_after_logout_stays_signed_out');
  // Sign up through actual Flutter UI with a third new synthetic account.
  await click('로그인 / 회원가입');
  await waitText('처음인가요? 회원가입');
  await click('처음인가요? 회원가입');
  await waitText('계정 만들기');
  await fill('이메일', `${fixtures.run}-ui-${randomBytes(4).toString('hex')}@example.test`);
  const signupPassword = randomBytes(24).toString('base64url');
  await fill('비밀번호', signupPassword);
  await fill('비밀번호 확인', 'mismatch');
  await click('계정 만들기');
  await waitText('비밀번호가 서로 달라요.');
  record('ui_signup_validation_failure');
  await fill('비밀번호 확인', signupPassword);
  await click('계정 만들기');
  await waitText('이 계정에 등록된 서버 테스트 의류가 없어요.');
  record('ui_signup_success_no_local_auto_upload');
  await click('로그아웃');
  await waitText('로그인이 필요해요.');
  // Mobile viewport, same production route and authentication screen.
  await send('Emulation.setDeviceMetricsOverride', {width:360,height:800,deviceScaleFactor:1,mobile:true});
  await click('로그인 / 회원가입');
  await waitText('이메일로 로그인');
  record('mobile_auth_layout_no_document_overflow', await evaluate('document.documentElement.scrollWidth<=innerWidth'));
  record('synthetic_indexeddb_metadata_photo_and_preferences_unchanged', before === sha(JSON.stringify(await dbSnapshot())));
  fs.writeFileSync(path.join(folder, 'browser-results.json'), JSON.stringify({origin:url,isolated_profile:true,passed:checks.length,failed:0,checks},null,2));
  console.log(`Browser checks: ${checks.length} passed, 0 failed`);
} catch (error) {
  fs.writeFileSync(path.join(folder, 'browser-results.json'), JSON.stringify({origin:url,passed:checks.length,failed:1,checks,error:error.message},null,2));
  console.error(error.message);
  process.exitCode = 1;
} finally {
  ws?.close();
  if (chrome && chrome.exitCode === null) chrome.kill();
  server.close();
}
