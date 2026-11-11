// Production Flutter CRUD, isolated origin/profile, synthetic metadata only.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash,randomBytes} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {startBrowser} from './browser_test_driver.mjs';

const root=fileURLToPath(new URL('..',import.meta.url));
const folder=path.resolve(process.argv[2]||'');
assert(folder.startsWith(path.join(root,'build','supabase-wardrobe-crud')+path.sep));
const fixture=JSON.parse(fs.readFileSync(path.join(folder,'private-fixtures.json')));
assert.equal(fixture.api,'http://127.0.0.1:54321');
const checks=[];let browser;
const record=(name,condition=true)=>{assert(condition,name);checks.push({name,passed:true});console.log(`PASS ${name}`);};
const digest=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
try {
  const build=path.resolve(root,process.env.MY_CLOSET_BROWSER_BUILD||'build/web_crud');
  assert(build.startsWith(path.join(root,'build')+path.sep));
  browser=await startBrowser({build,folder,redact:Object.values(fixture.users).map(u=>u.password)});
  const {evaluate,send,navigate,reload,text,waitText,click,fill,delay}=browser;
  await evaluate(`(async()=>{
    localStorage.setItem('my_closet.preferences.v1',JSON.stringify(JSON.stringify({version:1,design:'lovely',styles:['캐주얼'],temperature:'normal',onboardingComplete:true})));
    const db=await new Promise((r,j)=>{const q=indexedDB.open('my_closet_wardrobe_v1',1);q.onupgradeneeded=()=>{q.result.createObjectStore('garments');q.result.createObjectStore('photos');};q.onsuccess=()=>r(q.result);q.onerror=j;});
    const t=db.transaction(['garments','photos'],'readwrite');
    t.objectStore('garments').put({version:2,id:'crud-local-preserved',name:'로컬 보존용 셔츠',category:'tops',createdAt:'2026-11-02T00:00:00Z',updatedAt:'2026-11-02T00:00:00Z',imageMimeType:'image/png',imageWidth:1,imageHeight:1,subtype:'셔츠',materials:['면'],additionalColors:['민트'],thicknessLevel:3},'crud-local-preserved');
    t.objectStore('photos').put(new Uint8Array([1,2,3,4,5]),'crud-local-preserved');await new Promise((r,j)=>{t.oncomplete=r;t.onerror=j;});db.close();return true;
  })()`);
  const localSnapshot=()=>evaluate(`(async()=>{const db=await new Promise((r,j)=>{const q=indexedDB.open('my_closet_wardrobe_v1');q.onsuccess=()=>r(q.result);q.onerror=j;});const t=db.transaction(['garments','photos'],'readonly');const get=s=>new Promise((r,j)=>{const q=t.objectStore(s).getAll();q.onsuccess=()=>r(q.result);q.onerror=j;});const [rows,photos]=await Promise.all([get('garments'),get('photos')]);db.close();return {rows,photos:photos.map(p=>Array.from(p)),preferences:localStorage.getItem('my_closet.preferences.v1')};})()`);
  const before=digest(await localSnapshot());
  const route='http://localhost:8081/#/dev/server-wardrobe-crud';
  await navigate(route);await waitText('로그인 후 서버 의류 정보를 관리할 수 있어요.');record('unauthenticated_server_ui_gated');
  async function login(who) {await click('로그인 / 회원가입');await waitText('이메일로 로그인');await fill('이메일',fixture.users[who].email);await fill('비밀번호',fixture.users[who].password);await click('이메일로 로그인');await waitText('서버 새로고침');await delay(400);}
  await login('a');record('A_login_server_list');
  const name=`브라우저 등록 ${randomBytes(4).toString('hex')}`;
  await click('옷 추가');await waitText('서버 개발 옷장 · 사진은 선택 사항');
  record('photo_is_optional_in_server_form',(await text()).includes('사진은 선택 사항이에요.'));
  await fill('의류 이름 *',name);await click('카테고리 *');await click('상의');
  await fill('세부 종류 직접 입력','브라우저 사용자 종류');
  fs.writeFileSync(path.join(folder,'crud-before-save.png'),Buffer.from((await send('Page.captureScreenshot',{format:'png'})).data,'base64'));
  await click('옷 저장하기');await delay(500);
  fs.writeFileSync(path.join(folder,'crud-after-save.png'),Buffer.from((await send('Page.captureScreenshot',{format:'png'})).data,'base64'));
  await waitText(name);record('A_create_without_photo');
  await click('상의');await waitText('브라우저 사용자 종류');await click('브라우저 사용자 종류');
  await fill('의류 이름으로 검색',name);await waitText(name);record('category_subtype_search_combined');
  await click(name);await waitText('정보 수정');record('detail_read');
  await click('정보 수정');await waitText('옷 정보 수정');await fill('의류 이름 *',name+' 수정');await click('옷 저장하기');await waitText(name+' 수정');record('A_update');
  await navigate(route);await waitText(name+' 수정');await reload();await waitText(name+' 수정');record('actual_reload_reads_persisted_server_row');
  // Use this browser's user JWT only to edit its newly created synthetic row.
  const token=await evaluate(`JSON.parse(localStorage.getItem('my_closet.local_supabase.auth.v1')).access_token`);
  async function api(method,query,body) {
    const response=await fetch(`${fixture.api}/rest/v1/garments?${new URLSearchParams(query)}`,{method,redirect:'error',headers:{apikey:fixture.publishableKey,Authorization:`Bearer ${token}`,'Content-Type':'application/json',Prefer:'return=representation'},...(body?{body:JSON.stringify(body)}:{})});
    assert(response.ok,`Synthetic REST ${method} failed`);return response.status===204?null:response.json();
  }
  const [row]=await api('GET',{select:'id,user_id,revision',name:'eq.'+name+' 수정'});assert.equal(row.user_id,fixture.users.a.id);
  await click(name+' 수정');await click('정보 수정');await waitText('옷 정보 수정');await fill('의류 이름 *',name+' 내 초안');
  await api('PATCH',{id:'eq.'+row.id,user_id:'eq.'+row.user_id,revision:'eq.'+row.revision},{name:name+' 다른 탭',updated_at:new Date().toISOString()});
  await click('옷 저장하기');await waitText('자동으로 덮어쓰지 않았어요.');record('revision_conflict_notice_keeps_editor');
  await navigate(route);await waitText(name+' 다른 탭');record('conflict_did_not_overwrite_server');
  await send('Network.setBlockedURLs',{urls:['http://127.0.0.1:54321/rest/v1/garments*']});
  await click('서버 새로고침');await waitText('로컬 서버에 연결하지 못했어요.');record('network_error_visible');
  await send('Network.setBlockedURLs',{urls:[]});await click('다시 불러오기');await waitText(name+' 다른 탭');record('network_recovery_refresh');
  // Sign out with an editor open: its text fields/draft must disappear.
  await click(name+' 다른 탭');await click('정보 수정');await waitText('옷 정보 수정');await click('서버 로그아웃');await waitText('로그인 후 서버 의류 정보를 관리할 수 있어요.');
  record('logout_removes_open_editor_and_previous_data',!(await text()).includes(name));
  await login('b');record('account_B_has_no_A_row',!(await text()).includes(name));
  await click('서버 로그아웃');await waitText('로그인 후 서버 의류 정보를 관리할 수 있어요.');await login('a');await waitText(name+' 다른 탭');
  await send('Emulation.setDeviceMetricsOverride',{width:360,height:800,deviceScaleFactor:1,mobile:true});await delay(300);
  record('mobile_server_layout_no_document_overflow',await evaluate('document.documentElement.scrollWidth<=innerWidth'));
  await click(name+' 다른 탭');await waitText('의류 삭제');await click('의류 삭제');await waitText('이 옷을 삭제할까요?');await click('취소');await waitText('정보 수정');record('delete_cancel_preserves_row');
  await click('의류 삭제');await waitText('이 옷을 삭제할까요?');await click('삭제하기');await waitText(name+' 다른 탭',true);record('A_delete_confirmed');
  record('deleted_row_absent_in_actual_server',(await api('GET',{select:'id',id:'eq.'+row.id})).length===0);
  record('synthetic_local_metadata_photo_and_theme_unchanged',before===digest(await localSnapshot()));
  fs.writeFileSync(path.join(folder,'browser-results.json'),JSON.stringify({passed:checks.length,failed:0,checks,origin:'http://localhost:8081',isolated_profile:true},null,2));
  console.log(`Browser CRUD: ${checks.length} passed, 0 failed`);
} catch(error) {
  await browser?.diagnostics().catch(()=>{});
  fs.writeFileSync(path.join(folder,'browser-results.json'),JSON.stringify({passed:checks.length,failed:1,checks,error:error.message},null,2));
  console.error(error.message);process.exitCode=1;
} finally {browser?.close();}
