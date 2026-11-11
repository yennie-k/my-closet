// Isolated Edge, synthetic text, process-memory wardrobe; no user data/APIs.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {startBrowser} from './browser_test_driver.mjs';

const folder = path.resolve('build/unsaved-guard-20261109');
fs.mkdirSync(folder,{recursive:true});
process.env.CHROME_EXECUTABLE ||= path.join(process.env['PROGRAMFILES(X86)']||process.env.PROGRAMFILES||'','Microsoft/Edge/Application/msedge.exe');
const dialogs = [], checks = [];
let browser;
const record = name => { checks.push(name); console.log('PASS '+name); };
try {
  browser = await startBrowser({build:path.resolve('build/web_guard_probe'),folder,
    port:8082,privateMode:true,onProtocolEvent:event=>{
      if(event.method==='Page.javascriptDialogOpening') dialogs.push(event.params.type);
    }});
  const {send,evaluate,click,fill,waitText,delay} = browser;
  await send('Network.setBlockedURLs',{urls:['*supabase*','http://127.0.0.1:54321/*','http://localhost:54321/*']});
  await browser.navigate(); await waitText('합성 편집 열기');
  const cancelled = () => evaluate(`(()=>{const e=new Event('beforeunload',{cancelable:true});window.dispatchEvent(e);return e.defaultPrevented;})()`);
  assert.equal(await cancelled(),false); record('clean page has no beforeunload cancellation');
  await click('합성 편집 열기'); await waitText('새로운 옷 등록');
  assert.equal(await cancelled(),false); record('untouched editor has no warning');
  await fill('의류 이름 *','Synthetic unsaved draft');
  assert.equal(await cancelled(),true); record('typing attaches beforeunload guard');
  async function nativeAttempt(method, params={}) {
    const count=dialogs.length;
    const command=send(method,params);
    const deadline=Date.now()+10000;
    while(dialogs.length===count&&Date.now()<deadline) await delay(50);
    assert(dialogs.length>count,method+' did not open a native warning');
    assert.equal(dialogs.at(-1),'beforeunload');
    await send('Page.handleJavaScriptDialog',{accept:false});
    await command;
    await waitText('새로운 옷 등록');
    assert.equal(await cancelled(),true);
    assert.equal(await evaluate(`(()=>{function all(r=document){return [...r.querySelectorAll('*')].flatMap(e=>[e,...(e.shadowRoot?all(e.shadowRoot):[])]);}return all().some(e=>['INPUT','TEXTAREA'].includes(e.tagName)&&e.value==='Synthetic unsaved draft');})()`),true);
  }
  await nativeAttempt('Page.reload',{ignoreCache:true}); record('actual native reload warning cancelled; draft retained');
  const history=await send('Page.getNavigationHistory');
  // The named probe route may be an in-document Flutter history entry. Going
  // back to the blank test document explicitly exercises document-leaving back.
  const blank=history.entries.find(e=>e.url.endsWith('/__test_blank'));
  assert(blank,'isolated previous document missing');
  await nativeAttempt('Page.navigateToHistoryEntry',{entryId:blank.id});
  record('document-leaving browser back warning cancelled; editor retained');
  await nativeAttempt('Page.close'); record('actual tab close warning cancelled; editor retained');
  await fill('의류 이름 *','');
  assert.equal(await cancelled(),false); record('reverting text removes beforeunload listener');
  // The same input remains focused; Flutter may temporarily omit its label
  // after clearing. Type through the actual input channel rather than relying
  // on that transient accessibility label for a second lookup.
  await send('Input.insertText',{text:'Synthetic unsaved draft'}); await delay(250);
  assert.equal(await cancelled(),true);
  await click('Back'); await waitText('변경사항이 저장되지 않았어요');
  await click('계속 수정'); await waitText('새로운 옷 등록');
  assert.equal(await cancelled(),true); record('continue editing preserves browser protection');
  await click('Back'); await waitText('변경사항이 저장되지 않았어요');
  await click('저장하지 않고 나가기'); await waitText('합성 편집 열기');
  assert.equal(await cancelled(),false); record('discard disposes beforeunload listener');
  // Clean reload must be possible after disposal.
  const before=dialogs.length; await browser.reload(); await waitText('합성 편집 열기');
  assert.equal(dialogs.length,before); record('clean reload completes without native warning');
  fs.writeFileSync(path.join(folder,'edge-results.json'),JSON.stringify({passed:checks.length,failed:0,
    checks,browser:'isolated Edge InPrivate',actual_user_data_accessed:false,api_calls:0},null,2));
} catch(error) {
  fs.writeFileSync(path.join(folder,'edge-results.json'),JSON.stringify({passed:checks.length,failed:1,
    checks,error:error.message},null,2));
  console.error(error.message); process.exitCode=1;
} finally { browser?.close(); }
