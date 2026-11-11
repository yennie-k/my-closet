import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomBytes} from 'node:crypto';
import * as magick from '../build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/index.js';
import {startBrowser} from './browser_test_driver.mjs';
const root=fileURLToPath(new URL('..',import.meta.url)),folder=path.resolve(process.argv[2]||'');
assert(folder.startsWith(path.join(root,'build','supabase-photo-flow')+path.sep));
const ctx=JSON.parse(fs.readFileSync(path.join(folder,'private-context.json')));assert.equal(ctx.api,'http://127.0.0.1:54321');
await magick.initializeImageMagick(fs.readFileSync(path.join(root,'build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/x86/magick.wasm')));
fs.writeFileSync(path.join(folder,'replacement.png'),magick.ImageMagick.read(new magick.MagickColor('#75634e'),24,18,img=>img.write(magick.MagickFormat.Png,b=>Uint8Array.from(b))));
fs.writeFileSync(path.join(folder,'invalid.png'),'synthetic invalid image');
let browser;const checks=[];
const record=(name,value=true)=>{assert(value,name);checks.push({name,passed:true});console.log('PASS',name);};
try {
  browser=await startBrowser({build:path.join(root,'build','web_photos'),folder,redact:Object.values(ctx.users).map(u=>u.password)});
  const {send,evaluate,navigate,reload,click,fill,waitText,text,selectFile,delay}=browser;
  await evaluate(`localStorage.setItem('my_closet.preferences.v1',JSON.stringify(JSON.stringify({version:1,design:'minimal',styles:['캐주얼'],temperature:'normal',onboardingComplete:true})))`);
  const route='http://localhost:8081/#/dev/server-wardrobe-crud';await navigate(route);await waitText('로그인 후 서버 의류 정보를 관리할 수 있어요.');
  async function login(who){await click('로그인 / 회원가입');await waitText('이메일로 로그인');await fill('이메일',ctx.users[who].email);await fill('비밀번호',ctx.users[who].password);await click('이메일로 로그인');await waitText('서버 새로고침');await delay(300);}
  await login('a');record('real_user_login');
  const name=`Edge 사진 ${randomBytes(4).toString('hex')}`;
  await click('옷 추가');await waitText('사진은 선택 사항이에요.');
  await selectFile('사진 선택',path.join(folder,'invalid.png'));await waitText('손상된 사진이에요.');record('invalid_file_rejected_in_UI');
  await selectFile('사진 선택',path.join(folder,'synthetic.jpg'));await waitText('사진 변경');record('synthetic_selection_and_preview');
  await fill('의류 이름 *',name);await click('카테고리 *');await click('상의');await click('옷 저장하기');await waitText(name+' 사진');record('UI_upload_and_verified_card');
  const rowByName=()=>evaluate(`(async()=>{const s=JSON.parse(localStorage.getItem('my_closet.local_supabase.auth.v1'));const r=await fetch(${JSON.stringify(ctx.api+'/rest/v1/garments?select=id,photo_state,photo_path,photo_verified_at,retired_photo_path&name=eq.'+encodeURIComponent(name))},{headers:{apikey:${JSON.stringify(ctx.publishableKey)},Authorization:'Bearer '+s.access_token},cache:'no-store'});return (await r.json())[0];})()`);
  let row=await rowByName();assert(row.photo_state==='ready'&&row.photo_verified_at&&row.photo_path);const original=row.photo_path;record('server_ready_attestation_confirmed');
  await reload();await waitText(name+' 사진');record('actual_reload_keeps_authenticated_photo');
  await click(name);await waitText('서버에서 검증된 사진이에요.');record('verified_detail');
  await click('정보 수정');await waitText('사진 변경');await selectFile('사진 변경',path.join(folder,'replacement.png'));await click('옷 저장하기');await waitText('이전 사진 정리 가능 시각');
  row=await rowByName();record('replacement_active_and_retired_paths',row.photo_path!==original&&row.retired_photo_path===original);const replaced=row.photo_path;
  await click('정보 수정');await selectFile('사진 변경',path.join(folder,'synthetic.jpg'));await click('옷 저장하기');await waitText('이전 사진 보호 기간에는 다시 교체하거나 의류를 삭제할 수 없어요.');
  record('replacement_rejection_keeps_prior_active',(await rowByName()).photo_path===replaced);
  await click('서버 로그아웃');await waitText('로그인 후 서버 의류 정보를 관리할 수 있어요.');record('logout_removes_photo_and_editor',!(await text()).includes(name));
  await login('b');record('other_user_no_previous_photo',!(await text()).includes(name));
  const denied=await evaluate(`(async()=>{const s=JSON.parse(localStorage.getItem('my_closet.local_supabase.auth.v1'));const r=await fetch(${JSON.stringify(ctx.api+'/storage/v1/object/authenticated/garment-photos/'+replaced)},{headers:{apikey:${JSON.stringify(ctx.publishableKey)},Authorization:'Bearer '+s.access_token},cache:'no-store'});return r.ok;})()`);
  record('browser_other_user_download_denied',!denied);
  await click('서버 로그아웃');await waitText('로그인 후 서버 의류 정보를 관리할 수 있어요.');await login('a');await waitText(name+' 사진');record('relogin_restores_only_own_verified_photo');
  await send('Emulation.setDeviceMetricsOverride',{width:360,height:800,deviceScaleFactor:1,mobile:true});await delay(200);await click(name);await waitText('서버에서 검증된 사진이에요.');
  record('mobile_photo_detail_no_horizontal_overflow',await evaluate('document.documentElement.scrollWidth<=innerWidth'));
  fs.writeFileSync(path.join(folder,'edge-photo-ui.png'),Buffer.from((await send('Page.captureScreenshot',{format:'png'})).data,'base64'));
  // Existing within-this-run HTTP fixture has an active photo and no retired
  // slot. Schedule removal through UI; never delete protected existing data.
  await navigate(route);await waitText('서버 새로고침');await fill('의류 이름으로 검색','PHOTO FLOW png');await waitText('PHOTO FLOW png');await click('PHOTO FLOW png');await click('사진 삭제 예약');await waitText('이 사진 작업을 진행할까요?');await click('진행하기');await waitText('서버에서 승인된 사진이 없어요.');record('photo_removal_scheduled_in_UI');
  await click('의류 삭제');await click('삭제하기');await waitText('사진 또는 업로드 예약이 남아 있어 의류를 삭제하지 않았어요.');record('garment_delete_respects_photo_grace');
  fs.writeFileSync(path.join(folder,'browser-photo-results.json'),JSON.stringify({browser:process.env.CHROME_EXECUTABLE?.includes('Edge')?'Edge':'Chrome',passed:checks.length,failed:0,checks,origin:'http://localhost:8081',isolated_profile:true},null,2));
  console.log(JSON.stringify({passed:checks.length,failed:0}));
}catch(e){await browser?.diagnostics().catch(()=>{});fs.writeFileSync(path.join(folder,'browser-photo-results.json'),JSON.stringify({passed:checks.length,failed:1,checks,error:e.message},null,2));console.error(e.message);process.exitCode=1;}
finally{browser?.close();}
