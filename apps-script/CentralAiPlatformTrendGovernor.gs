const CAITG_VERSION = 'AI_PLATFORM_TREND_GOVERNOR_V1_20260828';
const CAITG_SHEET_ID = '1pWXbLskmqjCNFoi8N85JDyocordjo4ROuoJoLSkAymk';
const CAITG_MASTER_ID = '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI';

function installCentralAiPlatformTrendGovernorTriggersV1() {
  const handler = 'runCentralAiPlatformTrendGovernorCycleV1';
  ScriptApp.getProjectTriggers().forEach(function(t){
    if (t.getHandlerFunction() === handler) ScriptApp.deleteTrigger(t);
  });
  [9, 21].forEach(function(hour){
    ScriptApp.newTrigger(handler).timeBased().atHour(hour).everyDays(1).create();
  });
  return {
    ok: true,
    handler: handler,
    hoursKst: [9,21],
    state: 'TRIGGERS_CREATED_RUNTIME_READBACK_REQUIRED',
    version: CAITG_VERSION
  };
}

function runCentralAiPlatformTrendGovernorCycleV1() {
  const started = new Date();
  const runId = 'AITG_' + Utilities.formatDate(started, Session.getScriptTimeZone() || 'Asia/Seoul', 'yyyyMMdd_HHmmss') + '_' + Utilities.getUuid().slice(0,8);
  const sourceScan = scanOfficialTrendSourcesV1_(runId);
  const costGuard = enforceAiApiCostPolicyV1_(runId, sourceScan);
  const patchQueue = queueMaterialTrendImpactsV1_(runId, sourceScan, costGuard);
  const deployment = auditKnownDeploymentDriftV1_(runId);
  appendTrendRuntimeTestV1_(runId, sourceScan, costGuard, patchQueue, deployment);
  return {
    runId: runId,
    sourceScan: sourceScan,
    costGuard: costGuard,
    patchQueue: patchQueue,
    deployment: deployment,
    state: 'RUNTIME_EXECUTED_READBACK_REQUIRED',
    version: CAITG_VERSION
  };
}

function scanOfficialTrendSourcesV1_(runId) {
  const sources = caItgSheetObjects_('01_SOURCE_WATCH');
  const props = PropertiesService.getScriptProperties();
  let checked = 0, changed = 0, failed = 0, baseline = 0;
  const material = [];

  sources.forEach(function(src){
    const url = String(src.SOURCE_URL || '');
    if (!url || String(src.AUTH_REQUIRED || '').toUpperCase() === 'Y') return;
    checked++;
    try {
      const response = UrlFetchApp.fetch(url, {
        muteHttpExceptions: true,
        followRedirects: true,
        headers: {'User-Agent':'CentralAgent-AITrendGovernor/1.0'}
      });
      const code = response.getResponseCode();
      if (code < 200 || code >= 400) throw new Error('HTTP_' + code);
      const normalized = normalizeTrendTextV1_(response.getContentText());
      const signature = sha256HexV1_(normalized.slice(0, 180000));
      const key = 'AITG_HASH_' + String(src.SOURCE_ID || safeTrendIdV1_(url));
      const prev = props.getProperty(key);
      props.setProperty(key, signature);
      updateSourceWatchReadbackV1_(String(src.SOURCE_ID||''), signature, code, runId);
      if (!prev) {
        baseline++;
        return;
      }
      if (prev === signature) return;

      changed++;
      const cls = classifyOfficialSourceChangeV1_(src, normalized);
      const updateId = 'AUTO_' + safeTrendIdV1_(String(src.SOURCE_ID||'')) + '_' + signature.slice(0,12);
      const record = {
        UPDATE_ID:updateId,
        DATE:Utilities.formatDate(new Date(), Session.getScriptTimeZone() || 'Asia/Seoul','yyyy-MM-dd'),
        VENDOR:String(src.VENDOR||''),
        PRODUCT:String(src.SOURCE_NAME||''),
        TYPE:cls.type,
        WHAT_CHANGED:'Official source content signature changed. Review excerpt: ' + excerptTrendV1_(normalized, cls.keywords),
        WORKFLOW_IMPACT:cls.workflowImpact,
        COST_IMPACT:cls.costImpact,
        BRIDGE_IMPACT:cls.bridgeImpact,
        CODE_IMPACT:cls.codeImpact,
        TEST_REQUIRED:'Y',
        SOURCE_URL:url,
        CONFIDENCE:'OFFICIAL_SOURCE_CHANGE_DETECTED',
        NEXT_ACTION:cls.nextAction,
        STATUS:cls.status
      };
      if (!trendRowExistsV1_('02_UPDATE_FEED','UPDATE_ID',updateId)) appendTrendRowByHeaderV1_('02_UPDATE_FEED', record);
      material.push({source:src, classification:cls, update:record, signature:signature});
    } catch(e) {
      failed++;
      appendTrendRuntimeFailureV1_(runId, src, String(e));
    }
  });

  return {checked:checked,changed:changed,failed:failed,baseline:baseline,material:material};
}

function enforceAiApiCostPolicyV1_(runId, sourceScan) {
  const apiRows = caItgSheetObjects_('04_API_COST_GOVERNANCE');
  let blockedPaid = 0, conditional = 0, safeExisting = 0;
  apiRows.forEach(function(r){
    const id = String(r.API_ID||'');
    const approval = String(r.APPROVAL_CLASS||'');
    const autoEnable = String(r.AUTO_ENABLE||'').toUpperCase();
    const autoCall = String(r.AUTO_CALL||'').toUpperCase();
    if (/USER_APPROVAL_REQUIRED|PUBLIC_PUBLISH_GATE|EXTERNAL_REVIEW_PENDING/.test(approval) || autoEnable === 'N') blockedPaid++;
    else if (autoCall === 'CONDITIONAL') conditional++;
    else safeExisting++;
    if (/OPENAI|GEMINI/.test(id) && !/USER_APPROVAL_REQUIRED/.test(approval)) {
      appendTrendRowByHeaderV1_('09_RUNTIME_TEST', {
        TEST_ID:'AUTO_COST_POLICY_'+safeTrendIdV1_(id)+'_'+runId,
        SCOPE:'AI API COST GOVERNANCE',
        FIXTURE:id,
        PRECHECK:'subscription/API separation',
        ACTION:'policy audit',
        EXPECTED:'paid API cannot auto-enable or auto-buy credits',
        ACTUAL:'POLICY_REVIEW_REQUIRED',
        READBACK:'04_API_COST_GOVERNANCE',
        RUN_COUNT:1,
        STATUS:'FAIL_POLICY_GAP',
        LAST_RUN:new Date(),
        BLOCKER:'approval class missing',
        NEXT_ACTION:'patch approval class before any API call',
        EVIDENCE:runId
      });
    }
  });

  const pricingChanges = (sourceScan.material||[]).filter(function(m){
    return /PRICE|BILLING|COST|QUOTA/.test(String(m.classification.type||''));
  }).length;
  return {
    apiRows:apiRows.length,
    blockedPaid:blockedPaid,
    conditional:conditional,
    safeExisting:safeExisting,
    pricingChanges:pricingChanges,
    rule:'SUBSCRIPTION_UI_FIRST; API_SEPARATE_BILLING; NO_AUTO_PAID_ACTIVATION'
  };
}

function queueMaterialTrendImpactsV1_(runId, sourceScan, costGuard) {
  let queued = 0, blockedApproval = 0;
  (sourceScan.material||[]).forEach(function(m){
    const cls = m.classification;
    const update = m.update;
    const requiresApproval = /USER_APPROVAL|BILLING|OAUTH|SECRET|SCOPE|PUBLIC|TERMS|EXTERNAL_REVIEW/.test(String(cls.approvalClass||''));
    const patchId = 'AUTO_PATCH_' + safeTrendIdV1_(update.UPDATE_ID);
    if (!trendRowExistsV1_('08_PATCH_QUEUE','PATCH_ID',patchId)) {
      appendTrendRowByHeaderV1_('08_PATCH_QUEUE', {
        PATCH_ID:patchId,
        PRIORITY:cls.priority,
        TARGET_REPO:cls.targetRepo,
        TARGET_FILE_OR_FUNCTION:cls.targetFunction,
        CHANGE_ID:update.UPDATE_ID,
        PRECHECK:'LAST_GOOD + canonical repo/function + current runtime evidence',
        PATCH:cls.patch,
        TEST:'same fixture x2 + readback',
        DEPLOY_ACTION:requiresApproval?'HOLD_PUBLIC_OR_HIGH_IMPACT':'NONE_UNLESS_TARGET_REQUIRES',
        API_ACTION:cls.apiAction,
        APPROVAL:requiresApproval?cls.approvalClass:'NONE_SAFE_PATCH',
        STATUS:requiresApproval?'BLOCKED_APPROVAL':'READY_AFTER_PRECHECK',
        EVIDENCE:update.SOURCE_URL,
        NEXT_ACTION:requiresApproval?'record exact user action only':'PRECHECK→minimum patch→x2 test'
      });
    }

    const taskId = 'TASK_AITG_' + safeTrendIdV1_(update.UPDATE_ID).slice(0,64);
    if (!masterTaskExistsV1_(taskId)) {
      appendMasterTrendByHeaderV1_('07_EXECUTION_QUEUE', {
        TASK_ID:taskId,
        STAGE_NO:1,
        TASK_TYPE:'AI_PLATFORM_UPDATE_REVIEW',
        TARGET_ID:update.UPDATE_ID,
        ACTION:cls.patch,
        PRIORITY:cls.priority,
        APPROVAL_STATUS:requiresApproval?'USER_APPROVAL_REQUIRED':'POLICY_AUTO_APPROVED_SAFE_REVIEW',
        EXECUTION_METHOD:'PRECHECK→OFFICIAL_SOURCE→CANONICAL_REPO→MIN_PATCH→TEST_X2',
        STATUS:requiresApproval?'BLOCKED_APPROVAL':'READY',
        RETRY_COUNT:0,
        CREATED_AT:new Date(),
        UPDATED_AT:new Date(),
        NOTES:'Source='+update.SOURCE_URL+'; ChatGPT/Google AI Pro subscription UI preferred; API separate billing.',
        OWNER:'CENTRAL_AGENT',
        FIRST_REQUESTED_AT:new Date(),
        LAST_REQUESTED_AT:new Date(),
        REQUEST_COUNT:1,
        COMPLETION_EVIDENCE:'DIFF+TEST_X2+RUNTIME_READBACK+ROLLBACK',
        APPROVAL_TYPE:requiresApproval?cls.approvalClass:'NONE'
      });
    }
    if (requiresApproval) blockedApproval++; else queued++;
  });
  return {queued:queued,blockedApproval:blockedApproval};
}

function auditKnownDeploymentDriftV1_(runId) {
  const rows = caItgSheetObjects_('06_DEPLOYED_APP_RADAR');
  const mismatch = rows.filter(function(r){
    const expected = String(r.CANONICAL_EXPECTED||'');
    const actual = String(r.CANONICAL_ACTUAL||'');
    return expected && actual && expected !== actual;
  });
  mismatch.forEach(function(r){
    const id = 'AUTO_DEPLOY_DRIFT_' + safeTrendIdV1_(String(r.DEPLOY_ID||''));
    if (!trendRowExistsV1_('08_PATCH_QUEUE','PATCH_ID',id)) {
      appendTrendRowByHeaderV1_('08_PATCH_QUEUE', {
        PATCH_ID:id,
        PRIORITY:'P0',
        TARGET_REPO:String(r.CANONICAL_EXPECTED||r.GITHUB_REPO||''),
        TARGET_FILE_OR_FUNCTION:'Vercel repo/branch/SHA contract',
        CHANGE_ID:String(r.DEPLOY_ID||''),
        PRECHECK:'current Production URL/SHA + canonical repo parity + LAST_GOOD',
        PATCH:'DIAGNOSTIC_HOLD; compare features before relink or merge',
        TEST:'preview + production readback x2 only after parity',
        DEPLOY_ACTION:'NO_BLIND_PRODUCTION_RELINK',
        API_ACTION:'NONE',
        APPROVAL:'USER_APPROVAL_IF_HIGH_IMPACT_PRODUCTION_CHANGE',
        STATUS:'DIAGNOSTIC_HOLD',
        EVIDENCE:String(r.LATEST_PROD_URL||''),
        NEXT_ACTION:'compare current live repo vs canonical; preserve working features'
      });
    }
  });
  return {checked:rows.length,mismatch:mismatch.length,mismatchIds:mismatch.map(function(r){return r.DEPLOY_ID;})};
}

function appendTrendRuntimeTestV1_(runId, sourceScan, costGuard, patchQueue, deployment) {
  appendTrendRowByHeaderV1_('09_RUNTIME_TEST', {
    TEST_ID:'AUTO_TREND_CYCLE_'+runId,
    SCOPE:'AI/PLATFORM TREND GOVERNOR',
    FIXTURE:'official source watch + deployment/cost policy',
    PRECHECK:'01_SOURCE_WATCH + 04_API_COST_GOVERNANCE + canonical registry',
    ACTION:'fetch→hash→classify→cost gate→patch queue→deployment drift',
    EXPECTED:'no paid activation; material changes queued; no blind deploy',
    ACTUAL:'checked='+sourceScan.checked+'; changed='+sourceScan.changed+'; failed='+sourceScan.failed+'; queued='+patchQueue.queued+'; approval='+patchQueue.blockedApproval+'; drift='+deployment.mismatch,
    READBACK:'02_UPDATE_FEED|08_PATCH_QUEUE|07_EXECUTION_QUEUE',
    RUN_COUNT:1,
    STATUS:sourceScan.failed>0?'DEGRADED_SOURCE_FETCH':'PASS_CYCLE_SINGLE_RUN',
    LAST_RUN:new Date(),
    BLOCKER:sourceScan.failed>0?'one or more source fetches failed':'',
    NEXT_ACTION:'same fixture second run required before VERIFIED',
    EVIDENCE:CAITG_VERSION
  });
}

function classifyOfficialSourceChangeV1_(src, text) {
  const lower = String(text||'').toLowerCase();
  const sourceId = String(src.SOURCE_ID||'');
  const isCost = /price|pricing|billing|credit|quota|rate limit|prepay|postpay|spend cap|cost/.test(lower);
  const isBreaking = /deprecat|retir|removed|oauth|scope|terms|guidelines|migration|required action|breaking/.test(lower);
  const isMedia = /video|image|audio|flow|veo|omni|frame|4k|resolution/.test(lower);
  const isAgent = /agent|mcp|plugin|workflow|webhook|tool calling|function calling/.test(lower);
  const isPublish = /pinterest|tiktok|publish|content posting|pin|board/.test(lower);
  let type = isCost?'PRICE_BILLING_REVIEW':(isBreaking?'BREAKING_POLICY_REVIEW':'FEATURE_REVIEW');
  let priority = isBreaking?'P0':(isCost?'P1':'P2');
  let approvalClass = isCost?'USER_APPROVAL_IF_PAID_SPEND_CHANGES':(isBreaking?'USER_APPROVAL_IF_SCOPE_TERMS_PUBLIC_IMPACT':'NONE_SAFE_REVIEW');
  let targetRepo = 'CENTRAL_REVIEW';
  let targetFunction = 'impact classifier';
  let patch = 'record source delta and compare to current workflow; minimum compatible patch only';
  let bridgeImpact = isAgent?'BRIDGE_OR_AGENT_CONTRACT_REVIEW':(isMedia?'MEDIA_BRIDGE_REVIEW':(isPublish?'PUBLISH_BRIDGE_REVIEW':'CHECK_REQUIRED'));
  let apiAction = isCost?'NO_AUTO_ENABLE_OR_BILLING_CHANGE':'NONE_UNLESS_GAP_REQUIRES';
  if (/NOTEBOOK|GEMINI_NOTEBOOK/.test(sourceId)) { targetRepo='8friend8ship-cloud/notebooklm-webapp-bridge'; targetFunction='Notebook/Gemini Notebook selectors and runtime'; patch='dual-name/selector compatibility; preserve canonical task contract'; priority='P0'; }
  if (/FLOW/.test(sourceId)) { targetRepo='VIDEO_INTERIOR_TEMPLATE_REPOS'; targetFunction='Flow media template schema'; patch='update supported controls/metadata only; subscription UI first'; priority='P1'; }
  if (/VERCEL|GITHUB/.test(sourceId)) { targetRepo='AFFECTED_CANONICAL_REPO'; targetFunction='build/deploy/agent compatibility'; patch='compare dependency/runtime/agent contract; do not mass-upgrade'; }
  if (/PINTEREST|TIKTOK/.test(sourceId)) { targetRepo='PUBLISH_ADAPTER'; targetFunction='official publisher adapter'; patch='review terms/scopes/formats; hold public writes until provider/user gates pass'; approvalClass='USER_APPROVAL_IF_NEW_SCOPE_OR_PUBLIC_WRITE'; }
  return {
    type:type,
    priority:priority,
    approvalClass:approvalClass,
    workflowImpact:isAgent?'agent/automation architecture':(isMedia?'media template/runtime':(isPublish?'publisher workflow':'workflow compatibility/cost')),
    costImpact:isCost?'LIVE_COST_SNAPSHOT_CHANGED_OR_REVIEW':'NO_DIRECT_COST_CHANGE_DETECTED',
    bridgeImpact:bridgeImpact,
    codeImpact:isBreaking?'PATCH_OR_MIGRATION_REVIEW_REQUIRED':'MINIMUM_PATCH_REVIEW',
    nextAction:approvalClass==='NONE_SAFE_REVIEW'?'PRECHECK→minimum patch→x2 test':'record exact approval requirement; no auto consequential action',
    status:isBreaking?'REVIEW_REQUIRED':(isCost?'PATCH_COST_POLICY':'REVIEW_FOR_PATCH'),
    patch:patch,
    targetRepo:targetRepo,
    targetFunction:targetFunction,
    apiAction:apiAction,
    keywords:(isCost?['pricing','billing','quota','credit']:(isBreaking?['deprecated','oauth','terms','required']:['new','available','update','release']))
  };
}

function updateSourceWatchReadbackV1_(sourceId, signature, httpCode, runId) {
  const sh = SpreadsheetApp.openById(CAITG_SHEET_ID).getSheetByName('01_SOURCE_WATCH');
  if (!sh) return;
  const data = sh.getDataRange().getValues();
  const h = data[0].map(String);
  const idCol = h.indexOf('SOURCE_ID');
  const lastCol = h.indexOf('LAST_SNAPSHOT_DATE');
  const notesCol = h.indexOf('NOTES');
  for (let r=1;r<data.length;r++) {
    if (String(data[r][idCol]) !== sourceId) continue;
    if (lastCol >= 0) sh.getRange(r+1,lastCol+1).setValue(new Date());
    if (notesCol >= 0) {
      const base = String(data[r][notesCol]||'').replace(/\s*\|\s*AUTO_READBACK=.*/,'');
      sh.getRange(r+1,notesCol+1).setValue(base + ' | AUTO_READBACK=' + httpCode + '/' + signature.slice(0,12) + '/' + runId);
    }
    break;
  }
}

function appendTrendRuntimeFailureV1_(runId, src, errorText) {
  appendTrendRowByHeaderV1_('09_RUNTIME_TEST', {
    TEST_ID:'AUTO_SRC_FAIL_'+safeTrendIdV1_(String(src.SOURCE_ID||''))+'_'+runId,
    SCOPE:'OFFICIAL_SOURCE_FETCH',
    FIXTURE:String(src.SOURCE_URL||''),
    PRECHECK:'no auth source',
    ACTION:'UrlFetchApp.fetch',
    EXPECTED:'HTTP 2xx/3xx + normalized content',
    ACTUAL:errorText,
    READBACK:'',
    RUN_COUNT:1,
    STATUS:'DEGRADED_SOURCE_FETCH',
    LAST_RUN:new Date(),
    BLOCKER:errorText,
    NEXT_ACTION:'retry next scheduled cycle; after repeat use root-cause/source-specific adapter',
    EVIDENCE:String(src.SOURCE_ID||'')
  });
}

function caItgSheetObjects_(sheetName) {
  const sh = SpreadsheetApp.openById(CAITG_SHEET_ID).getSheetByName(sheetName);
  if (!sh) return [];
  const lr=sh.getLastRow(), lc=sh.getLastColumn();
  if (lr < 2 || lc < 1) return [];
  const v=sh.getRange(1,1,lr,lc).getValues(), h=v[0].map(String);
  return v.slice(1).filter(function(r){return r.some(function(x){return x!=='';});}).map(function(r){
    const o={}; h.forEach(function(k,i){o[k]=r[i];}); return o;
  });
}

function appendTrendRowByHeaderV1_(sheetName, payload) {
  const sh=SpreadsheetApp.openById(CAITG_SHEET_ID).getSheetByName(sheetName);
  if (!sh) throw new Error('TREND_SHEET_NOT_FOUND:'+sheetName);
  const h=sh.getRange(1,1,1,sh.getLastColumn()).getValues()[0].map(String);
  sh.appendRow(h.map(function(k){ return Object.prototype.hasOwnProperty.call(payload,k)?payload[k]:''; }));
}

function appendMasterTrendByHeaderV1_(sheetName, payload) {
  const sh=SpreadsheetApp.openById(CAITG_MASTER_ID).getSheetByName(sheetName);
  if (!sh) throw new Error('MASTER_SHEET_NOT_FOUND:'+sheetName);
  const h=sh.getRange(1,1,1,sh.getLastColumn()).getValues()[0].map(String);
  sh.appendRow(h.map(function(k){ return Object.prototype.hasOwnProperty.call(payload,k)?payload[k]:''; }));
}

function trendRowExistsV1_(sheetName, keyHeader, keyValue) {
  const rows = caItgSheetObjects_(sheetName);
  return rows.some(function(r){return String(r[keyHeader]||'')===String(keyValue||'');});
}

function masterTaskExistsV1_(taskId) {
  const sh=SpreadsheetApp.openById(CAITG_MASTER_ID).getSheetByName('07_EXECUTION_QUEUE');
  if (!sh || sh.getLastRow()<2) return false;
  const v=sh.getDataRange().getValues(), h=v[0].map(String), c=h.indexOf('TASK_ID');
  if (c<0) return false;
  return v.slice(1).some(function(r){return String(r[c]||'')===String(taskId||'');});
}

function normalizeTrendTextV1_(html) {
  return String(html||'')
    .replace(/<script[\s\S]*?<\/script>/gi,' ')
    .replace(/<style[\s\S]*?<\/style>/gi,' ')
    .replace(/<[^>]+>/g,' ')
    .replace(/&nbsp;/gi,' ')
    .replace(/&amp;/gi,'&')
    .replace(/&lt;/gi,'<')
    .replace(/&gt;/gi,'>')
    .replace(/\s+/g,' ')
    .trim();
}

function excerptTrendV1_(text, keywords) {
  const t=String(text||'');
  let pos=-1;
  (keywords||[]).some(function(k){ pos=t.toLowerCase().indexOf(String(k).toLowerCase()); return pos>=0; });
  if (pos<0) pos=0;
  return t.slice(Math.max(0,pos-220), Math.min(t.length,pos+700));
}

function sha256HexV1_(text) {
  const bytes=Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, String(text||''), Utilities.Charset.UTF_8);
  return bytes.map(function(b){const v=(b<0?b+256:b).toString(16);return v.length===1?'0'+v:v;}).join('');
}

function safeTrendIdV1_(s) {
  return String(s||'').replace(/[^A-Za-z0-9_-]+/g,'_').replace(/^_+|_+$/g,'') || Utilities.getUuid().slice(0,12);
}
