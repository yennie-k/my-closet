// Shared local UI-test driver. Isolated Chrome profile; loopback:8081 only.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import {spawn} from 'node:child_process';

const delay=ms=>new Promise(r=>setTimeout(r,ms));
const deep=`function all(root=document){return [...root.querySelectorAll('*')].flatMap(e=>[e,...(e.shadowRoot?all(e.shadowRoot):[])]);}`;
export async function startBrowser({build,folder,redact=[],port=8081,privateMode=false,onProtocolEvent=()=>{}}) {
  assert([8081,8082].includes(port),'Only isolated local test ports');
  const url=`http://${privateMode?'127.0.0.1':'localhost'}:${port}/`, blank=url+'__test_blank';
  const profile=fs.mkdtempSync(path.join(folder,'crud-chrome-'));
  const server=http.createServer((req,res)=>{
    res.setHeader('Cache-Control','no-store');
    if(req.url==='/__test_blank'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><body>Isolated test origin</body>');return;}
    const filename=path.resolve(build,`.${decodeURIComponent(new URL(req.url,url).pathname)}`);
    if(!filename.startsWith(build+path.sep)&&filename!==build){res.writeHead(403);res.end();return;}
    const file=fs.existsSync(filename)&&fs.statSync(filename).isFile()?filename:path.join(build,'index.html');
    res.setHeader('Content-Type',({'.js':'text/javascript','.wasm':'application/wasm','.json':'application/json','.html':'text/html; charset=utf-8','.png':'image/png','.woff2':'font/woff2'})[path.extname(file)]||'application/octet-stream');
    fs.createReadStream(file).pipe(res);
  });
  let chrome,ws,loaded;
  const close=()=>{ws?.close();if(chrome&&chrome.exitCode===null)chrome.kill();server.close();};
  try {
    await new Promise((r,j)=>{server.once('error',j);server.listen(port,'127.0.0.1',r);});
    chrome=spawn(process.env.CHROME_EXECUTABLE||path.join(process.env.PROGRAMFILES||'','Google/Chrome/Application/chrome.exe'),[
      ...(privateMode?[process.env.CHROME_EXECUTABLE?.includes('Edge')?'--inprivate':'--incognito','--disk-cache-size=0','--media-cache-size=0']:[]),
      '--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-port=0',`--user-data-dir=${profile}`,'--window-size=1280,1000',blank,
    ],{windowsHide:true,stdio:['ignore','ignore','pipe']});
    let stderr='';chrome.stderr.on('data',b=>stderr+=b.toString());
    const deadline=Date.now()+30000;
    while(!/DevTools listening on (ws:\/\/[^\s]+)/.test(stderr)){assert(Date.now()<deadline,'Chrome startup timeout');await delay(100);}
    const debugPort=new URL(stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/)[1]).port;
    let target;
    while(!target){target=(await(await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json()).find(t=>t.url===blank);assert(Date.now()<deadline,'Chrome tab timeout');if(!target)await delay(100);}
    ws=new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((r,j)=>{ws.addEventListener('open',r,{once:true});ws.addEventListener('error',j,{once:true});});
    let id=0;const pending=new Map();
    ws.addEventListener('message',e=>{const data=JSON.parse(e.data);if(data.method)onProtocolEvent(data);if(data.method==='Page.loadEventFired'&&loaded){loaded();loaded=null;}if(data.id&&pending.has(data.id)){const p=pending.get(data.id);pending.delete(data.id);data.error?p.reject(new Error('CDP command failed')):p.resolve(data.result);}});
    const send=(method,params={})=>new Promise((r,j)=>{const n=++id;const timer=setTimeout(()=>{pending.delete(n);j(new Error(`CDP timeout: ${method}`));},15000);pending.set(n,{resolve:v=>{clearTimeout(timer);r(v);},reject:e=>{clearTimeout(timer);j(e);}});ws.send(JSON.stringify({id:n,method,params}));});
    const evaluate=async expression=>{
      const data=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});
      if(data.exceptionDetails){let reason=data.exceptionDetails.exception?.description?.split('\n')[0]||'evaluation failed';for(const value of redact)if(value)reason=reason.replaceAll(value,'[REDACTED]');throw new Error(reason);}
      return data.result?.value;
    };
    await send('Page.enable');await send('Network.enable');
    async function navigate(destination=url,reload=false) {
      assert(new URL(destination).origin===new URL(url).origin,'Non-local navigation denied');
      if (!reload && await evaluate('location.href') === destination) reload = true;
      let timer;const load=new Promise((r,j)=>{loaded=r;timer=setTimeout(()=>j(new Error('Page load timeout')),30000);});
      try{await send(reload?'Page.reload':'Page.navigate',reload?{ignoreCache:true}:{url:destination});await load;}finally{loaded=null;clearTimeout(timer);}
    }
    const semantics=()=>evaluate(`(()=>{${deep}all().find(e=>e.tagName==='FLT-SEMANTICS-PLACEHOLDER')?.click();return true;})()`);
    const text=()=>evaluate(`(()=>{${deep}return all().filter(e=>e.tagName==='FLT-SEMANTICS').map(e=>(e.getAttribute('aria-label')||'')+' '+e.textContent).join(' ');})()`);
    async function diagnostics() {
      const labels=await evaluate(`(()=>{${deep}return all().filter(e=>e.tagName==='FLT-SEMANTICS').map(e=>({role:e.getAttribute('role'),label:e.getAttribute('aria-label'),text:e.children.length?null:e.textContent}));})()`);
      fs.writeFileSync(path.join(folder,'crud-ui-diagnostics.json'),JSON.stringify(labels,null,2));
      fs.writeFileSync(path.join(folder,'crud-ui-visible-text.txt'),await text());
      fs.writeFileSync(path.join(folder,'crud-ui-failure.png'),Buffer.from((await send('Page.captureScreenshot',{format:'png'})).data,'base64'));
    }
    async function waitText(value,absent=false) {
      const limit=Date.now()+30000;
      while(Date.now()<limit){await semantics();if((await text()).includes(value)!==absent)return;await delay(120);}
      await diagnostics();throw new Error(`UI timeout: ${value} (${absent?'absent':'present'})`);
    }
    async function pointFor(label,input=false) {
      for(let tries=0;tries<30;tries++) {
        const point=await evaluate(`(()=>{${deep}const label=${JSON.stringify(label)};const es=all();const s=es.filter(e=>e.tagName==='FLT-SEMANTICS');const matches=e=>e.getAttribute('aria-label')===label||e.textContent===label;const interactive=e=>['button','tab','option','menuitem','radio','checkbox'].includes(e.getAttribute('role'));const e=${input?`es.find(e=>['INPUT','TEXTAREA'].includes(e.tagName)&&e.getAttribute('aria-label')===label)`:`s.filter(e=>interactive(e)&&matches(e)).at(-1)||s.filter(e=>interactive(e)&&((e.getAttribute('aria-label')||'').includes(label)||e.textContent.includes(label))).at(-1)||s.find(matches)`};if(!e)return null;const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,height:innerHeight,width:innerWidth};})()`);
        if(!point){if(tries<25){await delay(120);continue;}await diagnostics();throw new Error(`UI control missing: ${label}`);}
        if(point.y>=0&&point.y<point.height&&point.x>=0&&point.x<point.width)return point;
        await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:point.width-45,y:point.height-100,deltaY:point.y<0?-500:500,deltaX:0});await delay(100);
      }
      await diagnostics();throw new Error(`UI control not visible: ${label}`);
    }
    async function click(label) {
      const {x,y}=await pointFor(label);
      await send('Input.dispatchMouseEvent',{type:'mousePressed',button:'left',clickCount:1,x,y});await send('Input.dispatchMouseEvent',{type:'mouseReleased',button:'left',clickCount:1,x,y});await delay(220);
    }
    async function fill(label,value) {
      const {x,y}=await pointFor(label,true);
      await send('Input.dispatchMouseEvent',{type:'mousePressed',button:'left',clickCount:1,x,y});await send('Input.dispatchMouseEvent',{type:'mouseReleased',button:'left',clickCount:1,x,y});
      await evaluate(`(()=>{${deep}all().find(e=>['INPUT','TEXTAREA'].includes(e.tagName)&&e.getAttribute('aria-label')===${JSON.stringify(label)})?.focus();return true;})()`);
      await delay(120);
      await send('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});await send('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});await send('Input.insertText',{text:value});
      await delay(200);
      // Hint-only fields lose their aria-label after becoming non-empty.
      assert(await evaluate(`(()=>{${deep}return all().some(e=>['INPUT','TEXTAREA'].includes(e.tagName)&&e.value===${JSON.stringify(value)});})()`),`Input did not retain value: ${label}`);
    }
    async function selectFile(label,file) {
      assert(path.resolve(file).startsWith(path.resolve(folder)+path.sep),'Only synthetic test files allowed');
      await send('Page.setInterceptFileChooserDialog',{enabled:true});
      await click(label);
      const document=await send('DOM.getDocument');
      let input;
      for(let attempt=0;attempt<25;attempt++){
        input=await send('DOM.querySelector',{nodeId:document.root.nodeId,selector:'file-selector input[type=file]'});
        if(input.nodeId)break;await delay(100);
      }
      assert(input?.nodeId,'Synthetic file input not found');
      await send('DOM.setFileInputFiles',{nodeId:input.nodeId,files:[path.resolve(file)]});
      await delay(400);
    }
    while(!(await evaluate(`document.readyState==='complete'&&document.body?.textContent==='Isolated test origin'`))){
      if(Date.now()>=deadline)throw new Error('Blank page timeout: '+await evaluate(`JSON.stringify({url:location.href,state:document.readyState,title:document.title,body:document.body?.textContent?.slice(0,200)})`));
      await delay(100);
    }
    return {url,evaluate,send,navigate,reload:()=>navigate(url,true),text,waitText,click,fill,selectFile,diagnostics,close,delay};
  } catch(e){close();throw e;}
}
