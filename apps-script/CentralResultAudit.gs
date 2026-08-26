const CENTRAL_MASTER_REGISTRY_ID = '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI';

function centralAuditResultV1(audit) {
  audit = audit || {};
  const now = new Date();
  const scores = audit.scores || {};
  const dims = [
    ['GOAL_ALIGNMENT',20,85],['PRACTICAL_USABILITY',15,80],['QUALITY_LEVEL',15,80],
    ['SOURCE_TRACEABILITY',10,90],['OUTPUT_COMPLETENESS',10,90],['FRONTAPP_FIT',10,80],
    ['TECHNICAL_READBACK',10,100],['REUSABILITY_LEARNING_VALUE',10,75]
  ];
  let weighted = 0, weightTotal = 0, minFailed = [], hardFails = [];
  dims.forEach(function(d){
    const v = Number(scores[d[0]] || 0); weighted += v*d[1]; weightTotal += d[1]; if (v < d[2]) minFailed.push(d[0]);
  });
  ['MISSING_RESULT','READBACK_FAILED','WRONG_OUTPUT_TYPE','CRITICAL_SOURCE_MISMATCH','UNUSABLE_FOR_TARGET_FRONT','DUPLICATE_COLLISION','CROSS_MODAL_CONFLICT']
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
    goal: audit.goal || '', outputType: audit.outputType || audit.artifactType || '', variantKey: audit.variantKey || '',
    rootCause: audit.rootCause || '', wrongAssumption: audit.wrongAssumption || '', fixApplied: audit.fixApplied || '',
    lesson: audit.lesson || '', preventionRule: audit.preventionRule || '', codePatchCandidate: audit.codePatchCandidate || '',
    functionPatchCandidate: audit.functionPatchCandidate || '', templateAdjustment: audit.templateAdjustment || ''
  };

  writeCentralAudit_(result, audit);
  writeLearningLoop_(result, audit);
  if (status === 'PASS') promoteCentralResult_(result, audit);
  else if (status === 'NEEDS_FIX' || status === 'REJECT') writeFailureLearning_(result, audit);
  return result;
}

function writeCentralAudit_(r, raw) {
  appendByHeader_('84_OPENAI_CENTRAL_AUDIT', {
    AUDIT_ID:r.auditId, AUDIT_AT:r.auditAt, TASK_ID:r.taskId, APP_ID:r.appId,
    AUDITOR_SOURCE:'OPENAI_CHATGPT_CENTRAL_AGENT', CENTRAL_CLAIM:r.goal,
    EVIDENCE_IDS:r.evidence, OPENAI_CHECK:JSON.stringify({scores:raw.scores||{},artifactChecks:raw.artifactChecks||{}}),
    MATCH_STATE:r.status==='PASS'?'MATCH':'PURPOSE_FIT_GAP', DISCREPANCY:(r.failedDimensions||[]).join('|')+(r.hardFails.length?'|'+r.hardFails.join('|'):''),
    CORRECTED_STATE:r.status, ACTION:r.status==='PASS'?'PROMOTE_SEED_TEMPLATE_PATTERN':'ROOT_CAUSE_MINIMUM_FIX_RETEST',
    STATUS:r.status, API_MODE:'NO_OPENAI_API', REVIEW_METHOD:'CENTRAL_RESULT_AUDIT_V1_1', VERSION:'CENTRAL_RESULT_AUDIT_V1_1',
    RUNTIME_EVIDENCE:r.resultId, NOTES:JSON.stringify({score:r.overallScore,artifactType:r.outputType,variantKey:r.variantKey,preventionRule:r.preventionRule})
  });
  appendByHeader_('80_DATA_RUNTIME_QA_LOG', {
    QA_ID:r.auditId, RUN_ID:r.taskId, APP_ID:r.appId, FUNCTION_ID:'centralAuditResultV1', INPUT_DATA_IDS:r.evidence,
    OUTPUT_DATA_IDS:r.resultId, RESULT_ID:r.resultId, STARTED_AT:r.auditAt, FINISHED_AT:r.auditAt,
    STATUS:r.status, READBACK_STATE:raw.readbackOk?'PASS':'FAIL', QUALITY_SCORE:r.overallScore,
    ERROR_CLASS:(r.hardFails||[]).join('|') || (r.failedDimensions||[]).join('|'), RETRY_COUNT:Number(raw.retryCount||0),
    EVIDENCE_POINTER:r.resultUrl||r.evidence, NEXT_ACTION:r.status==='PASS'?'PROMOTE_AND_LEARN':'FIX_AND_SAME_FIXTURE_RETEST'
  });
  appendByHeader_('71_MULTIMODAL_QA_HISTORY', {
    RUN_ID:r.taskId, RUN_AT:r.auditAt, REQUIREMENT_ID:r.goal, ROUTE_ID:r.outputType, TEMPLATE_ID:r.variantKey,
    INPUT_HASH:raw.inputHash||'', PRIMARY_RESULT:r.resultId, FALLBACK_USED:raw.fallbackUsed||'NO',
    TEXT_QA:raw.textQa||'', IMAGE_QA:raw.imageQa||'', VIDEO_QA:raw.videoQa||'', LINEAGE_QA:raw.lineageQa||'',
    READBACK_X2:raw.readbackOk?'PASS':'FAIL', SCORE:r.overallScore, ERROR_CLASS:(r.failedDimensions||[]).join('|'),
    FIX_APPLIED:r.fixApplied, LEARNED_RULE_OR_CHANGE_ID:r.lesson||r.preventionRule, STATUS:r.status
  });
}

function writeLearningLoop_(r, raw) {
  appendByHeader_('63_EVOLUTION_CHANGELOG', {
    APP_ID:r.appId, CHANGE_TYPE:r.status==='PASS'?'LEARNED_SUCCESS_PATTERN':'LEARNED_FAILURE_PATTERN',
    SOURCE_ID:r.resultId||r.taskId, STATUS:r.status, EVIDENCE:r.auditId+'|'+r.evidence,
    ROOT_CAUSE:r.rootCause, FIX:r.fixApplied, NOTES:JSON.stringify({wrongAssumption:r.wrongAssumption,preventionRule:r.preventionRule,codePatch:r.codePatchCandidate,functionPatch:r.functionPatchCandidate,templateAdjustment:r.templateAdjustment}),
    UPDATED_AT:r.auditAt
  });
  appendByHeader_('83_TASK_PRECHECK_ASSET_MAP', {
    APP_ID:r.appId, PROJECT_ID:r.appId, TASK_ID:r.taskId, ASSET_TYPE:'LESSON_PRECHECK_RULE',
    STATUS:r.status==='PASS'?'REUSABLE_SUCCESS_RULE':'BLOCK_REPEAT_UNTIL_FIXED',
    EVIDENCE:r.auditId+'|'+r.evidence,
    NOTES:JSON.stringify({artifactType:r.outputType,variantKey:r.variantKey,rootCause:r.rootCause,wrongAssumption:r.wrongAssumption,effectiveFix:r.fixApplied,preventionRule:r.preventionRule,templateAdjustment:r.templateAdjustment}),
    UPDATED_AT:r.auditAt
  });
  if (r.templateAdjustment || r.codePatchCandidate || r.functionPatchCandidate) {
    appendByHeader_('77_TEMPLATE_EVOLUTION_FACTORY', {
      APP_ID:r.appId, SOURCE_ID:r.resultId||r.taskId,
      STATUS:r.status==='PASS'?'LEARNED_CHANGE_VERIFIED':'PATCH_CANDIDATE_RETEST_REQUIRED',
      SCORE:r.overallScore, EVIDENCE:r.auditId,
      NOTES:JSON.stringify({templateAdjustment:r.templateAdjustment,codePatchCandidate:r.codePatchCandidate,functionPatchCandidate:r.functionPatchCandidate}),
      UPDATED_AT:r.auditAt
    });
  }
}

function centralPrecheckLessonsV1(projectKey, artifactType, errorSignature) {
  const ss = SpreadsheetApp.openById(CENTRAL_MASTER_REGISTRY_ID);
  const sh = ss.getSheetByName('83_TASK_PRECHECK_ASSET_MAP');
  if (!sh) throw new Error('SHEET_NOT_FOUND:83_TASK_PRECHECK_ASSET_MAP');
  const data = sh.getDataRange().getValues();
  if (data.length < 2) return {ok:true, matches:[]};
  const headers = data[0];
  const idx = {}; headers.forEach(function(h,i){idx[h]=i;});
  const matches = [];
  for (let i=data.length-1;i>=1 && matches.length<20;i--) {
    const row=data[i]; const app=String(row[idx.APP_ID]||row[idx.PROJECT_ID]||'');
    const notes=String(row[idx.NOTES]||''); const status=String(row[idx.STATUS]||'');
    if (projectKey && app && app!==projectKey) continue;
    if (artifactType && notes.indexOf(artifactType)<0) continue;
    if (errorSignature && notes.indexOf(errorSignature)<0) continue;
    matches.push({status:status,evidence:String(row[idx.EVIDENCE]||''),notes:notes,taskId:String(row[idx.TASK_ID]||'')});
  }
  const block = matches.some(function(m){return m.status==='BLOCK_REPEAT_UNTIL_FIXED';});
  return {ok:!block, decision:block?'DIAGNOSTIC_HOLD':'PROCEED', matches:matches};
}

function promoteCentralResult_(r, raw) {
  const seedText = raw.seedText || raw.resultSummary || '';
  appendByHeader_('35_INTERNAL_SEED_REGISTRY', {
    SEED_ID:'SEED_'+r.auditId, APP_ID:r.appId, SOURCE_TYPE:'CENTRAL_AUDIT_PASS', SOURCE_IDS:r.resultId,
    TOPIC_ID:raw.topicId||r.appId, SEED_TEXT:seedText, INPUT_SCHEMA_VERSION:'CENTRAL_RESULT_AUDIT_V1_1',
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
    ERROR:r.rootCause || (r.failedDimensions||[]).join('|'), NOTES:JSON.stringify({wrongAssumption:r.wrongAssumption,fix:r.fixApplied,lesson:r.lesson,preventionRule:r.preventionRule,score:r.overallScore})
  });
}

function appendByHeader_(sheetName, payload) {
  const ss = SpreadsheetApp.openById(CENTRAL_MASTER_REGISTRY_ID);
  const sh = ss.getSheetByName(sheetName); if (!sh) throw new Error('SHEET_NOT_FOUND:'+sheetName);
  const width = sh.getLastColumn(); const headers = sh.getRange(1,1,1,width).getValues()[0];
  const row = headers.map(function(h){ return Object.prototype.hasOwnProperty.call(payload,h) ? payload[h] : ''; });
  sh.appendRow(row); return sh.getLastRow();
}
