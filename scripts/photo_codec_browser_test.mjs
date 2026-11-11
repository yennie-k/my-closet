// Sequential pure-Dart web codec / native browser pixel comparison. No app data.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import {spawn} from 'node:child_process';
const folder=path.resolve(import.meta.dirname,'../build/photo-codec-20261105');
const manifest=JSON.parse(fs.readFileSync(path.join(folder,'manifest.json')));
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const server=http.createServer((req,res)=>{
  if(req.url==='/probe.js'){res.setHeader('Content-Type','text/javascript');fs.createReadStream(path.join(folder,'probe.js')).pipe(res);}
  else {res.setHeader('Content-Type','text/html');res.end(`<!doctype html><script>globalThis.photoProbeInput=${JSON.stringify(JSON.stringify(manifest))};</script><script src="/probe.js" defer></script>`);}
});
let child,ws;
try {
  await new Promise((r,j)=>{server.once('error',j);server.listen(0,'127.0.0.1',r);});
  const url=`http://127.0.0.1:${server.address().port}/`;
  const profile=fs.mkdtempSync(path.join(folder,'edge-codec-'));
  child=spawn(process.env.CHROME_EXECUTABLE||path.join(process.env['PROGRAMFILES(X86)']||process.env.PROGRAMFILES||'','Microsoft/Edge/Application/msedge.exe'),[
    '--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-port=0',`--user-data-dir=${profile}`,url,
  ],{windowsHide:true,stdio:['ignore','ignore','pipe']});
  let stderr='';child.stderr.on('data',b=>stderr+=b);child.on('error',e=>stderr+=e.message);
  let deadline=Date.now()+30000;
  while(!/DevTools listening on (ws:\/\/\S+)/.test(stderr)){assert(Date.now()<deadline,'Edge startup timeout');await pause(100);}
  const port=new URL(stderr.match(/DevTools listening on (ws:\/\/\S+)/)[1]).port;
  let target;
  while(!target){target=(await(await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t=>t.url===url);assert(Date.now()<deadline);if(!target)await pause(100);}
  ws=new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r,j)=>{ws.addEventListener('open',r,{once:true});ws.addEventListener('error',j,{once:true});});
  let sequence=0;const pending=new Map();
  ws.addEventListener('message',e=>{const d=JSON.parse(e.data);if(pending.has(d.id)){const p=pending.get(d.id);pending.delete(d.id);d.error?p.reject(new Error('CDP failed')):p.resolve(d.result);}});
  const send=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;const timer=setTimeout(()=>{pending.delete(id);reject(new Error('CDP timeout'));},60000);pending.set(id,{resolve:v=>{clearTimeout(timer);resolve(v);},reject});ws.send(JSON.stringify({id,method,params}));});
  async function evaluate(expression){const r=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});assert(!r.exceptionDetails,'Browser probe exception');return r.result.value;}
  let output;deadline=Date.now()+60000;
  while(!output){output=await evaluate('globalThis.photoProbeOutput');assert(Date.now()<deadline,'Codec probe timeout');if(!output)await pause(200);}
  const results=JSON.parse(output);
  fs.writeFileSync(path.join(folder,'web-results.json'),JSON.stringify(results));
  // Decode JPEG output with Edge's own codec, independent of Dart's JPEG codec.
  const native=await evaluate(`(async()=>{const output=JSON.parse(photoProbeOutput), result=[];for(const item of output){if(!item.jpeg){result.push({name:item.name});continue;}const im=new Image();im.src='data:image/jpeg;base64,'+item.jpeg;await im.decode();const c=document.createElement('canvas');c.width=im.naturalWidth;c.height=im.naturalHeight;const ctx=c.getContext('2d');ctx.drawImage(im,0,0);const samples=[];for(const y of [.1,.3,.7,.9])for(const x of [.1,.3,.7,.9])samples.push(Array.from(ctx.getImageData(Math.floor(x*c.width),Math.floor(y*c.height),1,1).data).slice(0,3));result.push({name:item.name,samples});}return result;})()`);
  const checks=results.map((r,i)=>{
    const mae=s=>s?Math.round(s.flat().reduce((sum,value,j)=>sum+Math.abs(value-manifest[i].samples.flat()[j]),0)/48*100)/100:null;
    const metric={name:r.name,error:r.error,decoded_mae:mae(r.decoded),output_mae:mae(r.output),edge_jpeg_mae:mae(native[i].samples)};
    metric.passed=!r.error&&metric.decoded_mae<8&&metric.edge_jpeg_mae<8;
    console.log(JSON.stringify(metric));return metric;
  });
  fs.writeFileSync(path.join(folder,'comparison.json'),JSON.stringify({passed:checks.filter(c=>c.passed).length,failed:checks.filter(c=>!c.passed).length,checks},null,2));
  if(checks.some(c=>!c.passed))process.exitCode=1;
} catch(e){console.error(e.message);process.exitCode=1;}
finally{ws?.close();child?.kill();server.close();}
