import fs from 'node:fs';
import http from 'node:http';
import { pathToFileURL } from 'node:url';

export const EXTENSION_ID = 'gedfnhdibkfgacmkbjgpfjihacalnlpn';
export const EXTENSION_URL = `chrome-extension://${EXTENSION_ID}/sidepanel.html`;
export const SELECTORS = Object.freeze({
  prompt: '#prompt-input',
  addQueue: '#add-to-queue-button',
  start: '#start-button',
  stop: '#stop-button',
  clearQueue: '#clear-queue-button',
  autoDownload: '#auto-download-input',
  downloadFolder: '#download-folder-input',
  ratio16x9: '[data-aspect-value="16:9"]'
});

function arg(name, fallback = '') {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}

export function validateOutputSubfolder(value) {
  const s = String(value ?? '').trim().replaceAll('\\', '/');
  if (!s || s.startsWith('/') || /^[A-Za-z]:\//.test(s) || s.includes('..')) throw new Error('UNSAFE_OUTPUT_SUBFOLDER');
  if (!/^ChatGPT-Auto\/[A-Za-z0-9._/-]+$/.test(s)) throw new Error('OUTPUT_SUBFOLDER_POLICY_MISMATCH');
  return s;
}

export function normalizeTask(raw) {
  const t = raw && typeof raw === 'object' ? raw : {};
  const taskId = String(t.taskId ?? '').trim();
  const prompt = String(t.prompt ?? '').trim();
  if (!taskId || !prompt) throw new Error('TASK_REQUIRED_FIELDS_MISSING');
  if (!/^[A-Za-z0-9._-]{4,120}$/.test(taskId)) throw new Error('TASK_ID_POLICY_MISMATCH');
  const outputSubfolder = validateOutputSubfolder(t.outputSubfolder || `ChatGPT-Auto/BIND08_${taskId}`);
  const aspectRatio = String(t.aspectRatio || '16:9');
  if (aspectRatio !== '16:9') throw new Error('ONLY_16_9_CANARY_ALLOWED_V1');
  return { taskId, prompt, outputSubfolder, aspectRatio };
}

export function validatePreflight(p) {
  if (!p || p.ok !== true) throw new Error(p?.reason || 'PREFLIGHT_FAILED');
  if (Array.isArray(p.missing) && p.missing.length) throw new Error(`SELECTOR_MISSING:${p.missing.join(',')}`);
  if (p.running) throw new Error('EXTENSION_ALREADY_RUNNING');
  if (Number(p.queueJobs || 0) !== 0 || Number(p.pendingCollect || 0) !== 0 || Number(p.pendingDescriptors || 0) !== 0) throw new Error('EXTENSION_QUEUE_NOT_EMPTY');
  if (String(p.authState || '').toLowerCase() !== 'ready') throw new Error('CHATGPT_AUTH_NOT_READY');
  if (p.blocker) throw new Error(`READINESS_BLOCKER:${String(p.blocker)}`);
  return true;
}

function requestJson(port, path, method = 'GET') {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname: '127.0.0.1', port, path, method }, res => {
      let body = '';
      res.on('data', c => { body += c; });
      res.on('end', () => {
        if (res.statusCode < 200 || res.statusCode >= 300) return reject(new Error(`CDP_HTTP_${res.statusCode}`));
        try { resolve(JSON.parse(body)); } catch (e) { reject(e); }
      });
    });
    req.on('error', reject);
    req.end();
  });
}

async function getTarget(port, allowOpen) {
  let targets = await requestJson(port, '/json');
  let target = targets.find(t => t.type === 'page' && t.url === EXTENSION_URL);
  if (!target && allowOpen) {
    const created = await requestJson(port, `/json/new?${encodeURIComponent(EXTENSION_URL)}`, 'PUT');
    target = created;
  }
  if (!target?.webSocketDebuggerUrl) throw new Error('EXTENSION_SIDEPANEL_TARGET_ABSENT');
  return target;
}

class Cdp {
  constructor(url) { this.url = url; this.seq = 0; this.pending = new Map(); }
  async open() {
    if (typeof WebSocket !== 'function') throw new Error('NODE_WEBSOCKET_UNAVAILABLE');
    this.ws = new WebSocket(this.url);
    this.ws.onmessage = ev => {
      const m = JSON.parse(ev.data);
      if (!m.id || !this.pending.has(m.id)) return;
      const p = this.pending.get(m.id); this.pending.delete(m.id);
      m.error ? p.reject(new Error(m.error.message || 'CDP_ERROR')) : p.resolve(m.result);
    };
    await new Promise((resolve, reject) => { this.ws.onopen = resolve; this.ws.onerror = () => reject(new Error('CDP_WS_OPEN_FAILED')); });
  }
  call(method, params = {}) {
    return new Promise((resolve, reject) => {
      const id = ++this.seq; this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }
  async eval(expression) {
    const r = await this.call('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    if (r.exceptionDetails) throw new Error(`CDP_EVAL_EXCEPTION:${r.exceptionDetails.text || 'unknown'}`);
    return r.result?.value;
  }
  close() { try { this.ws?.close(); } catch {} }
}

function preflightExpression() {
  const selectors = JSON.stringify(Object.values(SELECTORS));
  return `(async()=>{const sels=${selectors};const missing=sels.filter(s=>!document.querySelector(s));const st=await chrome.storage.local.get({appSettings:{},appSession:{},jobLedger:[]});const s=st.appSession||{};return {ok:missing.length===0,missing,running:Boolean(s.running),queueJobs:Array.isArray(s.queue?.jobs)?s.queue.jobs.length:0,pendingCollect:Array.isArray(s.pendingCollect)?s.pendingCollect.length:0,pendingDescriptors:Array.isArray(s.pendingDescriptors)?s.pendingDescriptors.length:0,authState:s.readiness?.authState??null,state:s.readiness?.state??null,surface:s.readiness?.surface??null,blocker:s.readiness?.blocker??null,ledgerCount:Array.isArray(st.jobLedger)?st.jobLedger.length:0,autoDownload:Boolean(st.appSettings?.autoDownload),downloadFolder:st.appSettings?.downloadFolder??null};})()`;
}

function stageExpression(task) {
  const payload = JSON.stringify(task);
  const selectors = JSON.stringify(SELECTORS);
  return `(async()=>{const t=${payload},S=${selectors};const q=s=>document.querySelector(s);const setValue=(el,v)=>{const proto=el instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const set=Object.getOwnPropertyDescriptor(proto,'value')?.set;if(!set)throw new Error('NATIVE_VALUE_SETTER_MISSING');set.call(el,v);el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));};const prompt=q(S.prompt),folder=q(S.downloadFolder),auto=q(S.autoDownload),ratio=q(S.ratio16x9),add=q(S.addQueue),start=q(S.start);if(!prompt||!folder||!auto||!ratio||!add||!start)throw new Error('EXACT_SELECTOR_MISSING');setValue(folder,t.outputSubfolder);if(!auto.checked){auto.click();await new Promise(r=>setTimeout(r,150));}setValue(prompt,t.prompt);ratio.click();await new Promise(r=>setTimeout(r,150));add.click();await new Promise(r=>setTimeout(r,350));const st=await chrome.storage.local.get({appSession:{}});const jobs=st.appSession?.queue?.jobs??[];if(jobs.length!==1)throw new Error('QUEUE_STAGE_COUNT_NOT_ONE');const job=jobs[0];if(!job?.id)throw new Error('QUEUE_JOB_ID_MISSING');start.click();return {ok:true,jobId:job.id,compiledPrompt:job.prompt??null,outputSubfolder:t.outputSubfolder,startedAt:new Date().toISOString()};})()`;
}

function pollExpression(jobId, startedAt, outputSubfolder) {
  const j = JSON.stringify(jobId), start = JSON.stringify(startedAt), folder = JSON.stringify(outputSubfolder);
  return `(async()=>{const st=await chrome.storage.local.get({appSession:{},jobLedger:[]});const s=st.appSession||{},ledger=Array.isArray(st.jobLedger)?st.jobLedger:[];const matches=ledger.filter(x=>x?.jobId===${j});const last=matches[matches.length-1]??null;const downloads=await chrome.downloads.search({startedAfter:${start},orderBy:['-startTime'],limit:50});const needle='/' + ${folder}.replaceAll('\\\\','/').replace(/^\\/+|\\/+$/g,'') + '/';const d=downloads.find(x=>String(x.filename||'').replaceAll('\\\\','/').includes(needle))??null;return {running:Boolean(s.running),queueJobs:Array.isArray(s.queue?.jobs)?s.queue.jobs.length:0,currentIndex:Number(s.queue?.currentIndex||0),lastStatus:last?.status??null,lastError:last?.errorMessage??null,conversationUrl:last?.conversationUrl??null,download:d?{id:d.id,state:d.state,filename:d.filename,fileSize:d.fileSize??0,mime:d.mime??null,startTime:d.startTime??null,endTime:d.endTime??null}:null};})()`;
}

function clearExpression() {
  return `(async()=>{const b=document.querySelector(${JSON.stringify(SELECTORS.clearQueue)});if(!b)throw new Error('CLEAR_QUEUE_SELECTOR_MISSING');b.click();await new Promise(r=>setTimeout(r,250));const st=await chrome.storage.local.get({appSession:{}});return {queueJobs:st.appSession?.queue?.jobs?.length??0,running:Boolean(st.appSession?.running)};})()`;
}

async function run() {
  const mode = arg('mode', 'preflight');
  const port = Number(arg('port', '9224'));
  if (mode === 'self-test') return { ok: true, mode, selectors: SELECTORS, extensionId: EXTENSION_ID };
  const taskFile = arg('task-file');
  const task = taskFile ? normalizeTask(JSON.parse(fs.readFileSync(taskFile, 'utf8'))) : null;
  const target = await getTarget(port, true);
  const cdp = new Cdp(target.webSocketDebuggerUrl);
  try {
    await cdp.open();
    const preflight = await cdp.eval(preflightExpression());
    validatePreflight(preflight);
    if (mode === 'preflight') return { ok: true, mode, targetUrl: target.url, preflight };
    if (mode !== 'execute' || !task) throw new Error('EXECUTE_TASK_REQUIRED');
    const staged = await cdp.eval(stageExpression(task));
    const deadline = Date.now() + Number(arg('timeout-ms', '360000'));
    let last = null;
    while (Date.now() < deadline) {
      await new Promise(r => setTimeout(r, 1000));
      last = await cdp.eval(pollExpression(staged.jobId, staged.startedAt, task.outputSubfolder));
      if (last.lastStatus === 'failed' || last.lastStatus === 'error') throw new Error(`EXTENSION_JOB_FAILED:${last.lastError || 'unknown'}`);
      if (last.lastStatus === 'success' && last.download?.state === 'complete') {
        const cleared = await cdp.eval(clearExpression());
        if (cleared.running || Number(cleared.queueJobs) !== 0) throw new Error('QUEUE_CLEAR_READBACK_FAILED');
        return { ok: true, mode, taskId: task.taskId, jobId: staged.jobId, startedAt: staged.startedAt, outputSubfolder: task.outputSubfolder, ledgerStatus: last.lastStatus, download: last.download, queueReadback: cleared };
      }
    }
    throw new Error(`CANARY_TIMEOUT:${JSON.stringify(last)}`);
  } finally { cdp.close(); }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  run().then(v => { console.log(JSON.stringify(v)); process.exit(v.ok ? 0 : 2); }).catch(e => { console.error(JSON.stringify({ ok: false, error: String(e?.message || e) })); process.exit(2); });
}
