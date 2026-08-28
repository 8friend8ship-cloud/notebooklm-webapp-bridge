const CDMH_VERSION = 'CENTRAL_DATA_MANAGEMENT_HUB_V1_1_20260828';
const CDMH_MASTER_ID = '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI';
const CDMH_HUB_ID = '1aBvDTPAFOjOI_CufzQsOJUFkU6bOhy6gBRy54VS1o-s';
const CDMH_HUB_URL = 'https://docs.google.com/spreadsheets/d/1aBvDTPAFOjOI_CufzQsOJUFkU6bOhy6gBRy54VS1o-s/edit';

function installCentralDataManagementHubTriggersV1() {
  const mine = ['runCentralDataManagementHubCycleV1'];
  ScriptApp.getProjectTriggers().forEach(function(t){
    if (mine.indexOf(t.getHandlerFunction()) >= 0) ScriptApp.deleteTrigger(t);
  });
  [6,14,22].forEach(function(h){
    ScriptApp.newTrigger('runCentralDataManagementHubCycleV1').timeBased().atHour(h).everyDays(1).create();
  });
  return {ok:true, handlers:['runCentralDataManagementHubCycleV1'], hoursKst:[6,14,22], state:'TRIGGERS_CREATED_RUNTIME_READBACK_REQUIRED', version:CDMH_VERSION};
}

function runCentralDataManagementHubCycleV1() {
  const started = new Date();
  const runId = 'CDMH_' + Utilities.formatDate(started, Session.getScriptTimeZone() || 'Asia/Seoul','yyyyMMdd_HHmmss') + '_' + Utilities.getUuid().slice(0,8);
  const notebook = typeof centralWorkflowStartGateV1 === 'function' ? centralWorkflowStartGateV1({source:'CENTRAL_DATA_HUB',runId:runId}) : {status:'RUNTIME_GATE_FUNCTION_MISSING'};
  const fileSync = syncMasterFileCatalogToDataHubV1_();
  const publish = syncMasterPublishLedgerToDataHubV1_();
  const gates = evaluateAndQueueDataHubReadinessV1_();
  const dispatch = dispatchForceQueueToMasterExecutionV1_(runId);
  const approvals = runCentralApprovalInboxScanV1();
  const modelQa = runConditionalDataGapAuditV1_(runId, gates);
  const notebookPass = /PASS/.test(String(notebook.status || '')) || String(notebook.status || '') === 'PASS_PRECHECK';
  const status = notebookPass ? (gates.blocked === 0 ? 'PASS_DATA_HUB' : 'PASS_WITH_FORCE_QUEUE') : 'DEGRADED_NOTEBOOK_RUNTIME';
  appendHubRowByHeader_('06_WORKFLOW_HEALTH', {
    CHECK_ID:runId, WORKFLOW_ID:'CENTRAL_DATA_MANAGEMENT_HUB', FRONT_APP:'ALL', NOTEBOOK_RUNTIME:String(notebook.status||''),
    APPS_SCRIPT:'CODE_STAGED_RUNTIME', CLASP:'RUNTIME_READBACK_REQUIRED', CHROME_EXTENSION:'RUNTIME_READBACK_REQUIRED', DRIVE_SYNC:fileSync.status,
    SEED_T1:gates.blocked===0?'READY':'FORCE_QUEUE_ACTIVE', PUBLISH_ROUTE:publish.status, OVERALL_STATUS:status,
    LAST_CHECK:new Date(), ERROR_CODE:gates.blockers.slice(0,20).concat(dispatch.blockedRoutes||[]).join('|'), LAST_GOOD:'MASTER_REGISTRY+81_ALL_FILE_CATALOG',
    AUTO_FIX:'ANALYZE→SEED→T1→URL_POINTER; route only to ACTIVE canonical functions; API only for blocker/quality/learning gap', USER_APPROVAL:approvals.userApprovalCount>0?'Y':'N'
  });
  return {runId:runId,status:status,notebook:notebook,fileSync:fileSync,publish:publish,gates:gates,dispatch:dispatch,approvals:approvals,modelQa:modelQa,version:CDMH_VERSION};
}

function syncMasterFileCatalogToDataHubV1_() {
  const src = sheetObjects_(CDMH_MASTER_ID,'81_ALL_FILE_CATALOG');
  const seeds = sheetObjects_(CDMH_MASTER_ID,'35_INTERNAL_SEED_REGISTRY');
  const assets = sheetObjects_(CDMH_MASTER_ID,'48_SEARCHABLE_ASSET_INDEX');
  const pubs = sheetObjects_(CDMH_MASTER_ID,'49_PLATFORM_DATA_LEDGER');
  const assetByFile = {};
  assets.forEach(function(a){ if(a.DRIVE_FILE_ID) assetByFile[String(a.DRIVE_FILE_ID)] = a; });
  const seedBySource = {};
  seeds.forEach(function(s){ String(s.SOURCE_IDS||'').split('|').forEach(function(x){ if(x) seedBySource[x]=s; }); });
  const pubBySource = {};
  pubs.forEach(function(p){ String(p.SOURCE_DRIVE_IDS||'').split('|').forEach(function(x){ if(x) pubBySource[x]=p; }); });
  const rows = src.map(function(r){
    const fileId = String(r.DRIVE_FILE_ID||'');
    const a = assetByFile[fileId] || {};
    const seed = seedBySource[fileId] || seedBySource[String(r.DATA_ID||'')] || {};
    const pub = pubBySource[fileId] || pubBySource[String(seed.SEED_ID||'')] || {};
    const analyzed = /REVIEWED|VERIFIED|PASS|ANALYZED/i.test(String(r.REVIEW_STATE||'')) || /PASS|VERIFIED/i.test(String(a.VERIFIED_STATUS||''));
    const rights = String(a.RIGHTS_USAGE||r.RIGHTS_CLASS||'');
    const hash = String(a.CONTENT_HASH||r.CONTENT_HASH||'');
    const seedId = String(a.SEED_ID||seed.SEED_ID||'');
    const seedReady = !!seedId && !/WAIT|PENDING|REVIEW_REQUIRED/i.test(String(seed.STATUS||''));
    const t1Ready = analyzed && !!rights && !!hash && (seedReady || /T1/i.test(String(r.USAGE_MODES||'')));
    const platformUrl = String(pub.PLATFORM_URL||'');
    return [
      String(r.DATA_ID||r.FILE_RECORD_ID||('DATA_'+fileId)), String(r.FILE_CLASS||'DRIVE_FILE'), String(r.TITLE||''), String(r.MIME_TYPE||''), fileId,
      String(r.DRIVE_URL||a.DRIVE_URL||a.SOURCE_URL||''), String(r.BUSINESS_ROLE||r.PARENT_OR_GROUP||''), String(r.APP_SCOPE||''), String(r.FILE_CLASS||a.ASSET_TYPE||''),
      String(a.PERSONA_SNAPSHOT_ID||''), '', String(a.SUMMARY_MEMO||r.NOTES||r.BUSINESS_ROLE||''), [r.USAGE_MODES,r.BUSINESS_ROLE,r.APP_SCOPE,a.BARCODE_TAGS,a.KEYWORDS].filter(Boolean).join('|'),
      analyzed?'ANALYZED':'CHECK_REQUIRED', seedId, seedReady?'SEED_READY':(seedId?'SEED_REVIEW_REQUIRED':'SEED_MISSING'), t1Ready?'READY_T1':'NOT_READY_FORCE_QUEUE',
      String(pub.PLATFORM_ID||''), platformUrl, '', rights, hash, String(a.UPDATED_AT||r.UPDATED_AT||''),
      t1Ready ? (platformUrl?'REUSE_FRONT_URL':'CREATE_OR_REGISTER_REAL_URL_POINTER') : 'FORCE_ANALYZE_SEED_T1_SAFE'
    ];
  });
  writeHubTable_('01_DATA_CATALOG', rows);
  return {status:'PASS_SYNCED_MASTER_81', rows:rows.length};
}

function syncMasterPublishLedgerToDataHubV1_() {
  const pubs = sheetObjects_(CDMH_MASTER_ID,'49_PLATFORM_DATA_LEDGER');
  const rows = pubs.map(function(p){
    const url=String(p.PLATFORM_URL||'');
    return [String(p.PUBLISH_ID||p.PLATFORM_RECORD_ID||''),String(p.SOURCE_DRIVE_IDS||''),String(p.APP_ID||''),String(p.PLATFORM_ID||''),'', '', url, String(p.PLATFORM_CONTENT_ID||''), url,
      url?'URL_VERIFIED':'URL_PENDING', url?'INDEX_CHECK_REQUIRED':'NOT_INDEXED', String(p.PUBLISHED_AT||''), String(p.METRIC_LAST_SYNC_AT||''), String(p.SEED_ID||''),'',String(p.NOTES||'')];
  });
  const keep = [['PUB_PINTEREST_PENDING','','ALL','PINTEREST','ALL','','','','','EXTERNAL_REVIEW_PENDING','NOT_INDEXED','','','','','Pinterest API app review pending; real URL required'],['PUB_BLOGGER_ROUTE','','ALL','BLOGGER','TEXT_IMAGE','','','','','ROUTE_READY_URL_PENDING','NOT_CHECKED','','','','','Official API first; actual post URL required']];
  writeHubTable_('04_PUBLISH_URL_LEDGER', keep.concat(rows));
  return {status:'PASS_PUBLISH_LEDGER_SYNC', rows:rows.length};
}

function evaluateAndQueueDataHubReadinessV1_() {
  const catalog = sheetObjects_(CDMH_HUB_ID,'01_DATA_CATALOG');
  const blocked = catalog.filter(function(r){ return String(r.T1_READINESS||'') !== 'READY_T1'; });
  const qRows = blocked.map(function(r,i){
    const missing=[];
    if(String(r.ANALYSIS_STATUS||'')!=='ANALYZED') missing.push('ANALYSIS');
    if(!r.SEED_ID) missing.push('SEED');
    if(!r.RIGHTS) missing.push('RIGHTS');
    if(!r.CONTENT_HASH) missing.push('HASH');
    if(!r.DRIVE_URL) missing.push('URL_POINTER');
    return ['FORCE_'+(r.DATA_ID||i),String(r.DATA_ID||''),'T1_NOT_READY','SCAN',missing.join('|'),'ANALYZE_STORED_DATA→SEED→T1→URL_POINTER','BLOCKER_OR_FINAL_QUALITY_OR_LEARNING_COMPARE','LOGIN_2FA_NEW_SECRET_SCOPE_PAID_PUBLIC_DESTRUCTIVE_PAYMENT','AUTO','AUTO','URL_READY_ONLY','READY',0,'','PROCESS_SAFE_GAPS'];
  });
  writeHubTable_('10_FORCE_PROCESS_QUEUE', qRows.length?qRows:[['FORCE_NONE','','NO_BLOCKERS','DONE','','NONE','','','','','','EMPTY',0,'','','']]);
  return {blocked:blocked.length,total:catalog.length,blockers:blocked.slice(0,50).map(function(r){return String(r.DATA_ID||'');})};
}

/**
 * Force-processing means canonical queue dispatch, not blind execution.
 * Only ACTIVE functions already registered in 79_FUNCTION_DATA_USAGE_MAP are routable.
 * Public publishing, OAuth, paid APIs, new secrets/scopes, deletion and payments remain gated.
 */
function dispatchForceQueueToMasterExecutionV1_(runId) {
  const forceRows = sheetObjects_(CDMH_HUB_ID,'10_FORCE_PROCESS_QUEUE').filter(function(r){
    return String(r.STATUS||'') === 'READY' && String(r.DATA_ID||'') && String(r.DATA_ID||'') !== 'FORCE_NONE';
  });
  const fileCatalog = sheetObjects_(CDMH_MASTER_ID,'81_ALL_FILE_CATALOG');
  const functionMap = sheetObjects_(CDMH_MASTER_ID,'79_FUNCTION_DATA_USAGE_MAP');
  const existingQueue = sheetObjects_(CDMH_MASTER_ID,'07_EXECUTION_QUEUE');
  const fileByData = {};
  fileCatalog.forEach(function(f){ if(f.DATA_ID) fileByData[String(f.DATA_ID)] = f; });
  const activeFunctions = functionMap.filter(function(m){ return /^ACTIVE/i.test(String(m.ACTIVE_STATE||'')); });
  const existingKeys = {};
  existingQueue.forEach(function(q){
    const key = String(q.TASK_TYPE||'')+'|'+String(q.TARGET_ID||'');
    if(!/COMPLETED|VERIFIED|CANCELLED|REJECTED/i.test(String(q.STATUS||''))) existingKeys[key]=true;
  });

  let queued=0, skippedDuplicate=0;
  const blockedRoutes=[];
  forceRows.forEach(function(fr){
    const dataId=String(fr.DATA_ID||'');
    const key='DATA_ANALYZE_SEED_T1|'+dataId;
    if(existingKeys[key]) { skippedDuplicate++; return; }
    const file=fileByData[dataId]||{};
    const linkedFunctions=String(file.LINKED_FUNCTION_IDS||'').split('|').filter(Boolean);
    const linkedTriggers=String(file.LINKED_TRIGGER_IDS||'').split('|').filter(Boolean);
    let route=null;
    for(let i=0;i<activeFunctions.length && !route;i++){
      const m=activeFunctions[i];
      const fnId=String(m.FUNCTION_ID||'');
      const fnName=String(m.FUNCTION_NAME||'');
      const inputs=String(m.INPUT_DATA_IDS||'');
      const trigger=String(m.TRIGGER_ID||'');
      if(linkedFunctions.indexOf(fnId)>=0 || linkedFunctions.indexOf(fnName)>=0 || inputs.split('|').indexOf(dataId)>=0 || linkedTriggers.indexOf(trigger)>=0) route=m;
    }
    const routeReady=!!route;
    if(!routeReady) blockedRoutes.push(dataId);
    const taskId='CDMH_FORCE_'+safeId_(dataId).slice(0,72);
    appendMasterByHeader_('07_EXECUTION_QUEUE', {
      TASK_ID:taskId,
      STAGE_NO:1,
      TASK_TYPE:'DATA_ANALYZE_SEED_T1',
      TARGET_ID:dataId,
      ACTION:'ANALYZE_STORED_DATA→SEED→T1→URL_POINTER; PUBLIC_PUBLISH_SEPARATE_GATE',
      PRIORITY:String(fr.REASON||'').indexOf('RIGHTS')>=0?'P0':'P1',
      APPROVAL_STATUS:'POLICY_AUTO_APPROVED_SAFE_DATA_PROCESSING',
      EXECUTION_METHOD:routeReady?('FUNCTION:'+String(route.FUNCTION_NAME||'')+'|TRIGGER:'+String(route.TRIGGER_ID||'')):'CENTRAL_ROUTE_RESOLUTION_REQUIRED',
      STATUS:routeReady?'READY':'BLOCKED_ROUTE',
      RETRY_COUNT:0,
      CREATED_AT:new Date(),
      UPDATED_AT:new Date(),
      NOTES:'Source='+String(file.TITLE||'')+'; missing='+String(fr.MISSING||'')+'; run='+runId+'; no blind invocation; API conditional only after stored-data gap.',
      OWNER:'CENTRAL_AGENT',
      FIRST_REQUESTED_AT:new Date(),
      LAST_REQUESTED_AT:new Date(),
      REQUEST_COUNT:1,
      BLOCKED_TASK_ID:'',
      COMPLETION_EVIDENCE:'RUNTIME_RESULT+SEED_ID+T1_ID+URL_POINTER+READBACK_X2_REQUIRED',
      APPROVAL_TYPE:'NONE_UNLESS_LOGIN_2FA_NEW_SECRET_SCOPE_PAID_PUBLIC_DESTRUCTIVE_PAYMENT'
    });
    existingKeys[key]=true;
    queued++;
  });
  return {status:blockedRoutes.length?'QUEUED_WITH_ROUTE_GAPS':'QUEUED_CANONICAL',queued:queued,skippedDuplicate:skippedDuplicate,blockedRoutes:blockedRoutes};
}

function runConditionalDataGapAuditV1_(runId, gates) {
  if (!gates || gates.blocked < 1) return {status:'SKIPPED_NO_GAP'};
  if (typeof runDualModelQaCompareV1 !== 'function') return {status:'SKIPPED_DUAL_QA_FUNCTION_MISSING'};
  try {
    return runDualModelQaCompareV1({runId:runId,goal:'Classify central data-management blockers only. Do not invent runtime evidence. Recommend reusable Seed/Template deltas.',gapCount:gates.blocked,blockedIds:gates.blockers.slice(0,20)});
  } catch(e) { return {status:'DUAL_QA_ERROR',error:String(e)}; }
}

/**
 * Approval inbox is an evidence/readback surface, not a reason to expand OAuth scope.
 * Gmail is intentionally NOT called from this bound-runtime file. Gmail/connector scans
 * may update 08_APPROVAL_INBOX through an already-approved external route. The DataHub
 * only consumes that evidence and preserves the user's no-new-OAuth/no-repeat-approval gate.
 */
function runCentralApprovalInboxScanV1() {
  const inbox = sheetObjects_(CDMH_HUB_ID,'08_APPROVAL_INBOX');
  const actionable = inbox.filter(function(r){ return String(r.USER_ACTION_REQUIRED||'').toUpperCase() === 'Y'; });
  return {
    status: inbox.length ? 'PASS_EXISTING_APPROVAL_INBOX_READBACK' : 'PASS_NO_APPROVAL_EVIDENCE',
    rows: inbox.length,
    userApprovalCount: actionable.length,
    source: 'EXISTING_DRIVE_EVIDENCE_ONLY',
    scopeExpansion: false,
    error: ''
  };
}

function writeHubTable_(sheetName, rows) {
  const sh=SpreadsheetApp.openById(CDMH_HUB_ID).getSheetByName(sheetName); if(!sh) throw new Error('HUB_SHEET_NOT_FOUND:'+sheetName);
  const cols=sh.getLastColumn(); if(sh.getMaxRows()>1) sh.getRange(2,1,sh.getMaxRows()-1,cols).clearContent();
  if(!rows || !rows.length) return;
  const normalized=rows.map(function(r){const x=r.slice(0,cols);while(x.length<cols)x.push('');return x;});
  if(sh.getMaxRows()<normalized.length+1) sh.insertRowsAfter(sh.getMaxRows(),normalized.length+1-sh.getMaxRows());
  sh.getRange(2,1,normalized.length,cols).setValues(normalized);
}

function appendHubRowByHeader_(sheetName,payload){
  const sh=SpreadsheetApp.openById(CDMH_HUB_ID).getSheetByName(sheetName); if(!sh) throw new Error('HUB_SHEET_NOT_FOUND:'+sheetName);
  const h=sh.getRange(1,1,1,sh.getLastColumn()).getValues()[0]; sh.appendRow(h.map(function(k){return Object.prototype.hasOwnProperty.call(payload,k)?payload[k]:'';}));
}
function appendMasterByHeader_(sheetName,payload){
  const sh=SpreadsheetApp.openById(CDMH_MASTER_ID).getSheetByName(sheetName); if(!sh) throw new Error('MASTER_SHEET_NOT_FOUND:'+sheetName);
  const h=sh.getRange(1,1,1,sh.getLastColumn()).getValues()[0]; sh.appendRow(h.map(function(k){return Object.prototype.hasOwnProperty.call(payload,k)?payload[k]:'';}));
}
function sheetObjects_(spreadsheetId,sheetName){
  const sh=SpreadsheetApp.openById(spreadsheetId).getSheetByName(sheetName); if(!sh) return [];
  const lr=sh.getLastRow(), lc=sh.getLastColumn(); if(lr<2||lc<1) return [];
  const v=sh.getRange(1,1,lr,lc).getValues(), h=v[0].map(String);
  return v.slice(1).filter(function(r){return r.some(function(x){return x!=='';});}).map(function(r){const o={};h.forEach(function(k,i){o[k]=r[i];});return o;});
}
function safeId_(s){return String(s||'').replace(/[^A-Za-z0-9_-]+/g,'_').replace(/^_+|_+$/g,'') || Utilities.getUuid().slice(0,12);}
