const CNRH_VERSION = 'CENTRAL_NOTEBOOK_RUNTIME_HUB_V1_20260828';
const CNRH_MASTER_REGISTRY_ID = '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI';
const CNRH_CENTRAL_FOLDER_ID = '1mAu8N8EfThhkM3D-axvOLi0pY4ryQKcS';
const CNRH_PROJECT_ID = 'contents-os-gcp';

/** Daily central check: local notebook runtime + workflow/front support + publish/pack readiness. */
function runCentralNotebookRuntimeHubDailyV1() {
  return runCentralNotebookRuntimeHubPreflightV1({source: 'DAILY_TRIGGER', deep: true});
}

/** Call this before a central workflow/webapp/local-browser job starts. */
function runCentralNotebookRuntimeHubPreflightV1(context) {
  context = context || {};
  const runId = 'NBRH_' + Utilities.formatDate(new Date(), Session.getScriptTimeZone() || 'Asia/Seoul', 'yyyyMMdd_HHmmss') + '_' + Utilities.getUuid().slice(0, 8);
  const readback = readNotebookRuntimeHubReadbackV1_();
  const evalResult = evaluateNotebookRuntimeHubReadbackV1_(readback);
  const support = evaluateWorkflowSupportStateV1_();
  const status = evalResult.pass && support.hardFailures.length === 0 ? 'PASS_PRECHECK' : 'NEEDS_LOCAL_REPAIR_OR_ROUTE_FIX';

  appendByHeaderCompat_(CNRH_MASTER_REGISTRY_ID, '80_DATA_RUNTIME_QA_LOG', {
    QA_ID: runId, RUN_ID: runId, APP_ID: 'P00_AGENT_CORE', FUNCTION_ID: 'runCentralNotebookRuntimeHubPreflightV1',
    INPUT_DATA_IDS: 'LOCAL_RUNTIME|03|24|36|56|60|61|76|77|83', OUTPUT_DATA_IDS: status,
    RESULT_ID: runId, STARTED_AT: new Date(), FINISHED_AT: new Date(), STATUS: status,
    READBACK_STATE: evalResult.pass ? 'PASS' : 'FAIL', QUALITY_SCORE: evalResult.score,
    ERROR_CLASS: evalResult.issues.concat(support.hardFailures).join('|'), RETRY_COUNT: 0,
    EVIDENCE_POINTER: JSON.stringify({readback: readback.meta, support: support.summary, context: context}).slice(0, 12000),
    NEXT_ACTION: status === 'PASS_PRECHECK' ? 'CONTINUE_WORKFLOW' : 'PRECHECK_LESSONS_THEN_LOCAL_SAFE_REPAIR_AND_SAME_FIXTURE_RETEST'
  });

  let repair = null;
  if (status !== 'PASS_PRECHECK') repair = requestNotebookRuntimeRepairV1(evalResult.issues.concat(support.hardFailures), context);
  return {runId: runId, status: status, readback: readback, evaluation: evalResult, support: support, repair: repair, version: CNRH_VERSION};
}

function readNotebookRuntimeHubReadbackV1_() {
  const root = DriveApp.getFolderById(CNRH_CENTRAL_FOLDER_ID);
  const rr = getOrNullFolder_(root, 'RUNTIME_READBACK');
  const hub = rr ? getOrNullFolder_(rr, 'NOTEBOOK_HUB') : null;
  const f = hub ? newestFileByName_(hub, 'NOTEBOOK_RUNTIME_HUB_LATEST.json') : null;
  if (!f) return {ok: false, data: null, meta: {status: 'READBACK_FILE_MISSING'}};
  try {
    const data = JSON.parse(f.getBlob().getDataAsString('UTF-8'));
    return {ok: true, data: data, meta: {fileId: f.getId(), fileUrl: f.getUrl(), updatedAt: f.getLastUpdated().toISOString(), status: data.status || ''}};
  } catch (e) {
    return {ok: false, data: null, meta: {fileId: f.getId(), fileUrl: f.getUrl(), status: 'READBACK_JSON_INVALID', error: String(e)}};
  }
}

function evaluateNotebookRuntimeHubReadbackV1_(r) {
  const issues = [];
  if (!r || !r.ok || !r.data) return {pass: false, score: 0, issues: ['NOTEBOOK_RUNTIME_READBACK_MISSING_OR_INVALID']};
  const d = r.data;
  const generated = new Date(d.generatedAt || 0);
  const ageMin = isNaN(generated.getTime()) ? 999999 : (Date.now() - generated.getTime()) / 60000;
  if (ageMin > 20) issues.push('NOTEBOOK_RUNTIME_READBACK_STALE_GT20M');
  if (!d.runtime || d.runtime.hostHealthy !== true) issues.push('LOCAL_HOST_UNHEALTHY');
  if (!d.driveWritebackOk) issues.push('DRIVE_WRITEBACK_NOT_CONFIRMED');
  if (!d.clasp || d.clasp.cli !== true) issues.push('CLASP_CLI_NOT_READY');
  if (!d.clasp || d.clasp.authReceiptPresent !== true) issues.push('CLASP_AUTH_RECEIPT_NOT_READY');
  if (!d.gcloud || d.gcloud.cli !== true) issues.push('GCLOUD_CLI_NOT_READY');
  if (d.gcloud && d.gcloud.activeAuth === true && d.gcloud.project && d.gcloud.project !== CNRH_PROJECT_ID) issues.push('GCLOUD_PROJECT_MISMATCH');
  (d.problems || []).forEach(function(x) { if (issues.indexOf(String(x)) < 0) issues.push(String(x)); });
  const score = Math.max(0, 100 - Math.min(100, issues.length * 12));
  return {pass: issues.length === 0, score: score, issues: issues, ageMinutes: Math.round(ageMin * 10) / 10};
}

/** Central support map: all front apps must have route+subscription; runtime-pending is not VERIFIED. */
function evaluateWorkflowSupportStateV1_() {
  const workflow = sheetRowsAsObjects_(CNRH_MASTER_REGISTRY_ID, '56_FRONTAPP_WORKFLOW_MAP');
  const subs = sheetRowsAsObjects_(CNRH_MASTER_REGISTRY_ID, '60_APP_DATA_SUBSCRIPTION');
  const contracts = sheetRowsAsObjects_(CNRH_MASTER_REGISTRY_ID, '61_BACKEND_FUNCTION_CONTRACT');
  const packs = sheetRowsAsObjects_(CNRH_MASTER_REGISTRY_ID, '76_ASSET_PACK_FACTORY');
  const hardFailures = [];
  if (!workflow.some(function(r) { return String(r.APP_ID || '') === 'APP_AGENT_CORE'; })) hardFailures.push('CENTRAL_WORKFLOW_MAP_MISSING');
  if (subs.length < 1) hardFailures.push('APP_DATA_SUBSCRIPTIONS_EMPTY');
  if (contracts.length < 1) hardFailures.push('BACKEND_FUNCTION_CONTRACTS_EMPTY');
  const needed = ['LANGUAGE','VOICE','PERSONA'];
  needed.forEach(function(k) {
    if (!packs.some(function(r) { return (String(r.PACK_CLASS || '') + '|' + String(r.SUBTYPE || '') + '|' + String(r.TAGS || '')).toUpperCase().indexOf(k) >= 0; })) hardFailures.push('PACK_MISSING_' + k);
  });
  return {
    hardFailures: hardFailures,
    summary: {workflowRows: workflow.length, subscriptionRows: subs.length, contractRows: contracts.length, assetPackRows: packs.length}
  };
}

/** Writes a safe repair request. Local watchdog/self-heal owns the actual Windows actions. */
function requestNotebookRuntimeRepairV1(issues, context) {
  issues = Array.isArray(issues) ? issues : [String(issues || '')];
  context = context || {};
  const root = DriveApp.getFolderById(CNRH_CENTRAL_FOLDER_ID);
  const rr = getOrCreateFolder_(root, 'RUNTIME_READBACK');
  const hub = getOrCreateFolder_(rr, 'NOTEBOOK_HUB');
  const req = {
    schema: 'CENTRAL_NOTEBOOK_RUNTIME_REPAIR_REQUEST_V1',
    requestId: 'NBRH_REPAIR_' + Utilities.getUuid(), requestedAt: new Date().toISOString(),
    issues: issues, context: context,
    precheck: 'HISTORY_LAST_GOOD_SUCCESS_FAILURE_FIRST',
    action: 'SAFE_LOCAL_SELF_HEAL_THEN_SAME_FIXTURE_RETEST',
    forbid: ['BLIND_RETRY','NEW_OAUTH_WITHOUT_EVIDENCE','NEW_CMD_WHEN_EXISTING_APPROVED_RUNTIME_EXISTS','NORMAL_CHROME_RESET','DELETE_OR_MOVE_ORIGINAL_MEDIA'],
    approvalBoundary: 'ASK_ONLY_LOGIN_2FA_NEW_SECRET_SCOPE_PAID_API_PUBLIC_HIGH_IMPACT_DESTRUCTIVE_PAYMENT'
  };
  upsertTextFile_(hub, 'NOTEBOOK_RUNTIME_REPAIR_REQUEST_LATEST.json', JSON.stringify(req, null, 2));
  return {status: 'REPAIR_REQUEST_WRITTEN', requestId: req.requestId};
}

/** Safe Google Developer/API discovery. This function never enables an API. */
function discoverGoogleApiRequirementV1(serviceName) {
  serviceName = String(serviceName || '').trim();
  if (!serviceName || serviceName.indexOf('.') < 0) throw new Error('SERVICE_NAME_REQUIRED');
  const props = PropertiesService.getScriptProperties();
  const projectNumber = props.getProperty('GOOGLE_CLOUD_PROJECT_NUMBER');
  if (!projectNumber) return {status: 'CONFIG_REQUIRED_PROJECT_NUMBER', serviceName: serviceName, projectId: CNRH_PROJECT_ID};
  try {
    const url = 'https://serviceusage.googleapis.com/v1/projects/' + encodeURIComponent(projectNumber) + '/services/' + encodeURIComponent(serviceName);
    const resp = UrlFetchApp.fetch(url, {method:'get', muteHttpExceptions:true, headers:{Authorization:'Bearer ' + ScriptApp.getOAuthToken()}});
    const code = resp.getResponseCode();
    const json = JSON.parse(resp.getContentText() || '{}');
    if (code >= 200 && code < 300) return {status: json.state === 'ENABLED' ? 'ENABLED' : 'DISABLED_OR_UNKNOWN', serviceName: serviceName, state: json.state || '', projectId: CNRH_PROJECT_ID};
    return {status: 'DISCOVERY_FAILED', serviceName: serviceName, http: code, error: JSON.stringify(json.error || json).slice(0, 2000)};
  } catch (e) {
    return {status: 'DISCOVERY_FAILED', serviceName: serviceName, error: String(e)};
  }
}

/** Enabling/new scopes/credentials are routed to the existing approval gate; no auto-enable here. */
function requestGoogleApiApprovalV1(serviceName, reason, workflowId) {
  const state = discoverGoogleApiRequirementV1(serviceName);
  if (state.status === 'ENABLED') return {status: 'ALREADY_ENABLED_REUSE', serviceName: serviceName};
  const root = DriveApp.getFolderById(CNRH_CENTRAL_FOLDER_ID);
  const folder = getOrCreateFolder_(root, 'API_APPROVAL_REQUESTS');
  const req = {
    schema:'GOOGLE_API_APPROVAL_REQUEST_V1', requestedAt:new Date().toISOString(), projectId:CNRH_PROJECT_ID,
    serviceName:String(serviceName), reason:String(reason || ''), workflowId:String(workflowId || ''), discovery:state,
    allowedReasons:['PROBLEM_BLOCKER','FINAL_TEMPLATE_QUALITY_GAP','LEARNING_COMPARISON_WHEN_CENTRAL_DATA_INSUFFICIENT'],
    postUseRule:'STORE_USEFUL_DELTA_AS_SEED_TEMPLATE_ASSET_AND_RETRY_API_FREE',
    approvalRequired:true
  };
  upsertTextFile_(folder, 'LATEST_' + serviceName.replace(/[^A-Za-z0-9_.-]/g,'_') + '.json', JSON.stringify(req,null,2));
  return {status:'APPROVAL_REQUEST_RECORDED_NOT_ENABLED', serviceName:serviceName, discovery:state};
}

function getOrNullFolder_(parent, name) { const it = parent.getFoldersByName(name); return it.hasNext() ? it.next() : null; }
function getOrCreateFolder_(parent, name) { return getOrNullFolder_(parent, name) || parent.createFolder(name); }
function newestFileByName_(folder, name) { const it=folder.getFilesByName(name); let best=null; while(it.hasNext()){const f=it.next(); if(!best || f.getLastUpdated()>best.getLastUpdated()) best=f;} return best; }
function upsertTextFile_(folder, name, text) { const f=newestFileByName_(folder,name); if(f){f.setContent(text); return f;} return folder.createFile(name,text,MimeType.PLAIN_TEXT); }

function sheetRowsAsObjects_(spreadsheetId, sheetName) {
  const sh = SpreadsheetApp.openById(spreadsheetId).getSheetByName(sheetName); if(!sh) return [];
  const v=sh.getDataRange().getValues(); if(v.length<2) return [];
  const h=v[0].map(String); return v.slice(1).filter(function(r){return r.some(function(x){return x!=='';});}).map(function(r){const o={};h.forEach(function(k,i){o[k]=r[i];});return o;});
}
function appendByHeaderCompat_(spreadsheetId, sheetName, payload) {
  if (typeof appendByHeaderSafe_ === 'function') { try { return appendByHeaderSafe_(sheetName,payload); } catch(e) {} }
  if (typeof appendByHeader_ === 'function') { try { return appendByHeader_(sheetName,payload); } catch(e) {} }
  const sh=SpreadsheetApp.openById(spreadsheetId).getSheetByName(sheetName); if(!sh) throw new Error('SHEET_NOT_FOUND:'+sheetName);
  const h=sh.getRange(1,1,1,sh.getLastColumn()).getValues()[0]; sh.appendRow(h.map(function(k){return Object.prototype.hasOwnProperty.call(payload,k)?payload[k]:'';})); return sh.getLastRow();
}
