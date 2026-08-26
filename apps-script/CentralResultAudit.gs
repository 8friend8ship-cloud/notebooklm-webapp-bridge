const CENTRAL_MASTER_REGISTRY_ID = '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI';

function centralAuditResultV1(audit) {
  audit = audit || {};
  const now = new Date();
  const scores = audit.scores || {};
  const dims = [
    ['GOAL_ALIGNMENT',25,85],['PRACTICAL_USABILITY',20,80],['QUALITY_LEVEL',15,80],
    ['SOURCE_TRACEABILITY',10,90],['OUTPUT_COMPLETENESS',10,90],['FRONTAPP_FIT',10,80],['TECHNICAL_READBACK',10,100]
  ];
  let weighted = 0, weightTotal = 0, minFailed = [], hardFails = [];
  dims.forEach(function(d){
    const v = Number(scores[d[0]] || 0); weighted += v*d[1]; weightTotal += d[1]; if (v < d[2]) minFailed.push(d[0]);
  });
  ['MISSING_RESULT','READBACK_FAILED','WRONG_OUTPUT_TYPE','CRITICAL_SOURCE_MISMATCH','UNUSABLE_FOR_TARGET_FRONT','DUPLICATE_COLLISION']
    .forEach(function(k){ if ((audit.hardFails||[]).indexOf(k) >= 0) hardFails.push(k); });
  const overall = weightTotal ? Math.round(weighted/weightTotal) : 0;
  let status = 'PASS';
  if (!audit.resultId || !audit.readbackOk) status = 'HOLD_MISSING_EVIDENCE';
  else if (hardFails.length) status = 'REJECT';
  else if (overall < 82 || minFailed.length) status = overall >= 60 ? 'NEEDS_FIX' : 'REJECT';

  const result = {
    auditId: audit.auditId || ('AUDIT-CENTRAL-' + Utilities.formatDate(now, Session.getScriptTimeZone() || 'Asia/Seoul','yyyyMMdd-HHmmss')),
    auditAt: now, taskId: audit.taskId || '', appId: audit.appId || audit.projectKey || '', status: status,
    overallScore: overall, failedDimensions: minFailed, hardFails: hardFails,
    resultId: audit.resultId || '', resultUrl: audit.resultUrl || '', evidence: audit.evidence || '',
    goal: audit.goal || '', outputType: audit.outputType || '', variantKey: audit.variantKey || '',
    rootCause: audit.rootCause || '', fixApplied: audit.fixApplied || '', lesson: audit.lesson || ''
  };

  writeCentralAudit_(result, audit);
  if (status === 'PASS') promoteCentralResult_(result, audit);
  else if (status === 'NEEDS_FIX' || status === 'REJECT') writeFailureLearning_(result, audit);
  return result;
}

function writeCentralAudit_(r, raw) {
  appendByHeader_('84_OPENAI_CENTRAL_AUDIT', {
    AUDIT_ID:r.auditId, AUDIT_AT:r.auditAt, TASK_ID:r.taskId, APP_ID:r.appId,
    AUDITOR_SOURCE:'OPENAI_CHATGPT_CENTRAL_AGENT', CENTRAL_CLAIM:r.goal,
    EVIDENCE_IDS:r.evidence, OPENAI_CHECK:JSON.stringify(raw.scores||{}),
    MATCH_STATE:r.status==='PASS'?'MATCH':'PURPOSE_FIT_GAP', DISCREPANCY:(r.failedDimensions||[]).join('|')+(r.hardFails.length?'|'+r.hardFails.join('|'):''),
    CORRECTED_STATE:r.status, ACTION:r.status==='PASS'?'PROMOTE_SEED_OR_TEMPLATE':'ROOT_CAUSE_MINIMUM_FIX_RETEST',
    STATUS:r.status, API_MODE:'NO_OPENAI_API', REVIEW_METHOD:'CENTRAL_RESULT_AUDIT_V1', VERSION:'CENTRAL_RESULT_AUDIT_V1',
    RUNTIME_EVIDENCE:r.resultId, NOTES:JSON.stringify({score:r.overallScore,outputType:r.outputType,variantKey:r.variantKey})
  });
  appendByHeader_('80_DATA_RUNTIME_QA_LOG', {
    QA_ID:r.auditId, RUN_ID:r.taskId, APP_ID:r.appId, FUNCTION_ID:'centralAuditResultV1', INPUT_DATA_IDS:r.evidence,
    OUTPUT_DATA_IDS:r.resultId, RESULT_ID:r.resultId, STARTED_AT:r.auditAt, FINISHED_AT:r.auditAt,
    STATUS:r.status, READBACK_STATE:raw.readbackOk?'PASS':'FAIL', QUALITY_SCORE:r.overallScore,
    ERROR_CLASS:(r.hardFails||[]).join('|') || (r.failedDimensions||[]).join('|'), RETRY_COUNT:Number(raw.retryCount||0),
    EVIDENCE_POINTER:r.resultUrl||r.evidence, NEXT_ACTION:r.status==='PASS'?'PROMOTE':'FIX_AND_SAME_FIXTURE_RETEST'
  });
  appendByHeader_('71_MULTIMODAL_QA_HISTORY', {
    RUN_ID:r.taskId, RUN_AT:r.auditAt, REQUIREMENT_ID:r.goal, ROUTE_ID:r.outputType, TEMPLATE_ID:r.variantKey,
    INPUT_HASH:raw.inputHash||'', PRIMARY_RESULT:r.resultId, FALLBACK_USED:raw.fallbackUsed||'NO',
    TEXT_QA:raw.textQa||'', IMAGE_QA:raw.imageQa||'', VIDEO_QA:raw.videoQa||'', LINEAGE_QA:raw.lineageQa||'',
    READBACK_X2:raw.readbackOk?'PASS':'FAIL', SCORE:r.overallScore, ERROR_CLASS:(r.failedDimensions||[]).join('|'),
    FIX_APPLIED:r.fixApplied, LEARNED_RULE_OR_CHANGE_ID:r.lesson, STATUS:r.status
  });
}

function promoteCentralResult_(r, raw) {
  const seedText = raw.seedText || raw.resultSummary || '';
  appendByHeader_('35_INTERNAL_SEED_REGISTRY', {
    SEED_ID:'SEED_'+r.auditId, APP_ID:r.appId, SOURCE_TYPE:'CENTRAL_AUDIT_PASS', SOURCE_IDS:r.resultId,
    TOPIC_ID:raw.topicId||r.appId, SEED_TEXT:seedText, INPUT_SCHEMA_VERSION:'CENTRAL_RESULT_AUDIT_V1',
    QUEENS_STATUS:'AUDIT_PASS', STATUS:'SEED_PROMOTED_QA_PASS', CREATED_AT:r.auditAt, UPDATED_AT:r.auditAt,
    EVIDENCE:r.auditId+'|'+r.evidence
  });
  appendByHeader_('77_TEMPLATE_EVOLUTION_FACTORY', {
    APP_ID:r.appId, SOURCE_ID:r.resultId, STATUS:'CANDIDATE_FROM_AUDIT_PASS', SCORE:r.overallScore,
    EVIDENCE:r.auditId, UPDATED_AT:r.auditAt
  });
}

function writeFailureLearning_(r, raw) {
  appendByHeader_('37_QUEENS_RESEARCH_RESULTS', {
    RESULT_ID:'FAIL_'+r.auditId, APP_ID:r.appId, STATUS:r.status, EVIDENCE:r.evidence,
    ERROR:r.rootCause || (r.failedDimensions||[]).join('|'), NOTES:JSON.stringify({fix:r.fixApplied,lesson:r.lesson,score:r.overallScore})
  });
}

function appendByHeader_(sheetName, payload) {
  const ss = SpreadsheetApp.openById(CENTRAL_MASTER_REGISTRY_ID);
  const sh = ss.getSheetByName(sheetName); if (!sh) throw new Error('SHEET_NOT_FOUND:'+sheetName);
  const width = sh.getLastColumn(); const headers = sh.getRange(1,1,1,width).getValues()[0];
  const row = headers.map(function(h){ return Object.prototype.hasOwnProperty.call(payload,h) ? payload[h] : ''; });
  sh.appendRow(row); return sh.getLastRow();
}
