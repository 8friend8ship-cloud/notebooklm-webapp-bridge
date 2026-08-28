const CDWG_V2_VERSION = 'CENTRAL_DAILY_WORKFLOW_GOVERNOR_V2_API_FREE_FIRST_20260828';

function decideCentralPromotionV2_(baselineStatus, dualQaStatus) {
  const baselinePass = String(baselineStatus || '') === 'PASS';
  const dualPass = String(dualQaStatus || '') === 'PASS_BOTH_MODELS';
  const apiOffByPolicy = String(dualQaStatus || '') === 'API_QA_DISABLED_POLICY';
  const approved = baselinePass && (dualPass || apiOffByPolicy);
  return {
    approved: approved,
    approvalMode: approved ? (dualPass ? 'DUAL_QA' : 'API_FREE_BASELINE') : 'NONE',
    finalStatus: approved
      ? (dualPass ? 'PASS_APPROVED_FOR_PROMOTION_DUAL_QA' : 'PASS_APPROVED_FOR_PROMOTION_API_FREE')
      : (baselinePass ? String(dualQaStatus || 'QA_STATUS_MISSING') : 'NEEDS_FIX_BASELINE')
  };
}

/**
 * Canonical daily QA runner for the staged governor.
 * Stored-data deterministic QA is authoritative. External OpenAI/Gemini QA is
 * optional and may strengthen a result, but disabled API policy must not block
 * an otherwise valid API-free MVP/Seed/Template promotion.
 */
function runCentralDailyQaAssetGovernorV2() {
  const started = new Date();
  const runId = makeId_('DAILYV2');
  const health = runCentralWorkflowHealthTick();
  if (health.status !== 'PASS') {
    return finalizeDailyRun_(runId, started, 'FAILED_TEST', {health: health, version: CDWG_V2_VERSION}, 'HEALTH_GATE_FAILED');
  }

  const precheck = centralPrecheckLessonsSafe_('P00_AGENT_CORE', 'PERSONA_LANGUAGE_VOICE_SUBTITLE_ASSET', '');
  if (precheck.decision === 'DIAGNOSTIC_HOLD') {
    return finalizeDailyRun_(runId, started, 'DIAGNOSTIC_HOLD', {precheck: precheck, version: CDWG_V2_VERSION}, 'PRECHECK_BLOCKED_REPEAT');
  }

  const snapshot = buildPackInventorySnapshotV1_();
  const baseline = deterministicPackQaV1_(snapshot);
  const dualQa = runDualModelQaCompareV1({
    runId: runId,
    goal: 'Validate reusable persona/language/voice/subtitle/asset/front-pack workflow without fabricating runtime evidence. External AI is conditional, not required for an API-free baseline pass.',
    snapshot: snapshot,
    baseline: baseline
  });

  const decision = decideCentralPromotionV2_(baseline.status, dualQa.status);
  appendFactoryAbLog_(runId, snapshot, baseline, dualQa, decision.finalStatus);

  let promotion = {status: 'NOT_PROMOTED'};
  if (decision.approved) {
    promotion = promoteApprovedQaResultToSeedAssetV2({
      runId: runId,
      snapshot: snapshot,
      baseline: baseline,
      dualQa: dualQa,
      approvalMode: decision.approvalMode
    });
  }

  const catalog = exportFrontStaticCatalogSnapshotV1();
  const details = {snapshot: snapshot, baseline: baseline, dualQa: dualQa, decision: decision, promotion: promotion, catalog: catalog, version: CDWG_V2_VERSION};
  finalizeDailyRun_(runId, started, decision.finalStatus, details, decision.approved ? '' : 'PROMOTION_GATE_NOT_PASSED');
  return {runId: runId, status: decision.finalStatus, baseline: baseline, dualQa: dualQa, decision: decision, promotion: promotion, catalog: catalog, version: CDWG_V2_VERSION};
}

function promoteApprovedQaResultToSeedAssetV2(ctx) {
  const dualPass = ctx && ctx.dualQa && ctx.dualQa.status === 'PASS_BOTH_MODELS';
  const apiFreePass = ctx && ctx.dualQa && ctx.dualQa.status === 'API_QA_DISABLED_POLICY';
  if (!ctx || !ctx.runId || !ctx.baseline || ctx.baseline.status !== 'PASS' || (!dualPass && !apiFreePass)) {
    return {status: 'BLOCKED_NOT_APPROVED'};
  }

  const now = new Date();
  const mode = dualPass ? 'DUAL_QA' : 'API_FREE_BASELINE';
  const seedId = 'SEED_DAILY_PACK_' + ctx.runId;
  const assetId = 'ASSET_DAILY_PACK_' + ctx.runId;
  const qualityScore = dualPass
    ? Math.min(Number(ctx.dualQa.openai.score || 0), Number(ctx.dualQa.gemini.score || 0))
    : Number(ctx.baseline.score || 0);

  appendByHeaderSafe_(CDWG_TABS.seeds, {
    SEED_ID: seedId,
    APP_ID: 'ALL_FRONT_APPS',
    SOURCE_TYPE: dualPass ? 'CENTRAL_DUAL_QA_PASS' : 'CENTRAL_API_FREE_BASELINE_PASS',
    SOURCE_IDS: ctx.runId,
    TOPIC_ID: 'PERSONA_LANGUAGE_VOICE_SUBTITLE_ASSET',
    SEED_TEXT: JSON.stringify(ctx.snapshot),
    INPUT_SCHEMA_VERSION: CDWG_V2_VERSION,
    QUEENS_STATUS: 'AUDIT_PASS',
    STATUS: dualPass ? 'SEED_PROMOTED_DUAL_QA_PASS' : 'SEED_PROMOTED_API_FREE_PASS',
    CREATED_AT: now,
    UPDATED_AT: now,
    EVIDENCE: ctx.runId + '|' + mode + '|BASELINE_SCORE=' + qualityScore
  });

  appendByHeaderSafe_(CDWG_TABS.assets, {
    ASSET_RECORD_ID: assetId,
    APP_ID: 'ALL_FRONT_APPS',
    CONTENT_ID: ctx.runId,
    SEED_ID: seedId,
    ASSET_TYPE: 'PERSONA_LANGUAGE_VOICE_SUBTITLE_PACK_INDEX',
    SOURCE_ROLE: 'CENTRAL_DAILY_QA_PROMOTION',
    SOURCE_ID: ctx.runId,
    SOURCE_URL: '',
    SEARCH_URL: '',
    BARCODE_TAGS: 'PERSONA|LANGUAGE_PACK|VOICE_PACK|SUBTITLE_PACK|FRONT_ASSET|' + mode,
    SUMMARY_MEMO: 'Approved reusable central pack index. Actual media remains URL/pointer based.',
    KEYWORDS: 'persona,language,voice,subtitle,front asset',
    CONTENT_HASH: digestHex_(JSON.stringify(ctx.snapshot)),
    RIGHTS_USAGE: 'POINTER_ONLY_RIGHTS_REQUIRED_PER_SOURCE',
    VERIFIED_STATUS: dualPass ? 'PASS_DUAL_QA' : 'PASS_API_FREE_BASELINE',
    PLATFORM_READY_YN: 'YES_AFTER_PLATFORM_ADAPTER_QA',
    CREATED_AT: now,
    UPDATED_AT: now,
    NOTES: CDWG_V2_VERSION + '|' + mode
  });

  appendByHeaderSafe_(CDWG_TABS.templateFactory, {
    APP_ID: 'ALL_FRONT_APPS',
    SOURCE_ID: ctx.runId,
    STATUS: dualPass ? 'CANDIDATE_FROM_DUAL_QA_PASS' : 'CANDIDATE_FROM_API_FREE_BASELINE_PASS',
    SCORE: qualityScore,
    EVIDENCE: ctx.runId + '|' + mode,
    UPDATED_AT: now,
    NOTES: JSON.stringify({seedId: seedId, assetId: assetId, version: CDWG_V2_VERSION, mode: mode})
  });

  return {status: 'PROMOTED', seedId: seedId, assetId: assetId, approvalMode: mode, score: qualityScore};
}
