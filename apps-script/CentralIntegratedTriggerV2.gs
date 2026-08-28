const CITV2_VERSION = 'CENTRAL_INTEGRATED_TRIGGER_V2_1_20260828';

/**
 * One integrated daily path: local notebook truth first, central Pack QA second.
 * This does not delete older triggers. If an older daily governor is physically
 * present, it is reported for exact diff/review instead of blindly removed.
 */
function installCentralIntegratedTriggersV2() {
  const ts = ScriptApp.getProjectTriggers();
  const handlers = ts.map(function(t){ return t.getHandlerFunction(); });
  const created = [];
  if (handlers.indexOf('runCentralWorkflowHealthTick') < 0) {
    ScriptApp.newTrigger('runCentralWorkflowHealthTick').timeBased().everyMinutes(30).create();
    created.push('runCentralWorkflowHealthTick');
  }
  if (handlers.indexOf('runCentralDailyIntegratedGovernorV1') < 0) {
    ScriptApp.newTrigger('runCentralDailyIntegratedGovernorV1').timeBased().atHour(9).everyDays(1).create();
    created.push('runCentralDailyIntegratedGovernorV1');
  }
  const legacyDailyPresent = handlers.indexOf('runCentralDailyQaAssetGovernor') >= 0;
  return {
    ok: true,
    created: created,
    legacyDailyPresent: legacyDailyPresent,
    state: legacyDailyPresent ? 'INTEGRATED_CREATED_LEGACY_TRIGGER_REVIEW_REQUIRED' : 'INTEGRATED_TRIGGER_READY_READBACK_REQUIRED',
    version: CITV2_VERSION
  };
}

function runCentralDailyIntegratedGovernorV1() {
  const started = new Date();
  const notebook = runCentralNotebookRuntimeHubPreflightV1({source:'DAILY_INTEGRATED_TRIGGER', deep:true});
  const centralQa = typeof runCentralDailyQaAssetGovernorV2 === 'function'
    ? runCentralDailyQaAssetGovernorV2()
    : runCentralDailyQaAssetGovernor();
  const notebookPass = notebook && notebook.status === 'PASS_PRECHECK';
  const qaPass = centralQa && /PASS/.test(String(centralQa.status || ''));
  const status = notebookPass && qaPass ? 'PASS_INTEGRATED_DAILY' : 'NEEDS_FIX_INTEGRATED_DAILY';

  appendByHeaderCompat_('1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI','80_DATA_RUNTIME_QA_LOG',{
    QA_ID:'INTEGRATED_'+Utilities.getUuid(), RUN_ID:(centralQa && centralQa.runId)||'', APP_ID:'P00_AGENT_CORE',
    FUNCTION_ID:'runCentralDailyIntegratedGovernorV1', INPUT_DATA_IDS:'NOTEBOOK_RUNTIME+CENTRAL_PACK_QA', OUTPUT_DATA_IDS:status,
    RESULT_ID:(centralQa && centralQa.runId)||'', STARTED_AT:started, FINISHED_AT:new Date(), STATUS:status,
    READBACK_STATE:notebookPass?'NOTEBOOK_PASS':'NOTEBOOK_FAIL', QUALITY_SCORE:(notebookPass&&qaPass)?100:0,
    ERROR_CLASS:[notebookPass?'':'NOTEBOOK_PREFLIGHT_FAIL',qaPass?'':'CENTRAL_QA_NOT_PASS'].filter(Boolean).join('|'), RETRY_COUNT:0,
    EVIDENCE_POINTER:JSON.stringify({notebook:notebook,centralQa:centralQa}).slice(0,12000),
    NEXT_ACTION:status==='PASS_INTEGRATED_DAILY'?'LEARN_REUSE_PUBLISH_ADAPTER_READBACK':'LAST_GOOD_ROOT_CAUSE_MIN_FIX_SAME_FIXTURE_RETEST'
  });
  return {status:status, notebook:notebook, centralQa:centralQa, version:CITV2_VERSION};
}

/** Standard gate to call at the beginning of any workflow that needs local/browser/App Script support. */
function centralWorkflowStartGateV1(context) {
  return runCentralNotebookRuntimeHubPreflightV1(context || {source:'WORKFLOW_START'});
}
