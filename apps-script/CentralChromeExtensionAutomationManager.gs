const CCEM_VERSION = 'CENTRAL_CHROME_EXTENSION_AUTOMATION_MANAGER_V1_20260828';
const CCEM_MANAGER_ID = '147pycCA4XT2u4TxFYZOaR9na0RtpplbNmRJmmN2o-3w';
const CCEM_MASTER_ID = '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI';
const CCEM_DATA_HUB_ID = '1aBvDTPAFOjOI_CufzQsOJUFkU6bOhy6gBRy54VS1o-s';

/**
 * Central Chrome-extension / Drive asset / Seed / Template / URL routing coordinator.
 * This file intentionally does not expand OAuth scopes, enable paid APIs, publish publicly,
 * delete extensions, or restart the user's normal Chrome. It coordinates existing approved
 * runtime lanes and writes evidence/queues for the already-registered workers.
 */
function installCentralChromeExtensionAutomationTriggersV1() {
  const handlers = [
    'runCentralChromeExtensionHealthCycleV1',
    'runCentralAssetIngestCycleV1',
    'runCentralSeedPromotionCycleV1',
    'runCentralTemplatePromotionCycleV1',
    'runCentralChromeDataOrchestraAuditV1'
  ];
  ScriptApp.getProjectTriggers().forEach(function(t) {
    if (handlers.indexOf(t.getHandlerFunction()) >= 0) ScriptApp.deleteTrigger(t);
  });

  ScriptApp.newTrigger('runCentralChromeExtensionHealthCycleV1').timeBased().everyMinutes(15).create();
  ScriptApp.newTrigger('runCentralAssetIngestCycleV1').timeBased().everyMinutes(30).create();
  ScriptApp.newTrigger('runCentralSeedPromotionCycleV1').timeBased().everyHours(1).create();
  ScriptApp.newTrigger('runCentralTemplatePromotionCycleV1').timeBased().everyHours(2).create();
  [6, 14, 22].forEach(function(hour) {
    ScriptApp.newTrigger('runCentralChromeDataOrchestraAuditV1').timeBased().atHour(hour).everyDays(1).create();
  });

  const result = {
    ok: true,
    version: CCEM_VERSION,
    handlers: handlers,
    state: 'TRIGGERS_CREATED_RUNTIME_ID_READBACK_REQUIRED',
    approvalExpansion: false
  };
  ccemAppendHistory_('TRIGGER_INSTALL', result, 'READBACK_TRIGGER_IDS_AND_RUN_SAME_FIXTURE_X2');
  return result;
}

function runCentralChromeExtensionHealthCycleV1() {
  const started = new Date();
  const runId = 'CCEM_HEALTH_' + Utilities.formatDate(started, Session.getScriptTimeZone() || 'Asia/Seoul', 'yyyyMMdd_HHmmss');
  const bridgeRows = ccemSheetObjects_(CCEM_MASTER_ID, '24_CHROME_BRIDGE_REGISTRY');
  const checklistRows = ccemSheetObjects_(CCEM_MASTER_ID, '88_CHROME_EXTENSION_CONTROL_CHECKLIST');
  const managerRows = ccemSheetObjects_(CCEM_MANAGER_ID, '01_EXTENSION_REGISTRY');
  const current = {};

  bridgeRows.forEach(function(r) {
    const id = String(r.EXTENSION_ID || '').trim();
    if (!id || id === 'N/A' || id === 'UNKNOWN' || id === 'PER_EXTENSION') return;
    current[id] = current[id] || {};
    current[id].bridgeName = String(r.BRIDGE_NAME || '');
    current[id].runtimeState = String(r.RUNTIME_STATE || '');
    current[id].lastSuccess = String(r.LAST_SUCCESS_AT || '');
    current[id].lastError = String(r.LAST_ERROR || r.BLOCKER || '');
    current[id].versionTruth = String(r.MANIFEST_VERSION || '');
  });

  checklistRows.forEach(function(r) {
    const id = String(r.EXTENSION_ID || '').trim();
    if (!id || id === 'N/A' || id === 'REGISTRY' || id === 'ACTUAL_32CHAR_ID') return;
    current[id] = current[id] || {};
    current[id].checkStatus = String(r.STATUS || '');
    current[id].lastChecked = String(r.LAST_CHECKED_AT || '');
    current[id].notes = String(r.NOTES || '');
  });

  let known = 0;
  let blocked = 0;
  managerRows.forEach(function(m) {
    const id = String(m.EXTENSION_ID || '').trim();
    if (!id) return;
    known++;
    const actual = current[id] || {};
    const state = actual.runtimeState || actual.checkStatus || String(m.RUNTIME_STATE || 'NO_LIVE_READBACK');
    if (/HOLD|PENDING|STALE|FAIL|ERROR|BLOCK/i.test(state)) blocked++;
    ccemAppendManagerByHeader_('11_RUNTIME_HEALTH', {
      COMPONENT: String(m.NAME || id),
      CURRENT_TRUTH: [actual.versionTruth, state, actual.lastError].filter(Boolean).join(' | '),
      TARGET: String(m.VERSION_TRUTH || ''),
      HEALTH: /FAIL|ERROR/.test(state) ? 'ERROR' : (/HOLD|PENDING|STALE|BLOCK/.test(state) ? 'PENDING_OR_HOLD' : 'CHECK_OK_OR_UNKNOWN'),
      LAST_EVIDENCE: actual.lastChecked || actual.lastSuccess || Utilities.formatDate(started, 'Asia/Seoul', 'yyyy-MM-dd HH:mm:ss KST'),
      NEXT_GATE: /FAIL|ERROR|HOLD|PENDING|STALE|BLOCK/.test(state) ? 'HISTORY_FIRST→FAILURE_LAYER→MINIMUM_FIX→SAME_FIXTURE_RETEST' : 'KEEP_TRAFFIC_SCHEDULE_AND_RUNTIME_READBACK'
    });
  });

  const result = {
    runId: runId,
    knownExtensions: known,
    blockedOrPending: blocked,
    state: blocked ? 'HEALTH_WITH_PENDING_OR_HOLD' : 'HEALTH_NO_KNOWN_BLOCKER',
    source: '24_CHROME_BRIDGE_REGISTRY+88_CHROME_EXTENSION_CONTROL_CHECKLIST',
    runtimeEvidenceRequired: true
  };
  ccemAppendHistory_('CHROME_HEALTH', result, blocked ? 'PROCESS_EXISTING_FAILURES_BY_PRIORITY' : 'KEEP_SCHEDULE');
  return result;
}

function runCentralAssetIngestCycleV1() {
  const started = new Date();
  const runId = 'CCEM_ASSET_' + Utilities.formatDate(started, Session.getScriptTimeZone() || 'Asia/Seoul', 'yyyyMMdd_HHmmss');
  const files = ccemSheetObjects_(CCEM_MASTER_ID, '81_ALL_FILE_CATALOG');
  const queue = ccemSheetObjects_(CCEM_MASTER_ID, '07_EXECUTION_QUEUE');
  const active = {};
  queue.forEach(function(q) {
    const key = String(q.TASK_TYPE || '') + '|' + String(q.TARGET_ID || '');
    if (!/COMPLETED|VERIFIED|CANCELLED|REJECTED/i.test(String(q.STATUS || ''))) active[key] = true;
  });

  let queued = 0;
  let skipped = 0;
  let ignored = 0;
  const recent = files.slice(Math.max(0, files.length - 500));
  recent.forEach(function(file) {
    const dataId = String(file.DATA_ID || file.FILE_RECORD_ID || '').trim();
    const fileId = String(file.DRIVE_FILE_ID || '').trim();
    if (!dataId && !fileId) return;
    const targetId = dataId || fileId;
    const assetType = ccemClassifyAssetType_(file);
    if (!assetType) { ignored++; return; }
    const key = 'ASSET_MULTIMODAL_ANALYSIS|' + targetId;
    if (active[key]) { skipped++; return; }

    const plan = analyzeNewAssetV1({
      runId: runId,
      targetId: targetId,
      dataId: dataId,
      driveFileId: fileId,
      driveUrl: String(file.DRIVE_URL || ''),
      title: String(file.TITLE || ''),
      mimeType: String(file.MIME_TYPE || ''),
      assetType: assetType,
      appScope: String(file.APP_SCOPE || ''),
      rights: String(file.RIGHTS_CLASS || ''),
      enqueue: true
    });
    if (plan && plan.queued) {
      queued++;
      active[key] = true;
    }
  });

  const result = {
    runId: runId,
    scanned: recent.length,
    queued: queued,
    skippedDuplicate: skipped,
    ignoredUnsupported: ignored,
    state: 'ASSET_INGEST_DISPATCHED_SAFE_QUEUE',
    note: 'Binary analysis is delegated to registered workflow/runtime; Apps Script only routes and deduplicates.'
  };
  ccemAppendHistory_('ASSET_INGEST', result, queued ? 'WAIT_RESULT_READBACK_THEN_SEED_EVALUATION' : 'NO_NEW_QUEUE');
  return result;
}

function analyzeNewAssetV1(asset) {
  asset = asset || {};
  const type = String(asset.assetType || ccemClassifyAssetType_(asset)).toUpperCase();
  const lanes = {
    VIDEO: ['VISUAL','AUDIO','VOICE','MOTION','LANGUAGE','PERSONA','ASSET','SCRIPT','HOOK','CAMERA','CAPTION','STYLE','QUALITY','RIGHTS','FRONT_FIT'],
    AUDIO: ['VOICE','LANGUAGE','ROLE','TIMING','EMOTION','PERSONA_FIT','RIGHTS'],
    IMAGE: ['OBJECT','STYLE','COMPOSITION','PERSONA','SPACE_MATERIAL','RIGHTS','FRONT_FIT'],
    TEXT: ['TOPIC','FACT','STRUCTURE','STYLE','KEYWORDS','APP_FIT','TEMPLATE_PATTERN','SOURCE_TRACEABILITY'],
    DOCUMENT: ['TOPIC','FACT','STRUCTURE','STYLE','KEYWORDS','APP_FIT','TEMPLATE_PATTERN','SOURCE_TRACEABILITY'],
    SKETCHUP: ['BOM','SCENE','MATERIAL','PREVIEW','INTERIOR_FRONT_FIT','RIGHTS']
  };
  const analysisLanes = lanes[type] || [];
  if (!analysisLanes.length) return {queued:false, reason:'UNSUPPORTED_ASSET_TYPE', assetType:type};

  const targetId = String(asset.targetId || asset.dataId || asset.driveFileId || ('ASSET_' + Utilities.getUuid())).trim();
  const action = [
    'ANALYZE_' + type,
    'LANES=' + analysisLanes.join(','),
    'OUTPUT=QUEENS_EVIDENCE→SEED_CANDIDATE→FRONT_CAPABILITY_CHECK',
    'NO_INVENTED_RUNTIME_EVIDENCE',
    'RIGHTS_AND_SOURCE_TRACEABILITY_REQUIRED'
  ].join('; ');

  if (asset.enqueue !== false) {
    ccemAppendMasterByHeader_('07_EXECUTION_QUEUE', {
      TASK_ID: 'CCEM_ASSET_' + ccemSafeId_(targetId).slice(0, 80),
      STAGE_NO: 1,
      TASK_TYPE: 'ASSET_MULTIMODAL_ANALYSIS',
      TARGET_ID: targetId,
      ACTION: action,
      PRIORITY: type === 'VIDEO' ? 'P0' : 'P1',
      APPROVAL_STATUS: 'POLICY_AUTO_APPROVED_SAFE_INTERNAL_ANALYSIS',
      EXECUTION_METHOD: 'ORCHESTRA_WORKFLOW_MAP→REGISTERED_EXTENSION_OR_BACKEND',
      STATUS: 'READY',
      RETRY_COUNT: 0,
      CREATED_AT: new Date(),
      UPDATED_AT: new Date(),
      NOTES: 'driveFileId=' + String(asset.driveFileId || '') + ';driveUrl=' + String(asset.driveUrl || '') + ';title=' + String(asset.title || '') + ';mime=' + String(asset.mimeType || '') + ';appScope=' + String(asset.appScope || '') + ';rights=' + String(asset.rights || '') + ';run=' + String(asset.runId || ''),
      OWNER: 'CENTRAL_AGENT',
      FIRST_REQUESTED_AT: new Date(),
      LAST_REQUESTED_AT: new Date(),
      REQUEST_COUNT: 1,
      BLOCKED_TASK_ID: '',
      COMPLETION_EVIDENCE: 'ANALYSIS_RESULT_ID+DRIVE_POINTER+QUEENS_ID+SEED_DECISION+FRONT_FIT+READBACK',
      APPROVAL_TYPE: 'NONE_UNLESS_NEW_OAUTH_SCOPE_SECRET_PAID_PUBLIC_DESTRUCTIVE_PAYMENT'
    });
  }

  return {
    queued: asset.enqueue !== false,
    targetId: targetId,
    assetType: type,
    lanes: analysisLanes,
    resultContract: 'QUEENS_EVIDENCE→SEED_CANDIDATE→TEMPLATE_IF_X2→FRONT_FIT'
  };
}

function dispatchChromeWorkflowTaskV1(task) {
  task = task || {};
  const workflowId = String(task.workflowId || '');
  const service = String(task.service || ccemServiceFromWorkflow_(workflowId)).toUpperCase();
  const extension = ccemFindExtensionForService_(service);
  if (!extension) return {ok:false, state:'NO_REGISTERED_EXTENSION_ROUTE', service:service};

  const lockKey = ccemTrafficLockForService_(service);
  const estimate = Number(task.expectedDurationSec || extension.EXPECTED_DURATION_SEC || 120);
  const minGap = Number(extension.MIN_GAP_SEC || 30);
  const slot = ccemAcquireTrafficSlot_(lockKey, estimate, minGap);
  if (!slot.ok) {
    return {ok:false, state:'QUEUE_WAIT_TRAFFIC', service:service, extensionId:String(extension.EXTENSION_ID || ''), lockKey:lockKey, nextAllowedAt:slot.nextAllowedAt};
  }

  const targetId = String(task.targetId || task.taskId || Utilities.getUuid());
  const queueTaskId = String(task.taskId || ('CCEM_CHROME_' + ccemSafeId_(service + '_' + targetId).slice(0,80)));
  if (task.enqueue !== false) {
    ccemAppendMasterByHeader_('07_EXECUTION_QUEUE', {
      TASK_ID: queueTaskId,
      STAGE_NO: 1,
      TASK_TYPE: 'CHROME_WORKFLOW_TASK',
      TARGET_ID: targetId,
      ACTION: String(task.action || workflowId || service),
      PRIORITY: String(task.priority || 'P1'),
      APPROVAL_STATUS: 'POLICY_APPROVED_EXISTING_SCOPE',
      EXECUTION_METHOD: 'BRIDGE_ID=' + String(extension.EXTENSION_ID || '') + '|SERVICE=' + service + '|LOCK=' + lockKey,
      STATUS: 'READY',
      RETRY_COUNT: 0,
      CREATED_AT: new Date(),
      UPDATED_AT: new Date(),
      NOTES: 'workflowId=' + workflowId + ';expectedDurationSec=' + estimate + ';resultRoute=' + String(extension.DRIVE_RESULT_MODE || '') + ';history-first required',
      OWNER: 'CENTRAL_AGENT',
      FIRST_REQUESTED_AT: new Date(),
      LAST_REQUESTED_AT: new Date(),
      REQUEST_COUNT: 1,
      BLOCKED_TASK_ID: '',
      COMPLETION_EVIDENCE: 'CLAIMED→STARTED→RESULT_SAVED→DRIVE_READBACK→SAME_FIXTURE_X2',
      APPROVAL_TYPE: 'NEW_OAUTH_SCOPE_SECRET_PAID_PUBLIC_DESTRUCTIVE_PAYMENT_ONLY'
    });
  }

  ccemAppendHistory_('CHROME_DISPATCH', {
    taskId: queueTaskId,
    workflowId: workflowId,
    service: service,
    extensionId: String(extension.EXTENSION_ID || ''),
    lockKey: lockKey,
    estimateSec: estimate,
    nextAllowedAt: slot.nextAllowedAt
  }, 'WAIT_RESULT_OR_RELEASE_SLOT');

  return {ok:true, state:'DISPATCH_READY', taskId:queueTaskId, service:service, extensionId:String(extension.EXTENSION_ID || ''), lockKey:lockKey, nextAllowedAt:slot.nextAllowedAt};
}

function recordChromeWorkflowResultV1(result) {
  result = result || {};
  const lockKey = String(result.lockKey || ccemTrafficLockForService_(String(result.service || '')));
  const durationSec = Math.max(0, Number(result.durationSec || 0));
  ccemReleaseTrafficSlot_(lockKey, durationSec, Number(result.minGapSec || 30));

  ccemAppendManagerByHeader_('11_RUNTIME_HEALTH', {
    COMPONENT: String(result.service || result.extensionName || result.extensionId || 'CHROME_WORKFLOW'),
    CURRENT_TRUTH: String(result.status || '') + ' | task=' + String(result.taskId || '') + ' | result=' + String(result.resultId || ''),
    TARGET: String(result.expected || ''),
    HEALTH: /PASS|DONE|VERIFIED/i.test(String(result.status || '')) ? 'PASS' : 'FAIL_OR_PENDING',
    LAST_EVIDENCE: new Date(),
    NEXT_GATE: /PASS|DONE|VERIFIED/i.test(String(result.status || '')) ? 'DRIVE_READBACK→SEED/TEMPLATE_ROUTING' : 'ERROR_LAYER→MINIMUM_FIX→SAME_FIXTURE_RETEST'
  });

  ccemAppendHistory_('CHROME_RESULT', result, /PASS|DONE|VERIFIED/i.test(String(result.status || '')) ? 'ROUTE_RESULT_TO_LEARNING' : 'DIAGNOSTIC_HOLD_IF_REPEAT');
  return {ok:true, lockKey:lockKey, status:String(result.status || '')};
}

function runCentralSeedPromotionCycleV1() {
  const seeds = ccemSheetObjects_(CCEM_MASTER_ID, '35_INTERNAL_SEED_REGISTRY');
  const queue = ccemSheetObjects_(CCEM_MASTER_ID, '07_EXECUTION_QUEUE');
  const completedAnalysis = queue.filter(function(q) {
    return String(q.TASK_TYPE || '') === 'ASSET_MULTIMODAL_ANALYSIS' && /COMPLETED|VERIFIED|DONE/i.test(String(q.STATUS || ''));
  });
  const seedIds = {};
  seeds.forEach(function(s) { if (s.SEED_ID) seedIds[String(s.SEED_ID)] = true; });

  const result = {
    existingSeeds: seeds.length,
    completedAnalysisTasks: completedAnalysis.length,
    state: 'SEED_PROMOTION_REQUIRES_ACTUAL_ANALYSIS_PAYLOAD',
    rule: 'Do not fabricate SEED_TEXT. Completed analysis must carry source/evidence/seed candidate payload before append.',
    next: 'REGISTER_ANALYSIS_RESULT→SEED_CANDIDATE→QA_X2→35_INTERNAL_SEED_REGISTRY'
  };
  ccemAppendHistory_('SEED_PROMOTION', result, 'PROMOTE_ONLY_EVIDENCE_BACKED_CANDIDATES');
  return result;
}

function runCentralTemplatePromotionCycleV1() {
  const seeds = ccemSheetObjects_(CCEM_MASTER_ID, '35_INTERNAL_SEED_REGISTRY');
  const templates = ccemSheetObjects_(CCEM_MASTER_ID, '70_MULTIMODAL_TEMPLATE_LIBRARY');
  const evolution = ccemSheetObjects_(CCEM_MASTER_ID, '77_TEMPLATE_EVOLUTION_FACTORY');
  const result = {
    seeds: seeds.length,
    templates: templates.length,
    evolutionRows: evolution.length,
    state: 'TEMPLATE_PROMOTION_AUDIT_ONLY_UNTIL_X2_EVIDENCE',
    gate: 'SAME_FIXTURE_RETEST_X2+PURPOSE_FIT+REGRESSION+LESSON_CHECKED'
  };
  ccemAppendHistory_('TEMPLATE_PROMOTION', result, 'KEEP_CANDIDATE_UNTIL_X2');
  return result;
}

function registerPlatformResultUrlV1(payload) {
  payload = payload || {};
  const url = String(payload.publicUrl || payload.url || '').trim();
  if (!/^https:\/\//i.test(url)) return {ok:false, state:'REAL_HTTPS_URL_REQUIRED'};
  const publishId = String(payload.publishId || ('PUB_' + Utilities.getUuid().replace(/-/g,'').slice(0,16)));
  ccemAppendMasterByHeader_('33_FRONT_PUBLISH_URL_REGISTRY', {
    PUBLISH_ID: publishId,
    CONTENT_ID: String(payload.contentId || ''),
    SEED_ID: String(payload.seedId || ''),
    RESULT_ID: String(payload.resultId || ''),
    PARENT_PUBLISH_ID: String(payload.parentPublishId || ''),
    APP_ID: String(payload.appId || ''),
    PUBLISH_LEVEL: String(payload.publishLevel || 'RESULT_URL'),
    SLUG: String(payload.slug || ''),
    PUBLIC_URL: url,
    API_READ_URL: String(payload.apiReadUrl || ''),
    DRIVE_SOURCE_ID: String(payload.driveSourceId || ''),
    GITHUB_VERSION: String(payload.githubVersion || ''),
    INDEX_POLICY: String(payload.indexPolicy || 'VERIFY_BEFORE_INDEX'),
    HTTP_STATUS: String(payload.httpStatus || ''),
    DEPLOY_STATUS: String(payload.deployStatus || 'URL_RECORDED_READBACK_REQUIRED'),
    GOOGLE_INDEX_STATUS: String(payload.googleIndexStatus || 'NOT_CHECKED'),
    CANONICAL_URL: String(payload.canonicalUrl || url),
    VERIFY_COUNT: Number(payload.verifyCount || 0),
    LAST_ERROR: String(payload.lastError || ''),
    CREATED_AT: new Date(),
    UPDATED_AT: new Date(),
    NOTES: String(payload.notes || 'Registered by CentralChromeExtensionAutomationManager; provider/content ID and URL readback still required before VERIFIED.')
  });
  ccemAppendHistory_('PLATFORM_URL', {publishId:publishId,url:url,appId:String(payload.appId||'')}, 'VERIFY_PROVIDER_ID_URL_AND_FEEDBACK_TO_SEED');
  return {ok:true, publishId:publishId, url:url, state:'URL_RECORDED_READBACK_REQUIRED'};
}

function runCentralChromeDataOrchestraAuditV1() {
  const runId = 'CCEM_AUDIT_' + Utilities.formatDate(new Date(), Session.getScriptTimeZone() || 'Asia/Seoul', 'yyyyMMdd_HHmmss');
  const health = runCentralChromeExtensionHealthCycleV1();
  const asset = runCentralAssetIngestCycleV1();
  const seed = runCentralSeedPromotionCycleV1();
  const template = runCentralTemplatePromotionCycleV1();
  const queue = ccemSheetObjects_(CCEM_MASTER_ID, '07_EXECUTION_QUEUE');
  const errors = ccemSheetObjects_(CCEM_MANAGER_ID, '10_ERROR_LEARNING');
  const waiting = queue.filter(function(q){ return /READY|QUEUED|HOLD|BLOCK/i.test(String(q.STATUS || '')); }).length;
  const result = {
    runId: runId,
    health: health.state,
    newAssetQueued: asset.queued,
    seedState: seed.state,
    templateState: template.state,
    waitingQueue: waiting,
    learnedErrorPatterns: errors.length,
    completion: 'RUNTIME_X2_AND_DRIVE_READBACK_REQUIRED'
  };
  ccemAppendHistory_('FULL_AUDIT', result, waiting ? 'PROCESS_P0_EXISTING_QUEUE_WITH_TRAFFIC_GUARD' : 'KEEP_SCHEDULE');
  return result;
}

function ccemClassifyAssetType_(file) {
  const mime = String(file.MIME_TYPE || file.mimeType || '').toLowerCase();
  const title = String(file.TITLE || file.title || '').toLowerCase();
  if (mime.indexOf('video/') === 0 || /\.(mp4|mov|webm|mkv)$/i.test(title)) return 'VIDEO';
  if (mime.indexOf('audio/') === 0 || /\.(mp3|m4a|wav|aac|ogg)$/i.test(title)) return 'AUDIO';
  if (mime.indexOf('image/') === 0 || /\.(png|jpe?g|webp|gif)$/i.test(title)) return 'IMAGE';
  if (mime.indexOf('text/') === 0 || /\.(txt|md|csv|json)$/i.test(title)) return 'TEXT';
  if (/pdf|document|presentation|spreadsheet/.test(mime) || /\.(pdf|docx?|pptx?|xlsx?)$/i.test(title)) return 'DOCUMENT';
  if (/\.skp$/i.test(title) || /sketchup/i.test(mime)) return 'SKETCHUP';
  return '';
}

function ccemServiceFromWorkflow_(workflowId) {
  const x = String(workflowId || '').toUpperCase();
  if (x.indexOf('NOTEBOOK') >= 0 || x.indexOf('NLM') >= 0) return 'NOTEBOOKLM';
  if (x.indexOf('FLOW') >= 0) return 'FLOW';
  if (x.indexOf('SKETCH') >= 0) return 'SKETCHUP';
  if (x.indexOf('AI_STUDIO') >= 0) return 'AI_STUDIO';
  if (x.indexOf('FRONT') >= 0 || x.indexOf('QA') >= 0) return 'FRONT_QA';
  return '';
}

function ccemFindExtensionForService_(service) {
  const rows = ccemSheetObjects_(CCEM_MANAGER_ID, '01_EXTENSION_REGISTRY');
  const target = String(service || '').toUpperCase();
  for (let i = 0; i < rows.length; i++) {
    const s = String(rows[i].SERVICE || '').toUpperCase();
    if (s === target || (target === 'SKETCHUP' && s.indexOf('SKETCHUP') >= 0)) return rows[i];
  }
  return null;
}

function ccemTrafficLockForService_(service) {
  const s = String(service || '').toUpperCase();
  if (s === 'NOTEBOOKLM') return 'NOTEBOOKLM_STUDIO';
  if (s === 'FLOW') return 'FLOW_GENERATION';
  return 'CHROME_GLOBAL';
}

function ccemAcquireTrafficSlot_(lockKey, estimatedDurationSec, minGapSec) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) return {ok:false, nextAllowedAt:'LOCK_BUSY'};
  try {
    const props = PropertiesService.getScriptProperties();
    const key = 'CCEM_NEXT_' + ccemSafeId_(lockKey);
    const now = Date.now();
    const next = Number(props.getProperty(key) || 0);
    if (next > now) return {ok:false, nextAllowedAt:new Date(next).toISOString()};
    const reserveMs = (Math.max(1, Number(estimatedDurationSec || 60)) + Math.max(0, Number(minGapSec || 0))) * 1000;
    const nextAt = now + reserveMs;
    props.setProperty(key, String(nextAt));
    return {ok:true, nextAllowedAt:new Date(nextAt).toISOString()};
  } finally {
    lock.releaseLock();
  }
}

function ccemReleaseTrafficSlot_(lockKey, durationSec, minGapSec) {
  if (!lockKey) return;
  const props = PropertiesService.getScriptProperties();
  const now = Date.now();
  const gapMs = Math.max(0, Number(minGapSec || 0)) * 1000;
  props.setProperty('CCEM_NEXT_' + ccemSafeId_(lockKey), String(now + gapMs));
  if (durationSec > 0) {
    const avgKey = 'CCEM_AVG_' + ccemSafeId_(lockKey);
    const oldAvg = Number(props.getProperty(avgKey) || durationSec);
    const newAvg = Math.round(oldAvg * 0.7 + Number(durationSec) * 0.3);
    props.setProperty(avgKey, String(newAvg));
  }
}

function ccemAppendHistory_(directive, payload, resumePoint) {
  ccemAppendManagerByHeader_('15_HISTORY_READBACK', {
    TIMESTAMP: new Date(),
    DIRECTIVE: String(directive || ''),
    CASE_LOOKUP: '18→34→24→51→63→73→75→80→83→84→88→LAST_GOOD',
    ACTION: JSON.stringify(payload || {}).slice(0, 4000),
    RESULT: String((payload && (payload.state || payload.status)) || 'RECORDED'),
    RESUME_POINT: String(resumePoint || '')
  });
}

function ccemSheetObjects_(spreadsheetId, sheetName) {
  const sh = SpreadsheetApp.openById(spreadsheetId).getSheetByName(sheetName);
  if (!sh) return [];
  const values = sh.getDataRange().getValues();
  if (!values.length) return [];
  const headers = values[0].map(function(v){ return String(v || '').trim(); });
  return values.slice(1).filter(function(row){ return row.some(function(v){ return String(v || '') !== ''; }); }).map(function(row){
    const o = {};
    headers.forEach(function(h, i){ if (h) o[h] = row[i]; });
    return o;
  });
}

function ccemAppendMasterByHeader_(sheetName, obj) {
  return ccemAppendByHeader_(CCEM_MASTER_ID, sheetName, obj);
}

function ccemAppendManagerByHeader_(sheetName, obj) {
  return ccemAppendByHeader_(CCEM_MANAGER_ID, sheetName, obj);
}

function ccemAppendByHeader_(spreadsheetId, sheetName, obj) {
  const sh = SpreadsheetApp.openById(spreadsheetId).getSheetByName(sheetName);
  if (!sh) throw new Error('CCEM_SHEET_NOT_FOUND:' + sheetName);
  const lastCol = sh.getLastColumn();
  if (lastCol < 1) throw new Error('CCEM_HEADER_MISSING:' + sheetName);
  const headers = sh.getRange(1, 1, 1, lastCol).getValues()[0].map(function(v){ return String(v || '').trim(); });
  const row = headers.map(function(h){ return Object.prototype.hasOwnProperty.call(obj, h) ? obj[h] : ''; });
  sh.appendRow(row);
  return {ok:true,row:sh.getLastRow(),sheet:sheetName};
}

function ccemSafeId_(value) {
  return String(value || '').replace(/[^A-Za-z0-9_\-]+/g, '_');
}
