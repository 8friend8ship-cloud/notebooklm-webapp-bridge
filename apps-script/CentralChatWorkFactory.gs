const CCWF_VERSION = 'CENTRAL_CHAT_WORK_FACTORY_V1_20260828';
const CCWF_MASTER_ID = '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI';

/**
 * PRIMARY OPERATING RULE
 * Apps Script + webapp + registered bridges are the execution plane.
 * OpenAI Work / Gemini / external model APIs are optional comparison or
 * exception-resolution tools, never the default runtime for routine work.
 */
function installCentralChatWorkFactoryTriggersV1() {
  const handler = 'runCentralChatWorkFactoryV1';
  ScriptApp.getProjectTriggers().forEach(function(t) {
    if (t.getHandlerFunction() === handler) ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger(handler).timeBased().everyMinutes(15).create();
  return {
    ok: true,
    handler: handler,
    cadence: '15_MIN',
    state: 'TRIGGER_CREATED_RUNTIME_READBACK_REQUIRED',
    version: CCWF_VERSION
  };
}

function runCentralChatWorkFactoryV1() {
  const started = new Date();
  const runId = 'CCWF_' + Utilities.formatDate(started, Session.getScriptTimeZone() || 'Asia/Seoul', 'yyyyMMdd_HHmmss') + '_' + Utilities.getUuid().slice(0, 8);
  const precheck = ccwfPrecheck_();
  if (precheck.status !== 'PASS') {
    ccwfWriteRuntime_(runId, started, 'DIAGNOSTIC_HOLD', precheck.reason || 'PRECHECK_FAILED', precheck);
    return {runId: runId, status: 'DIAGNOSTIC_HOLD', precheck: precheck};
  }

  const commands = ccwfRows_('34_CHAT_COMMAND_HISTORY');
  const recent = commands.slice(-100);
  const queue = ccwfRows_('07_EXECUTION_QUEUE');
  const queuedTaskIds = {};
  queue.forEach(function(r) { if (r.TASK_ID) queuedTaskIds[String(r.TASK_ID)] = true; });

  let queued = 0;
  let learned = 0;
  let bridged = 0;
  let held = 0;
  const touched = [];

  recent.forEach(function(cmd) {
    const taskId = String(cmd.TASK_ID || '').trim();
    const cmdId = String(cmd.CHAT_CMD_ID || '').trim();
    if (!cmdId) return;

    const classification = ccwfClassifyCommand_(cmd);
    if (classification === 'IGNORE') return;

    if (taskId && !queuedTaskIds[taskId] && classification === 'EXECUTE') {
      const work = ccwfBuildQueueRow_(cmd, taskId);
      ccwfAppendByHeader_('07_EXECUTION_QUEUE', work);
      queuedTaskIds[taskId] = true;
      queued++;
      touched.push(taskId);

      const evt = ccwfPublishWorkEvent_(cmd, taskId);
      if (evt.ok) bridged++;
    }

    if (classification === 'LEARN_SUCCESS' || classification === 'LEARN_FAILURE') {
      const result = ccwfCaptureLesson_(cmd, classification);
      if (result.created) learned++;
    }

    if (classification === 'HUMAN_GATE') held++;
  });

  const unresolved = ccwfReviewInterruptedWork_();
  const conditionalQa = ccwfConditionalQa_(runId, unresolved);

  const status = unresolved.p0 > 0 ? 'PASS_WITH_ACTIVE_BLOCKERS' : 'PASS_FACTORY_CYCLE';
  ccwfWriteRuntime_(runId, started, status, unresolved.p0 ? 'UNRESOLVED_P0_PRESENT' : '', {
    queued: queued,
    learned: learned,
    bridged: bridged,
    held: held,
    unresolved: unresolved,
    conditionalQa: conditionalQa,
    touched: touched
  });
  return {
    runId: runId,
    status: status,
    queued: queued,
    learned: learned,
    bridged: bridged,
    humanGate: held,
    unresolved: unresolved,
    conditionalQa: conditionalQa,
    version: CCWF_VERSION
  };
}

function ccwfPrecheck_() {
  const ss = SpreadsheetApp.openById(CCWF_MASTER_ID);
  const required = [
    '07_EXECUTION_QUEUE','18_AGENT_INSTRUCTION','34_CHAT_COMMAND_HISTORY','35_INTERNAL_SEED_REGISTRY',
    '36_AUTOMATION_TRIGGER_REGISTRY','59_DATA_INTELLIGENCE_BUS','63_EVOLUTION_CHANGELOG',
    '75_ORCHESTRA_WORKFLOW_MAP','77_TEMPLATE_EVOLUTION_FACTORY','80_DATA_RUNTIME_QA_LOG','83_TASK_PRECHECK_ASSET_MAP'
  ];
  const missing = required.filter(function(n) { return !ss.getSheetByName(n); });
  if (missing.length) return {status:'FAIL', reason:'MISSING_TABS:' + missing.join('|')};

  if (typeof centralPrecheckLessonsV1 === 'function') {
    try {
      const p = centralPrecheckLessonsV1('P00_AGENT_CORE','CHAT_WORK_FACTORY','');
      if (p && p.decision === 'DIAGNOSTIC_HOLD') return {status:'FAIL', reason:'LESSON_BLOCK_REPEAT', lesson:p};
    } catch (e) {}
  }
  return {status:'PASS'};
}

function ccwfClassifyCommand_(cmd) {
  const status = String(cmd.STATUS || '').toUpperCase();
  const blocker = String(cmd.BLOCKER || '').toUpperCase();
  const evidence = String(cmd.EVIDENCE || '');
  const next = String(cmd.NEXT_ACTION || '');
  if (/COMPLETE|VERIFIED|PASS_/.test(status) && evidence) return 'LEARN_SUCCESS';
  if (/FAILED|FAIL_|BLOCKED|DIAGNOSTIC_HOLD/.test(status) && (blocker || evidence || next)) return 'LEARN_FAILURE';
  if (/USER_|HUMAN_|APPROVAL_REQUIRED|2FA|OAUTH|SECRET|PAYMENT|BILLING|PUBLIC_PUBLISH/.test(status + '|' + blocker + '|' + next)) return 'HUMAN_GATE';
  if (/COMPLETE|VERIFIED/.test(status)) return 'IGNORE';
  if (/QUEUED|READY|PENDING|REGISTERED|STAGED|REQUIRED|ACTIVE|RUNNING|IMPLEMENTING/.test(status) || !status) return 'EXECUTE';
  return 'EXECUTE';
}

function ccwfBuildQueueRow_(cmd, taskId) {
  const route = String(cmd.ROUTE || 'CENTRAL_FACTORY');
  const project = String(cmd.PROJECT_ID || 'P00_AGENT_CORE');
  const priority = String(cmd.PRIORITY || 'P1');
  return {
    TASK_ID: taskId,
    STAGE_NO: 0,
    TASK_TYPE: 'CHAT_WORK_FACTORY',
    TARGET_ID: project,
    ACTION: String(cmd.USER_REQUEST_SUMMARY || '').slice(0, 12000),
    PRIORITY: priority,
    APPROVAL_STATUS: ccwfNeedsHumanApproval_(cmd) ? 'HUMAN_CONFIRM_REQUIRED' : 'APPROVED_BY_POLICY',
    EXECUTION_METHOD: 'APPS_SCRIPT_WEBAPP_BRIDGE_FIRST|' + route,
    STATUS: ccwfNeedsHumanApproval_(cmd) ? 'BLOCKED_APPROVAL' : 'READY',
    RETRY_COUNT: 0,
    CREATED_AT: new Date(),
    UPDATED_AT: new Date(),
    NOTES: 'PRE_CHECK→LAST_GOOD→MIN_FIX→SAME_FIXTURE_X2; OpenAI Work not default execution plane',
    OWNER: 'CENTRAL_AGENT',
    FIRST_REQUESTED_AT: cmd.RECEIVED_AT || new Date(),
    LAST_REQUESTED_AT: new Date(),
    REQUEST_COUNT: 1,
    BLOCKED_TASK_ID: '',
    COMPLETION_EVIDENCE: '',
    APPROVAL_TYPE: ccwfNeedsHumanApproval_(cmd) ? 'HIGH_RISK_HUMAN_GATE' : 'EXISTING_POLICY_REUSE'
  };
}

function ccwfNeedsHumanApproval_(cmd) {
  const s = [cmd.STATUS,cmd.BLOCKER,cmd.NEXT_ACTION,cmd.USER_REQUEST_SUMMARY].join('|').toUpperCase();
  return /LOGIN|2FA|NEW_SECRET|NEW_SCOPE|OAUTH|PAID|BILLING|PAYMENT|CONTRACT|DELETE|IRREVERSIBLE|PUBLIC_PRODUCTION|PUBLIC_PUBLISH/.test(s);
}

function ccwfPublishWorkEvent_(cmd, taskId) {
  const payload = {
    producer_app_id: 'P00_AGENT_CORE',
    data_stage: 'TASK',
    entity_type: 'CHAT_WORK_ORDER',
    entity_id: taskId,
    keyword: String(cmd.PROJECT_ID || 'ALL_PROJECTS'),
    summary: String(cmd.USER_REQUEST_SUMMARY || '').slice(0, 4000),
    metrics: {priority:String(cmd.PRIORITY || 'P1')},
    urls: [],
    lineage: {chat_cmd_id:String(cmd.CHAT_CMD_ID || ''), route:String(cmd.ROUTE || '')},
    consumer_scope: String(cmd.PROJECT_ID || 'ALL_APPS')
  };
  if (typeof centralPublishDataEvent === 'function') {
    try {
      const r = centralPublishDataEvent(payload);
      return {ok:true, via:'centralPublishDataEvent', result:r};
    } catch (e) {}
  }
  try {
    ccwfAppendByHeader_('59_DATA_INTELLIGENCE_BUS', {
      EVENT_ID: 'EVT_' + taskId,
      PRODUCER_APP_ID: 'P00_AGENT_CORE',
      DATA_STAGE: 'TASK',
      ENTITY_TYPE: 'CHAT_WORK_ORDER',
      ENTITY_ID: taskId,
      KEYWORD: payload.keyword,
      SUMMARY: payload.summary,
      LINEAGE: JSON.stringify(payload.lineage),
      CONSUMER_SCOPE: payload.consumer_scope,
      CREATED_AT: new Date(),
      STATUS: 'READY'
    });
    return {ok:true, via:'59_DATA_INTELLIGENCE_BUS'};
  } catch (e2) {
    return {ok:false, error:String(e2)};
  }
}

function ccwfCaptureLesson_(cmd, kind) {
  const key = 'CHATLESSON_' + String(cmd.CHAT_CMD_ID || 'UNKNOWN');
  const existing = ccwfRows_('77_TEMPLATE_EVOLUTION_FACTORY').some(function(r){ return String(r.EVOLVE_ID || '') === key; });
  if (existing) return {created:false, id:key};

  const success = kind === 'LEARN_SUCCESS';
  const evidence = String(cmd.EVIDENCE || cmd.BLOCKER || cmd.NEXT_ACTION || '');
  const seedId = 'SEED_' + key;
  ccwfAppendByHeader_('35_INTERNAL_SEED_REGISTRY', {
    SEED_ID: seedId,
    APP_ID: String(cmd.PROJECT_ID || 'ALL_APPS'),
    SOURCE_TYPE: success ? 'VERIFIED_CHAT_SUCCESS' : 'CHAT_FAILURE_LESSON',
    SOURCE_IDS: String(cmd.CHAT_CMD_ID || ''),
    TOPIC_ID: 'WORKFLOW_OPERATION_LESSON',
    SEED_TEXT: String(cmd.USER_REQUEST_SUMMARY || '') + '\nEVIDENCE/LESSON: ' + evidence,
    INPUT_SCHEMA_VERSION: CCWF_VERSION,
    QUEENS_STATUS: success ? 'VERIFIED_SUCCESS' : 'FAILURE_EVIDENCE',
    STATUS: success ? 'SEED_PROMOTED_VERIFIED_SUCCESS' : 'SEED_FAILURE_PREVENTION_CANDIDATE',
    CREATED_AT: new Date(),
    UPDATED_AT: new Date(),
    EVIDENCE: evidence
  });

  ccwfAppendByHeader_('77_TEMPLATE_EVOLUTION_FACTORY', {
    EVOLVE_ID: key,
    TRIGGER: success ? 'VERIFIED_CHAT_SUCCESS' : 'SOLVED_OR_RECORDED_FAILURE',
    INPUT_RESULT: String(cmd.CHAT_CMD_ID || '') + '|' + String(cmd.TASK_ID || ''),
    MEASURE: 'repeatability|time_to_recovery|manual_intervention|runtime_evidence',
    BEST_COMPONENTS: success ? 'verified sequence|function|bridge|fixture|fallback|approval boundary' : 'LAST_GOOD|root cause|working fix if present',
    WEAK_COMPONENTS: success ? 'only regression-prone dimension' : String(cmd.BLOCKER || 'failed stage'),
    NEW_TEMPLATE: 'fork closest passing workflow; preserve LAST_GOOD; no blind rebuild',
    SOURCE_PACKS: seedId + '|83_PRECHECK|75_WORKFLOW_MAP',
    REPO_PATCH: 'minimal target adapter only if needed',
    APPS_SCRIPT_PATCH: 'script/webapp first; minimum function/trigger patch after exact lineage check',
    API_DELTA: 'Gemini/OpenAI conditional comparison only when stored data and deterministic path cannot resolve blocker or final-quality gap',
    PROMOTION_GATE: 'same fixture x2 + runtime/readback + regression + evidence',
    REGRESSION: 'before reuse by another app and after code/template change',
    WRITEBACK: '18|34|35|63|75|77|80|83|84 + target app map',
    STATUS: success ? 'CANDIDATE_FROM_VERIFIED_SUCCESS' : 'PREVENTION_CANDIDATE',
    VERSION: CCWF_VERSION,
    OWNER: 'CENTRAL_AGENT',
    NOTES: evidence
  });

  if (!success) {
    ccwfAppendByHeader_('83_TASK_PRECHECK_ASSET_MAP', {
      PRECHECK_RULE_ID: 'PCR_FAIL_' + String(cmd.CHAT_CMD_ID || ''),
      TASK_TYPE: 'REPEAT_FAILURE_PREVENTION',
      APP_SCOPE: String(cmd.PROJECT_ID || 'ALL'),
      PRIORITY: String(cmd.PRIORITY || 'P1'),
      REQUIRED_DATA_IDS: seedId,
      REQUIRED_FILE_CLASSES: 'SHEET|DOC|CODE_TEXT|ASSET',
      REQUIRED_GMAIL_CATEGORIES: '',
      REQUIRED_CENTRAL_TABS: '18|34|35|63|75|77|80|83',
      REQUIRED_GITHUB: 'target canonical repo',
      REQUIRED_SCRIPT_CONTRACTS: 'target function/trigger contract',
      REQUIRED_RUNTIME_EVIDENCE: 'same fixture x2 before VERIFIED',
      OPTIONAL_ASSETS: 'LAST_GOOD + previous success case',
      BLOCK_IF_MISSING: 'Y',
      OPENAI_CROSSCHECK: 'CONDITIONAL_ONLY',
      ON_FAIL_ACTION: 'DIAGNOSTIC_HOLD→ROOT_CAUSE→MIN_FIX→SAME_FIXTURE_RETEST',
      LAST_REVIEWED_AT: new Date(),
      STATUS: 'ACTIVE_PREVENTION_CANDIDATE',
      OWNER: 'CENTRAL_AGENT',
      VERSION: CCWF_VERSION,
      NOTES: evidence
    });
  }
  return {created:true, id:key, seedId:seedId};
}

function ccwfReviewInterruptedWork_() {
  const q = ccwfRows_('07_EXECUTION_QUEUE');
  const unresolved = q.filter(function(r) {
    const s = String(r.STATUS || '').toUpperCase();
    return !/COMPLETE|VERIFIED|CANCELLED|CLOSED/.test(s);
  });
  const p0 = unresolved.filter(function(r){ return String(r.PRIORITY || '').toUpperCase() === 'P0'; });
  return {
    total: unresolved.length,
    p0: p0.length,
    taskIds: unresolved.slice(-50).map(function(r){ return String(r.TASK_ID || ''); }).filter(Boolean),
    p0TaskIds: p0.slice(-30).map(function(r){ return String(r.TASK_ID || ''); }).filter(Boolean)
  };
}

function ccwfConditionalQa_(runId, unresolved) {
  const props = PropertiesService.getScriptProperties();
  if (props.getProperty('CENTRAL_EXTERNAL_AI_QA_ENABLED') !== 'true') return {status:'SKIPPED_POLICY_DISABLED'};
  if (!unresolved || unresolved.p0 < 1) return {status:'SKIPPED_NO_P0_GAP'};
  if (typeof runDualModelQaCompareV1 !== 'function') return {status:'SKIPPED_DUAL_QA_NOT_AVAILABLE'};
  try {
    return runDualModelQaCompareV1({
      runId: runId,
      goal: 'Classify unresolved P0 workflow blockers using only supplied central evidence. Recommend a minimum reusable fix and do not invent runtime proof.',
      unresolved: unresolved
    });
  } catch (e) {
    return {status:'DUAL_QA_ERROR', error:String(e)};
  }
}

function ccwfWriteRuntime_(runId, started, status, errorClass, details) {
  ccwfAppendByHeader_('80_DATA_RUNTIME_QA_LOG', {
    QA_ID: runId,
    RUN_ID: runId,
    APP_ID: 'P00_AGENT_CORE',
    FUNCTION_ID: 'runCentralChatWorkFactoryV1',
    INPUT_DATA_IDS: '18|34|63|75|77|83',
    OUTPUT_DATA_IDS: '07|35|59|77|80|83',
    RESULT_ID: runId,
    STARTED_AT: started,
    FINISHED_AT: new Date(),
    STATUS: status,
    READBACK_STATE: /PASS/.test(status) ? 'PASS_LOGGED_RUNTIME_X2_STILL_REQUIRED' : 'HOLD',
    QUALITY_SCORE: /PASS/.test(status) ? 90 : 0,
    ERROR_CLASS: errorClass || '',
    RETRY_COUNT: 0,
    EVIDENCE_POINTER: JSON.stringify(details || {}).slice(0, 12000),
    NEXT_ACTION: /PASS/.test(status) ? 'CONTINUE_FACTORY; PROMOTE ONLY AFTER SAME_FIXTURE_X2' : 'ROOT_CAUSE_MINIMUM_FIX_RETEST'
  });
}

function ccwfRows_(sheetName) {
  const sh = SpreadsheetApp.openById(CCWF_MASTER_ID).getSheetByName(sheetName);
  if (!sh) throw new Error('SHEET_NOT_FOUND:' + sheetName);
  const lr = sh.getLastRow(), lc = sh.getLastColumn();
  if (lr < 2 || lc < 1) return [];
  const v = sh.getRange(1,1,lr,lc).getValues();
  const h = v[0].map(String);
  return v.slice(1).filter(function(r){ return r.some(function(x){ return x !== ''; }); }).map(function(r){
    const o = {}; h.forEach(function(k,i){ o[k] = r[i]; }); return o;
  });
}

function ccwfAppendByHeader_(sheetName, payload) {
  if (typeof appendByHeader_ === 'function') {
    try { return appendByHeader_(sheetName, payload); } catch (e) {}
  }
  const sh = SpreadsheetApp.openById(CCWF_MASTER_ID).getSheetByName(sheetName);
  if (!sh) throw new Error('SHEET_NOT_FOUND:' + sheetName);
  const h = sh.getRange(1,1,1,sh.getLastColumn()).getValues()[0];
  sh.appendRow(h.map(function(k){ return Object.prototype.hasOwnProperty.call(payload,k) ? payload[k] : ''; }));
  return sh.getLastRow();
}
