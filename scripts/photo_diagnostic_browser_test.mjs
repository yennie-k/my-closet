// Only generated synthetic fixtures; diagnostic app has no DB/Storage code.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {startBrowser} from './browser_test_driver.mjs';
const root=path.resolve(import.meta.dirname,'..'),folder=path.join(root,'build/photo-codec-20261105');
let b;const checks=[];
try {
  b=await startBrowser({build:path.join(root,'build/photo_diagnostic_web'),folder,port:8082});
  await b.navigate();await b.waitText('사진 단계별 진단 · 저장하지 않음');
  for(const file of ['2048-420.jpg','png-rgb.png','webp-lossless.webp','exif-6.jpg']) {
    await b.selectFile('진단할 사진 선택',path.join(folder,file));
    await b.waitText('C. 앱에서 사용하는 최종 JPEG');
    await b.waitText('한 장을 순차 처리하고 있어요…',true);
    assert(!(await b.text()).includes('이 단계의 Flutter 디코딩 실패'));
    checks.push({name:file,passed:true});console.log('PASS Flutter Edge preview',file);
    if(file==='2048-420.jpg') {
      const metric=await b.send('Page.getLayoutMetrics');
      fs.writeFileSync(path.join(folder,'flutter-edge-2048.png'),Buffer.from((await b.send('Page.captureScreenshot',{format:'png',captureBeyondViewport:true,clip:{x:0,y:0,width:1280,height:Math.min(2200,metric.cssContentSize.height),scale:1}})).data,'base64'));
    }
  }
  fs.writeFileSync(path.join(folder,'flutter-browser-results.json'),JSON.stringify({passed:checks.length,failed:0,checks,isolated_port:8082},null,2));
}catch(e){console.error(e.message);await b?.diagnostics().catch(()=>{});process.exitCode=1;}
finally{b?.close();}
