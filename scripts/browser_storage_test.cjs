// Run a compiled production repository probe, reload the actual browser page,
// then verify its persisted metadata and image in a fresh JavaScript context.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { spawn } = require('node:child_process');
const root = path.resolve(__dirname, '..', 'build', 'storage_probe');
const chrome = process.env.CHROME_EXECUTABLE || path.join(process.env.PROGRAMFILES || '', 'Google/Chrome/Application/chrome.exe');
const profile = fs.mkdtempSync(path.join(root, 'chrome-profile-'));
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const server = http.createServer((req, res) => {
  if (req.url === '/probe.js') { res.setHeader('content-type', 'text/javascript'); fs.createReadStream(path.join(root, 'probe.js')).pipe(res); }
  else { res.setHeader('content-type', 'text/html; charset=utf-8'); res.end('<!doctype html><html lang="ko"><body><script src="/probe.js" defer></script></body></html>'); }
});
let child, ws;
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}/`;
  child = spawn(chrome, ['--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--remote-debugging-port=0', `--user-data-dir=${profile}`, url], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
  let stderr = '';
  child.stderr.on('data', chunk => { stderr += chunk.toString(); });
  child.on('error', error => { stderr += error.message; });
  const deadline = Date.now() + 25000;
  while (!/DevTools listening on (ws:\/\/[^\s]+)/.test(stderr)) {
    if (Date.now() > deadline) throw new Error('Chrome did not start: ' + stderr.slice(-1000));
    await delay(100);
  }
  const browserUrl = stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/)[1];
  const port = new URL(browserUrl).port;
  let target;
  while (!target) {
    const tabs = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    target = tabs.find(tab => tab.url === url);
    if (Date.now() > deadline) throw new Error('Probe tab did not open');
    if (!target) await delay(100);
  }
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.addEventListener('open', resolve, {once:true}); ws.addEventListener('error', reject, {once:true}); });
  const pending = new Map(); let nextId = 0;
  ws.addEventListener('message', event => {
    const result = JSON.parse(event.data);
    if (result.id && pending.has(result.id)) { const p = pending.get(result.id); pending.delete(result.id); result.error ? p.reject(new Error(JSON.stringify(result.error))) : p.resolve(result.result); }
  });
  function send(method, params = {}) {
    return new Promise((resolve, reject) => { const id = ++nextId; pending.set(id, {resolve, reject}); ws.send(JSON.stringify({id, method, params})); });
  }
  async function waitStatus(expected) {
    const limit = Date.now() + 20000;
    while (Date.now() < limit) {
      const result = await send('Runtime.evaluate', {expression: 'document.body && document.body.textContent', returnByValue: true});
      const text = result.result?.value || '';
      if (text.includes('PROBE_ERROR')) throw new Error(text);
      if (text.includes(expected)) return text;
      await delay(100);
    }
    throw new Error('Timed out waiting for ' + expected);
  }
  console.log(await waitStatus('WRITE_OK'));
  await send('Page.reload', {ignoreCache: true});
  console.log(await waitStatus('READ_AFTER_RELOAD_OK'));
  await send('Page.reload', {ignoreCache: true});
  console.log(await waitStatus('UPDATED_AFTER_RELOAD_OK'));
  console.log('PASS: v1 read did not overwrite data; v2 update + binary photos survived two actual page reloads.');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  if (ws) ws.close();
  if (child && child.exitCode === null) child.kill();
  server.close();
  // Keep the isolated test profile under ignored build/ for inspection.
});
