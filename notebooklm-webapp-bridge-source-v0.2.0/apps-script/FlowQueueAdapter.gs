const FLOW_ADAPTER_VERSION = 'FLOW_QUEUE_ADAPTER_V1_20260825';
const DEFAULT_FLOW_SPREADSHEET_ID = '1bpilaFQ9vMNF9lKL76sKbD-08Xupz3KKsGS7C04om4M';
const DEFAULT_FLOW_SHEET_NAME = 'BRIDGE_TASKS';
const FLOW_RUNNER_ID = 'FLOW_AGENT_BRIDGE_V0.1.0';

function flowJson_(data) {
  return ContentService.createTextOutput(JSON.stringify(data)).setMimeType(ContentService.MimeType.JSON);
}

function flowRequireToken_(token) {
  const expected = PropertiesService.getScriptProperties().getProperty('FLOW_QUEUE_TOKEN');
  if (!expected) throw new Error('FLOW_QUEUE_TOKEN_NOT_CONFIGURED');
  if (String(token || '') !== String(expected)) throw new Error('FLOW_QUEUE_TOKEN_INVALID');
}

function flowSpreadsheet_() {
  const p = PropertiesService.getScriptProperties();
  const id = p.getProperty('FLOW_SPREADSHEET_ID') || DEFAULT_FLOW_SPREADSHEET_ID;
  return SpreadsheetApp.openById(id);
}

function flowSheet_() {
  const p = PropertiesService.getScriptProperties();
  const name = p.getProperty('FLOW_TASK_SHEET_NAME') || DEFAULT_FLOW_SHEET_NAME;
  const sh = flowSpreadsheet_().getSheetByName(name);
  if (!sh) throw new Error('FLOW_TASK_SHEET_NOT_FOUND:' + name);
  return sh;
}

function flowHeaderMap_(sh) {
  if (sh.getLastRow() < 1) throw new Error('FLOW_TASK_SHEET_EMPTY');
  const headers = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0].map(String);
  const map = {};
  headers.forEach((h, i) => { if (h) map[h] = i + 1; });
  ['TASK_ID','TARGET','ACTION','PAYLOAD_JSON','STATUS','RUNNER_ID','CLAIMED_AT','UPDATED_AT','RESULT_JSON','ERROR'].forEach(h => {
    if (!map[h]) throw new Error('FLOW_HEADER_MISSING:' + h);
  });
  return map;
}

function flowCell_(row, map, key) {
  return row[map[key] - 1];
}

function flowSet_(sh, rowNumber, map, patch) {
  Object.keys(patch).forEach(key => {
    if (map[key]) sh.getRange(rowNumber, map[key]).setValue(patch[key]);
  });
}

function flowParsePayload_(raw) {
  if (raw && typeof raw === 'object') return raw;
  const text = String(raw || '').trim();
  if (!text) return {};
  try { return JSON.parse(text); } catch (_e) { return { prompt: text }; }
}

function flowExtractPrompt_(payload) {
  const prompt = payload.prompt || payload.PROMPT || payload.promptText || payload.prompt_text ||
    payload.scenePrompt || payload.SCENE_PROMPT || payload.input || payload.INPUT || payload.text || '';
  return String(prompt || '').trim();
}

function nextFlowTask_(params) {
  flowRequireToken_(params && params.token);
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(8000)) throw new Error('FLOW_QUEUE_LOCK_BUSY');
  try {
    const sh = flowSheet_();
    const map = flowHeaderMap_(sh);
    const lastRow = sh.getLastRow();
    if (lastRow < 2) return { ok:false, error:'NO_FLOW_TASK' };
    const rows = sh.getRange(2, 1, lastRow - 1, sh.getLastColumn()).getValues();
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const target = String(flowCell_(row, map, 'TARGET') || '').toUpperCase();
      const action = String(flowCell_(row, map, 'ACTION') || '').toUpperCase();
      const status = String(flowCell_(row, map, 'STATUS') || '').toUpperCase();
      if (target !== 'FLOW') continue;
      if (action.indexOf('GENERATE') !== 0) continue;
      if (['QUEUED','READY','RETRY'].indexOf(status) < 0) continue;
      const payload = flowParsePayload_(flowCell_(row, map, 'PAYLOAD_JSON'));
      const prompt = flowExtractPrompt_(payload);
      if (!prompt) continue;
      const taskId = String(flowCell_(row, map, 'TASK_ID') || '');
      const now = new Date();
      flowSet_(sh, i + 2, map, {
        STATUS:'CLAIMED', RUNNER_ID:FLOW_RUNNER_ID, CLAIMED_AT:now, UPDATED_AT:now, ERROR:''
      });
      return {
        ok:true,
        adapterVersion:FLOW_ADAPTER_VERSION,
        task:{ taskId, prompt, action, payload, status:'CLAIMED', runnerId:FLOW_RUNNER_ID }
      };
    }
    return { ok:false, error:'NO_FLOW_TASK' };
  } finally {
    lock.releaseLock();
  }
}

function completeFlowTask_(body) {
  flowRequireToken_(body && body.token);
  const taskId = String((body && body.taskId) || '').trim();
  if (!taskId) throw new Error('FLOW_TASK_ID_REQUIRED');
  const sh = flowSheet_();
  const map = flowHeaderMap_(sh);
  const lastRow = sh.getLastRow();
  if (lastRow < 2) throw new Error('FLOW_TASK_NOT_FOUND:' + taskId);
  const rows = sh.getRange(2, 1, lastRow - 1, sh.getLastColumn()).getValues();
  const index = rows.findIndex(row => String(flowCell_(row, map, 'TASK_ID')) === taskId);
  if (index < 0) throw new Error('FLOW_TASK_NOT_FOUND:' + taskId);
  const rowNumber = index + 2;
  const currentRunner = String(flowCell_(rows[index], map, 'RUNNER_ID') || '');
  if (currentRunner && currentRunner !== FLOW_RUNNER_ID) throw new Error('FLOW_TASK_CLAIMED_BY_OTHER_RUNNER');
  const requestedStatus = String((body && body.status) || 'SUBMITTED').toUpperCase();
  const allowed = ['SUBMITTED','DONE','ERROR','REVIEW'];
  const status = allowed.indexOf(requestedStatus) >= 0 ? requestedStatus : 'SUBMITTED';
  const result = (body && (body.flowResult || body.result)) || {};
  const now = new Date();
  flowSet_(sh, rowNumber, map, {
    STATUS:status,
    RUNNER_ID:FLOW_RUNNER_ID,
    UPDATED_AT:now,
    RESULT_JSON:JSON.stringify({ adapterVersion:FLOW_ADAPTER_VERSION, submittedAt:(body && body.submittedAt) || now.toISOString(), result }),
    ERROR:status === 'ERROR' ? String((body && body.error) || 'FLOW_SUBMIT_ERROR') : ''
  });
  return { ok:true, adapterVersion:FLOW_ADAPTER_VERSION, taskId, status };
}

function flowHealth_(params) {
  flowRequireToken_(params && params.token);
  const sh = flowSheet_();
  const map = flowHeaderMap_(sh);
  return {
    ok:true,
    adapterVersion:FLOW_ADAPTER_VERSION,
    spreadsheetId:sh.getParent().getId(),
    sheetName:sh.getName(),
    rowCount:Math.max(0, sh.getLastRow() - 1),
    headersReady:!!map.TASK_ID
  };
}

function setupFlowQueueAdapter() {
  const p = PropertiesService.getScriptProperties();
  if (!p.getProperty('FLOW_SPREADSHEET_ID')) p.setProperty('FLOW_SPREADSHEET_ID', DEFAULT_FLOW_SPREADSHEET_ID);
  if (!p.getProperty('FLOW_TASK_SHEET_NAME')) p.setProperty('FLOW_TASK_SHEET_NAME', DEFAULT_FLOW_SHEET_NAME);
  if (!p.getProperty('FLOW_QUEUE_TOKEN')) p.setProperty('FLOW_QUEUE_TOKEN', Utilities.getUuid() + Utilities.getUuid());
  const sh = flowSheet_();
  flowHeaderMap_(sh);
  return {
    ok:true,
    adapterVersion:FLOW_ADAPTER_VERSION,
    spreadsheetId:sh.getParent().getId(),
    sheetName:sh.getName(),
    queueTokenReady:!!p.getProperty('FLOW_QUEUE_TOKEN')
  };
}
