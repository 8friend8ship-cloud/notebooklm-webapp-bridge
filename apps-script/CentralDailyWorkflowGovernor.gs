const CDWG_MASTER_REGISTRY_ID = '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI';
const CDWG_CENTRAL_FOLDER_ID = '1mAu8N8EfThhkM3D-axvOLi0pY4ryQKcS';
const CDWG_VERSION = 'CENTRAL_DAILY_WORKFLOW_GOVERNOR_V1_20260828';

const CDWG_TABS = {
  triggers: '36_AUTOMATION_TRIGGER_REGISTRY',
  seeds: '35_INTERNAL_SEED_REGISTRY',
  persona: '42_PERSONA_ROUTING_MASTER',
  personaData: '47_PERSONA_DATA_ROUTING',
  assets: '48_SEARCHABLE_ASSET_INDEX',
  platformLedger: '49_PLATFORM_DATA_LEDGER',
  workflow: '56_FRONTAPP_WORKFLOW_MAP',
  bus: '59_DATA_INTELLIGENCE_BUS',
  subscriptions: '60_APP_DATA_SUBSCRIPTION',
  contracts: '61_BACKEND_FUNCTION_CONTRACT',
  evolution: '63_EVOLUTION_CHANGELOG',
  factory: '66_FACTORY_PRODUCTION_CONTROL',
  ab: '67_FACTORY_QA_AB_LOG',
  qaHistory: '71_MULTIMODAL_QA_HISTORY',
  assetFactory: '76_ASSET_PACK_FACTORY',
  templateFactory: '77_TEMPLATE_EVOLUTION_FACTORY',
  runtimeQa: '80_DATA_RUNTIME_QA_LOG',
  precheck: '83_TASK_PRECHECK_ASSET_MAP',
  openaiAudit: '84_OPENAI_CENTRAL_AUDIT',
  publishUrls: '33_FRONT_PUBLISH_URL_REGISTRY'
};

/**
 * Installation is intentionally explicit. Calling this function creates only
 * the two governor triggers and never deletes unrelated triggers.
 * Runtime completion must still be proven by trigger readback + actual results.
 */
function installCentralDailyWorkflowGovernorTriggersV1() {
  const existing = ScriptApp.getProjectTriggers().map(function(t) { return t.getHandlerFunction(); });
  const created = [];
  if (existing.indexOf('runCentralWorkflowHealthTick') < 0) {
    ScriptApp.newTrigger('runCentralWorkflowHealthTick').timeBased().everyMinutes(30).create();
    created.push('runCentralWorkflowHealthTick');
  }
  if (existing.indexOf('runCentralDailyQaAssetGovernor') < 0) {
    ScriptApp.newTrigger('runCentralDailyQaAssetGovernor').timeBased().atHour(9).everyDays(1).create();
    created.push('runCentralDailyQaAssetGovernor');
  }
  return {ok: true, created: created, state: created.length ? 'TRIGGERS_CREATED_RUNTIME_READBACK_REQUIRED' : 'TRIGGERS_ALREADY_PRESENT_READBACK_REQUIRED'};
}

function runCentralWorkflowHealthTick() {
  const started = new Date();
  const required = Object.keys(CDWG_TABS).map(function(k) { return CDWG_TABS[k]; });
  const ss = SpreadsheetApp.openById(CDWG_MASTER_REGISTRY_ID);
  const missing = required.filter(function(name) { return !ss.getSheetByName(name); });
  const precheck = centralPrecheckLessonsSafe_('P00_AGENT_CORE', 'CENTRAL_WORKFLOW_GOVERNOR', '');
  const status = missing.length ? 'FAILED_TEST' : (precheck.decision === 'DIAGNOSTIC_HOLD' ? 'DIAGNOSTIC_HOLD' : 'PASS');
  const result = {
    runId: makeId_('HEALTH'),
    startedAt: started,
    finishedAt: new Date(),
    status: status,
    missingSheets: missing,
    precheck: precheck,
    version: CDWG_VERSION
  };
  appendByHeaderSafe_(CDWG_TABS.runtimeQa, {
    QA_ID: result.runId,
    RUN_ID: result.runId,
    APP_ID: 'P00_AGENT_CORE',
    FUNCTION_ID: 'runCentralWorkflowHealthTick',
    STARTED_AT: started,
    FINISHED_AT: result.finishedAt,
    STATUS: status,
    READBACK_STATE: missing.length ? 'FAIL' : 'PASS',
    QUALITY_SCORE: missing.length ? 0 : 100,
    ERROR_CLASS: missing.join('|'),
    RETRY_COUNT: 0,
    EVIDENCE_POINTER: 'MASTER_REGISTRY:' + CDWG_MASTER_REGISTRY_ID,
    NEXT_ACTION: status === 'PASS' ? 'CONTINUE_DAILY_GOVERNOR' : 'ROOT_CAUSE_MINIMUM_FIX_RETEST'
  });
  return result;
}

/**
 * Daily deep loop:
 * PRE_CHECK -> pack inventory -> deterministic MVP QA -> optional OpenAI+Gemini
 * A/B QA -> promotion -> URL/catalog snapshot -> history/evolution writeback.
 * No public publishing is executed here. Platform adapters must call
 * registerPlatformPublishUrlV1 only after an actual platform ID/URL is returned.
 */
function runCentralDailyQaAssetGovernor() {
  const started = new Date();
  const runId = makeId_('DAILY');
  const health = runCentralWorkflowHealthTick();
  if (health.status !== 'PASS') {
    return finalizeDailyRun_(runId, started, 'FAILED_TEST', {health: health}, 'HEALTH_GATE_FAILED');
  }

  const precheck = centralPrecheckLessonsSafe_('P00_AGENT_CORE', 'PERSONA_LANGUAGE_VOICE_SUBTITLE_ASSET', '');
  if (precheck.decision === 'DIAGNOSTIC_HOLD') {
    return finalizeDailyRun_(runId, started, 'DIAGNOSTIC_HOLD', {precheck: precheck}, 'PRECHECK_BLOCKED_REPEAT');
  }

  const snapshot = buildPackInventorySnapshotV1_();
  const baseline = deterministicPackQaV1_(snapshot);
  const dualQa = runDualModelQaCompareV1({
    runId: runId,
    goal: 'Validate reusable persona/language/voice/subtitle/asset/front-pack workflow without fabricating runtime evidence.',
    snapshot: snapshot,
    baseline: baseline
  });

  const approved = baseline.status === 'PASS' && dualQa.status === 'PASS_BOTH_MODELS';
  const finalStatus = approved ? 'PASS_APPROVED_FOR_PROMOTION' :
    (baseline.status !== 'PASS' ? 'NEEDS_FIX_BASELINE' : dualQa.status);

  appendFactoryAbLog_(runId, snapshot, baseline, dualQa, finalStatus);

  let promotion = {status: 'NOT_PROMOTED'};
  if (approved) {
    promotion = promoteApprovedQaResultToSeedAssetV1({
      runId: runId,
      snapshot: snapshot,
      baseline: baseline,
      dualQa: dualQa
    });
  }

  const catalog = exportFrontStaticCatalogSnapshotV1();
  const details = {snapshot: snapshot, baseline: baseline, dualQa: dualQa, promotion: promotion, catalog: catalog};
  finalizeDailyRun_(runId, started, finalStatus, details, approved ? '' : 'PROMOTION_GATE_NOT_PASSED');
  return {runId: runId, status: finalStatus, baseline: baseline, dualQa: dualQa, promotion: promotion, catalog: catalog};
}

function buildPackInventorySnapshotV1_() {
  const persona = rowsAsObjects_(CDWG_TABS.persona);
  const personaData = rowsAsObjects_(CDWG_TABS.personaData);
  const assets = rowsAsObjects_(CDWG_TABS.assets);
  const subs = rowsAsObjects_(CDWG_TABS.subscriptions);
  const platform = rowsAsObjects_(CDWG_TABS.platformLedger);

  const activePersona = persona.filter(function(r) { return text_(r.STATUS).indexOf('ACTIVE') >= 0 || text_(r.CENTRAL_FILTER_STATUS).indexOf('PASS') >= 0; });
  const packRoutes = personaData.filter(function(r) {
    const need = text_(r.NEED_TYPE) + '|' + text_(r.REQUIRED_DATA) + '|' + text_(r.NOTES);
    return /PERSONA|LANGUAGE|VOICE|SUBTITLE|ASSET|PLATFORM/i.test(need);
  });
  const verifiedAssets = assets.filter(function(r) {
    return /PASS|VERIFIED|READY/i.test(text_(r.VERIFIED_STATUS)) && !!text_(r.SOURCE_URL || r.DRIVE_URL);
  });
  const frontApps = subs.filter(function(r) { return text_(r.STATUS) && !/DISABLED|RETIRED/i.test(text_(r.STATUS)); });
  const published = platform.filter(function(r) {
    return /PUBLISHED|VERIFIED|LIVE/i.test(text_(r.PUBLISH_STATUS)) && !!text_(r.PLATFORM_URL);
  });

  return {
    capturedAt: new Date().toISOString(),
    personaRoutes: activePersona.length,
    packRoutes: packRoutes.length,
    verifiedAssets: verifiedAssets.length,
    subscribedFrontApps: frontApps.length,
    publishedUrls: published.length,
    missingCritical: {
      persona: activePersona.length === 0,
      packRouting: packRoutes.length === 0,
      frontSubscriptions: frontApps.length === 0
    },
    sampleAssetIds: verifiedAssets.slice(0, 25).map(function(r) { return r.ASSET_RECORD_ID; }).filter(Boolean),
    sampleFrontApps: frontApps.slice(0, 25).map(function(r) { return r.APP_ID; }).filter(Boolean)
  };
}

function deterministicPackQaV1_(snapshot) {
  const failures = [];
  if (snapshot.missingCritical.persona) failures.push('PERSONA_ROUTE_MISSING');
  if (snapshot.missingCritical.packRouting) failures.push('PACK_ROUTE_MISSING');
  if (snapshot.missingCritical.frontSubscriptions) failures.push('FRONT_SUBSCRIPTION_MISSING');
  if (snapshot.verifiedAssets < 1) failures.push('NO_VERIFIED_ASSET_POINTER');
  let score = 100;
  score -= failures.length * 20;
  if (snapshot.publishedUrls < 1) score -= 5; // not a hard fail: actual publication may legitimately be pending.
  score = Math.max(0, score);
  return {
    status: failures.length ? 'NEEDS_FIX' : 'PASS',
    score: score,
    failures: failures,
    rules: ['NO_FAKE_URL', 'RIGHTS_AND_LINEAGE_REQUIRED', 'FRONT_CACHE_GITHUB_STATIC_FIRST', 'API_ONLY_AFTER_BASELINE_GAP']
  };
}

/**
 * External AI QA is disabled by default. Enable only after explicit policy/secret
 * setup by setting CENTRAL_EXTERNAL_AI_QA_ENABLED=true in Script Properties.
 * Both providers must return PASS and score >= 82; central deterministic QA remains authoritative.
 */
function runDualModelQaCompareV1(payload) {
  const props = PropertiesService.getScriptProperties();
  if (props.getProperty('CENTRAL_EXTERNAL_AI_QA_ENABLED') !== 'true') {
    return {status: 'API_QA_DISABLED_POLICY', openai: null, gemini: null, approval: false};
  }
  const openaiKey = props.getProperty('OPENAI_API_KEY');
  const geminiKey = props.getProperty('GEMINI_API_KEY');
  const openaiModel = props.getProperty('OPENAI_QA_MODEL');
  const geminiModel = props.getProperty('GEMINI_QA_MODEL');
  if (!openaiKey || !geminiKey || !openaiModel || !geminiModel) {
    return {status: 'BLOCKED_ACCESS_MISSING_AI_QA_CONFIG', openai: null, gemini: null, approval: false};
  }

  const compact = JSON.stringify(payload).slice(0, 60000);
  const prompt = [
    'You are a QA auditor. Evaluate only the supplied evidence. Do not invent runtime proof.',
    'PASS only when the pack is useful, traceable, reusable, and safe for front-app reuse.',
    'Return the requested JSON schema.',
    compact
  ].join('\n');

  const openai = callOpenAIQaV1_(openaiKey, openaiModel, prompt);
  const gemini = callGeminiQaV1_(geminiKey, geminiModel, prompt);
  const bothPass = isModelQaPass_(openai) && isModelQaPass_(gemini);
  const status = bothPass ? 'PASS_BOTH_MODELS' : 'NEEDS_FIX_MODEL_DISAGREEMENT_OR_FAIL';

  appendByHeaderSafe_(CDWG_TABS.openaiAudit, {
    AUDIT_ID: makeId_('DUALQA'),
    AUDIT_AT: new Date(),
    TASK_ID: payload.runId || '',
    APP_ID: 'P00_AGENT_CORE',
    AUDITOR_SOURCE: 'OPENAI_GEMINI_DUAL_QA',
    CENTRAL_CLAIM: payload.goal || '',
    EVIDENCE_IDS: payload.runId || '',
    OPENAI_CHECK: JSON.stringify(openai),
    MATCH_STATE: bothPass ? 'MATCH' : 'PURPOSE_FIT_GAP',
    DISCREPANCY: bothPass ? '' : JSON.stringify({openai: openai, gemini: gemini}).slice(0, 12000),
    CORRECTED_STATE: status,
    ACTION: bothPass ? 'PROMOTE_SEED_TEMPLATE_PATTERN' : 'ROOT_CAUSE_MINIMUM_FIX_RETEST',
    STATUS: status,
    API_MODE: 'OPENAI_RESPONSES+GEMINI_INTERACTIONS_CONDITIONAL',
    REVIEW_METHOD: CDWG_VERSION,
    VERSION: CDWG_VERSION,
    RUNTIME_EVIDENCE: payload.runId || '',
    NOTES: JSON.stringify({gemini: gemini}).slice(0, 12000)
  });
  return {status: status, openai: openai, gemini: gemini, approval: bothPass};
}

function qaSchemaV1_() {
  return {
    type: 'object',
    additionalProperties: false,
    properties: {
      decision: {type: 'string', enum: ['PASS', 'NEEDS_FIX', 'REJECT']},
      score: {type: 'integer', minimum: 0, maximum: 100},
      issues: {type: 'array', items: {type: 'string'}},
      reusable: {type: 'boolean'},
      evidence_complete: {type: 'boolean'},
      next_action: {type: 'string'}
    },
    required: ['decision', 'score', 'issues', 'reusable', 'evidence_complete', 'next_action']
  };
}

function callOpenAIQaV1_(apiKey, model, prompt) {
  const body = {
    model: model,
    input: prompt,
    store: false,
    text: {format: {type: 'json_schema', name: 'central_qa_result', strict: true, schema: qaSchemaV1_()}}
  };
  try {
    const resp = UrlFetchApp.fetch('https://api.openai.com/v1/responses', {
      method: 'post', contentType: 'application/json', muteHttpExceptions: true,
      headers: {Authorization: 'Bearer ' + apiKey}, payload: JSON.stringify(body)
    });
    const code = resp.getResponseCode();
    const json = JSON.parse(resp.getContentText() || '{}');
    if (code < 200 || code >= 300) return {provider: 'OPENAI', ok: false, http: code, error: compactError_(json)};
    const txt = extractOpenAIOutputText_(json);
    const parsed = JSON.parse(txt);
    parsed.provider = 'OPENAI'; parsed.ok = true; parsed.http = code; return parsed;
  } catch (e) {
    return {provider: 'OPENAI', ok: false, error: String(e)};
  }
}

function callGeminiQaV1_(apiKey, model, prompt) {
  const body = {
    model: model,
    input: prompt,
    store: false,
    response_format: {type: 'text', mime_type: 'application/json', schema: qaSchemaV1_()}
  };
  try {
    const resp = UrlFetchApp.fetch('https://generativelanguage.googleapis.com/v1beta/interactions', {
      method: 'post', contentType: 'application/json', muteHttpExceptions: true,
      headers: {'x-goog-api-key': apiKey}, payload: JSON.stringify(body)
    });
    const code = resp.getResponseCode();
    const json = JSON.parse(resp.getContentText() || '{}');
    if (code < 200 || code >= 300) return {provider: 'GEMINI', ok: false, http: code, error: compactError_(json)};
    const txt = extractGeminiOutputText_(json);
    const parsed = JSON.parse(txt);
    parsed.provider = 'GEMINI'; parsed.ok = true; parsed.http = code; return parsed;
  } catch (e) {
    return {provider: 'GEMINI', ok: false, error: String(e)};
  }
}

function extractOpenAIOutputText_(json) {
  if (json.output_text) return json.output_text;
  const out = json.output || [];
  for (let i = 0; i < out.length; i++) {
    const content = out[i].content || [];
    for (let j = 0; j < content.length; j++) {
      if (content[j].text) return content[j].text;
    }
  }
  throw new Error('OPENAI_OUTPUT_TEXT_NOT_FOUND');
}

function extractGeminiOutputText_(json) {
  if (json.output_text) return json.output_text;
  const steps = json.steps || [];
  for (let i = steps.length - 1; i >= 0; i--) {
    if (steps[i].type !== 'model_output') continue;
    const content = steps[i].content || [];
    for (let j = 0; j < content.length; j++) {
      if (content[j].type === 'text' && content[j].text) return content[j].text;
    }
  }
  const outputs = json.outputs || [];
  for (let k = 0; k < outputs.length; k++) if (outputs[k].text) return outputs[k].text;
  throw new Error('GEMINI_OUTPUT_TEXT_NOT_FOUND');
}

function isModelQaPass_(x) {
  return !!x && x.ok === true && x.decision === 'PASS' && Number(x.score || 0) >= 82 && x.reusable === true && x.evidence_complete === true;
}

function promoteApprovedQaResultToSeedAssetV1(ctx) {
  if (!ctx || !ctx.runId || !ctx.dualQa || ctx.dualQa.status !== 'PASS_BOTH_MODELS' || !ctx.baseline || ctx.baseline.status !== 'PASS') {
    return {status: 'BLOCKED_NOT_APPROVED'};
  }
  const now = new Date();
  const seedId = 'SEED_DAILY_PACK_' + ctx.runId;
  const assetId = 'ASSET_DAILY_PACK_' + ctx.runId;
  appendByHeaderSafe_(CDWG_TABS.seeds, {
    SEED_ID: seedId,
    APP_ID: 'ALL_FRONT_APPS',
    SOURCE_TYPE: 'CENTRAL_DUAL_QA_PASS',
    SOURCE_IDS: ctx.runId,
    TOPIC_ID: 'PERSONA_LANGUAGE_VOICE_SUBTITLE_ASSET',
    SEED_TEXT: JSON.stringify(ctx.snapshot),
    INPUT_SCHEMA_VERSION: CDWG_VERSION,
    QUEENS_STATUS: 'AUDIT_PASS',
    STATUS: 'SEED_PROMOTED_QA_PASS',
    CREATED_AT: now,
    UPDATED_AT: now,
    EVIDENCE: ctx.runId + '|OPENAI_GEMINI_PASS'
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
    BARCODE_TAGS: 'PERSONA|LANGUAGE_PACK|VOICE_PACK|SUBTITLE_PACK|FRONT_ASSET|QA_PASS',
    SUMMARY_MEMO: 'Approved reusable central pack index. Actual media remains URL/pointer based.',
    KEYWORDS: 'persona,language,voice,subtitle,front asset',
    CONTENT_HASH: digestHex_(JSON.stringify(ctx.snapshot)),
    RIGHTS_USAGE: 'POINTER_ONLY_RIGHTS_REQUIRED_PER_SOURCE',
    VERIFIED_STATUS: 'PASS_DUAL_QA',
    PLATFORM_READY_YN: 'YES_AFTER_PLATFORM_ADAPTER_QA',
    CREATED_AT: now,
    UPDATED_AT: now,
    NOTES: CDWG_VERSION
  });
  appendByHeaderSafe_(CDWG_TABS.templateFactory, {
    APP_ID: 'ALL_FRONT_APPS', SOURCE_ID: ctx.runId,
    STATUS: 'CANDIDATE_FROM_DUAL_QA_PASS', SCORE: Math.min(Number(ctx.dualQa.openai.score || 0), Number(ctx.dualQa.gemini.score || 0)),
    EVIDENCE: ctx.runId, UPDATED_AT: now,
    NOTES: JSON.stringify({seedId: seedId, assetId: assetId, version: CDWG_VERSION})
  });
  return {status: 'PROMOTED', seedId: seedId, assetId: assetId};
}

/** Register only real platform results. Empty/fabricated URLs are rejected. */
function registerPlatformPublishUrlV1(p) {
  p = p || {};
  if (!p.publishId || !p.appId || !p.platformId || !p.platformUrl || !/^https?:\/\//i.test(p.platformUrl)) {
    throw new Error('REAL_PLATFORM_ID_AND_URL_REQUIRED');
  }
  const now = new Date();
  appendByHeaderSafe_(CDWG_TABS.platformLedger, {
    PLATFORM_RECORD_ID: p.platformRecordId || ('PLATREC_' + p.publishId),
    PUBLISH_ID: p.publishId,
    APP_ID: p.appId,
    CONTENT_ID: p.contentId || '',
    SEED_ID: p.seedId || '',
    PLATFORM_ID: p.platformId,
    CHANNEL_ID: p.channelId || '',
    PLATFORM_CONTENT_ID: p.platformContentId || p.publishId,
    PLATFORM_URL: p.platformUrl,
    PLATFORM_DATA_JSON: JSON.stringify(p.platformData || {}),
    TITLE_VARIANT: p.title || '',
    CAPTION_OR_BODY_VARIANT: p.body || '',
    CTA_VARIANT: p.cta || '',
    TAGS: p.tags || '',
    LOCALE: p.locale || 'ko-KR',
    PUBLISH_MODE: p.publishMode || 'OFFICIAL_API_FIRST',
    PUBLISH_STATUS: p.publishStatus || 'PUBLISHED_READBACK_REQUIRED',
    PUBLISHED_AT: p.publishedAt || now,
    METRIC_LAST_SYNC_AT: '',
    METRIC_SNAPSHOT_JSON: '',
    SOURCE_DRIVE_IDS: p.sourceDriveIds || '',
    CREATED_AT: now,
    UPDATED_AT: now,
    NOTES: CDWG_VERSION
  });
  appendByHeaderSafe_(CDWG_TABS.publishUrls, {
    PUBLISH_ID: p.publishId,
    CONTENT_ID: p.contentId || '',
    SEED_ID: p.seedId || '',
    RESULT_ID: p.resultId || '',
    PARENT_PUBLISH_ID: p.parentPublishId || '',
    APP_ID: p.appId,
    PUBLISH_LEVEL: p.publishLevel || 'PLATFORM',
    SLUG: p.slug || '',
    PUBLIC_URL: p.platformUrl,
    API_READ_URL: p.apiReadUrl || '',
    DRIVE_SOURCE_ID: p.sourceDriveIds || '',
    GITHUB_VERSION: p.githubVersion || '',
    INDEX_POLICY: p.indexPolicy || 'INDEX_IF_VERIFIED',
    HTTP_STATUS: p.httpStatus || '',
    DEPLOY_STATUS: p.publishStatus || 'PUBLISHED_READBACK_REQUIRED',
    GOOGLE_INDEX_STATUS: p.googleIndexStatus || 'NOT_CHECKED',
    CANONICAL_URL: p.canonicalUrl || p.platformUrl,
    VERIFY_COUNT: Number(p.verifyCount || 0),
    LAST_ERROR: '',
    CREATED_AT: now,
    UPDATED_AT: now,
    NOTES: CDWG_VERSION
  });
  return {ok: true, publishId: p.publishId, url: p.platformUrl};
}

/**
 * Creates/updates a compact Drive JSON snapshot for fronts. GitHub recurring
 * sync is intentionally not attempted unless a separately approved secret/app
 * integration is configured; this prevents embedding PATs in code/Drive.
 */
function exportFrontStaticCatalogSnapshotV1() {
  const assets = rowsAsObjects_(CDWG_TABS.assets).filter(function(r) {
    return /PASS|VERIFIED|READY/i.test(text_(r.VERIFIED_STATUS)) && (!!text_(r.SOURCE_URL) || !!text_(r.DRIVE_URL));
  });
  const pubs = rowsAsObjects_(CDWG_TABS.platformLedger).filter(function(r) {
    return /PUBLISHED|VERIFIED|LIVE/i.test(text_(r.PUBLISH_STATUS)) && /^https?:\/\//i.test(text_(r.PLATFORM_URL));
  });
  const catalog = {
    schema: 'CENTRAL_FRONT_STATIC_CATALOG_V1',
    generatedAt: new Date().toISOString(),
    sourceRegistry: CDWG_MASTER_REGISTRY_ID,
    rule: 'FRONT_STATIC_FIRST_GITHUB_OR_DRIVE_URL_POINTERS_ONLY',
    assets: assets.slice(-500).map(function(r) {
      return {assetId:r.ASSET_RECORD_ID, appId:r.APP_ID, seedId:r.SEED_ID, type:r.ASSET_TYPE, url:r.SOURCE_URL || r.DRIVE_URL, tags:r.BARCODE_TAGS, rights:r.RIGHTS_USAGE, status:r.VERIFIED_STATUS};
    }),
    publications: pubs.slice(-500).map(function(r) {
      return {publishId:r.PUBLISH_ID, appId:r.APP_ID, platformId:r.PLATFORM_ID, url:r.PLATFORM_URL, locale:r.LOCALE, status:r.PUBLISH_STATUS};
    })
  };
  const folder = DriveApp.getFolderById(PropertiesService.getScriptProperties().getProperty('CENTRAL_STATIC_CATALOG_FOLDER_ID') || CDWG_CENTRAL_FOLDER_ID);
  const name = 'central_front_static_catalog.json';
  const json = JSON.stringify(catalog, null, 2);
  const files = folder.getFilesByName(name);
  let f;
  if (files.hasNext()) { f = files.next(); f.setContent(json); }
  else { f = folder.createFile(name, json, MimeType.PLAIN_TEXT); }
  return {status: 'DRIVE_SNAPSHOT_WRITTEN_GITHUB_SYNC_SEPARATE', fileId: f.getId(), url: f.getUrl(), entries: catalog.assets.length + catalog.publications.length, hash: digestHex_(json)};
}

function appendFactoryAbLog_(runId, snapshot, baseline, dualQa, decision) {
  appendByHeaderSafe_(CDWG_TABS.ab, {
    RUN_ID: runId,
    RUN_AT: new Date(),
    APP_ID: 'ALL_FRONT_APPS',
    FRONT_FIXTURE: 'PERSONA_LANGUAGE_VOICE_SUBTITLE_ASSET_PACK',
    MODE_A: 'STORED_API_FREE_MVP',
    MODE_B: 'OPENAI_GEMINI_DUAL_QA_CONDITIONAL',
    QUEENS_COUNT: snapshot.packRoutes,
    SEED_COUNT: '', T1_COUNT: '', T2_COUNT: '',
    COVERAGE_A: baseline.score,
    COVERAGE_B: dualQa.status === 'PASS_BOTH_MODELS' ? 100 : 'PENDING_OR_FAIL',
    QUALITY_A: baseline.score,
    QUALITY_B: dualQa.status === 'PASS_BOTH_MODELS' ? Math.min(dualQa.openai.score, dualQa.gemini.score) : 'PENDING_OR_FAIL',
    LATENCY_A_MS: 'LOCAL_SHEETS',
    LATENCY_B_MS: 'PROVIDER_RESPONSE',
    TRAFFIC_A: '0_API_CALL',
    TRAFFIC_B: dualQa.status === 'PASS_BOTH_MODELS' ? '2_MODEL_CALLS' : '0_OR_FAILED_CALL',
    DUP_RATE: 'HASH_URL_DEDUPE_REQUIRED',
    ERROR_CODE: baseline.failures.join('|') || (dualQa.status === 'PASS_BOTH_MODELS' ? 'NONE' : dualQa.status),
    MARKET_TREND_MATCH: 'TREND_WAREHOUSE_REUSE_REQUIRED',
    DECISION: decision,
    PATCH_ID: CDWG_VERSION,
    RETEST_STATUS: decision === 'PASS_APPROVED_FOR_PROMOTION' ? 'PASS' : 'RETEST_REQUIRED'
  });
}

function finalizeDailyRun_(runId, started, status, details, errorClass) {
  const now = new Date();
  appendByHeaderSafe_(CDWG_TABS.runtimeQa, {
    QA_ID: runId, RUN_ID: runId, APP_ID: 'P00_AGENT_CORE', FUNCTION_ID: 'runCentralDailyQaAssetGovernor',
    INPUT_DATA_IDS: '42|47|48|49|59|60|66|67', OUTPUT_DATA_IDS: status,
    RESULT_ID: runId, STARTED_AT: started, FINISHED_AT: now, STATUS: status,
    READBACK_STATE: /PASS/.test(status) ? 'PASS' : 'PENDING_OR_FAIL', QUALITY_SCORE: /PASS/.test(status) ? 100 : 0,
    ERROR_CLASS: errorClass || '', RETRY_COUNT: 0,
    EVIDENCE_POINTER: JSON.stringify(details || {}).slice(0, 12000),
    NEXT_ACTION: /PASS/.test(status) ? 'LEARN_AND_REUSE' : 'ROOT_CAUSE_MINIMUM_FIX_SAME_FIXTURE_RETEST'
  });
  appendByHeaderSafe_(CDWG_TABS.evolution, {
    CHANGE_ID: 'CHG_' + runId, CREATED_AT: now, SOURCE_RESEARCH_ID: runId, APP_ID: 'ALL_FRONT_APPS',
    CHANGE_LEVEL: 'WORKFLOW', CHANGE_TYPE: 'DAILY_PERSONA_ASSET_QA_GOVERNOR',
    BEFORE: 'PACKS_AND_ASSETS_EXISTED_ACROSS_MULTIPLE_TABS_WITH_RUNTIME_GAPS',
    PROPOSAL: 'DAILY_PRECHECK_BASELINE_QA_CONDITIONAL_OPENAI_GEMINI_AB_PROMOTION_URL_CATALOG_WRITEBACK',
    WHY_NOW: 'User requested continuous reusable front-pack validation and learning loop.',
    EVIDENCE_IDS: runId, EXPECTED_IMPACT: 'Less duplicate API use; reusable tested packs; traceable publish URLs; lighter fronts.',
    RISK: 'External AI QA and public publishing remain gated by configured credentials/approval.',
    TASK_ID: runId, GITHUB_REPO: '8friend8ship-cloud/notebooklm-webapp-bridge',
    BRANCH: 'feat/central-daily-qa-asset-governor-20260828', BACKEND_FUNCTION: 'runCentralDailyQaAssetGovernor',
    TEST_CASE: 'baseline then conditional dual-model QA then promotion', TEST_RESULT: status,
    DECISION: /PASS/.test(status) ? 'APPLY_AFTER_RUNTIME_READBACK' : 'RETEST_REQUIRED', STATUS: 'ACTIVE', ROLLED_BACK: false
  });
  return {runId: runId, status: status};
}

function centralPrecheckLessonsSafe_(projectKey, artifactType, errorSignature) {
  try {
    if (typeof centralPrecheckLessonsV1 === 'function') return centralPrecheckLessonsV1(projectKey, artifactType, errorSignature);
  } catch (e) {}
  const rows = rowsAsObjects_(CDWG_TABS.precheck);
  const matches = rows.filter(function(r) {
    const app = text_(r.APP_ID || r.PROJECT_ID);
    const notes = text_(r.NOTES);
    return (!projectKey || !app || app === projectKey) && (!artifactType || notes.indexOf(artifactType) >= 0) && (!errorSignature || notes.indexOf(errorSignature) >= 0);
  }).slice(-20);
  const block = matches.some(function(m) { return text_(m.STATUS) === 'BLOCK_REPEAT_UNTIL_FIXED'; });
  return {ok: !block, decision: block ? 'DIAGNOSTIC_HOLD' : 'PROCEED', matches: matches};
}

function rowsAsObjects_(sheetName) {
  const sh = SpreadsheetApp.openById(CDWG_MASTER_REGISTRY_ID).getSheetByName(sheetName);
  if (!sh) throw new Error('SHEET_NOT_FOUND:' + sheetName);
  const values = sh.getDataRange().getValues();
  if (values.length < 2) return [];
  const h = values[0].map(String);
  return values.slice(1).filter(function(r) { return r.some(function(v) { return v !== ''; }); }).map(function(r) {
    const o = {}; h.forEach(function(k, i) { o[k] = r[i]; }); return o;
  });
}

function appendByHeaderSafe_(sheetName, payload) {
  if (typeof appendByHeader_ === 'function') {
    try { return appendByHeader_(sheetName, payload); } catch (e) {}
  }
  const sh = SpreadsheetApp.openById(CDWG_MASTER_REGISTRY_ID).getSheetByName(sheetName);
  if (!sh) throw new Error('SHEET_NOT_FOUND:' + sheetName);
  const width = sh.getLastColumn();
  const headers = sh.getRange(1, 1, 1, width).getValues()[0];
  const row = headers.map(function(h) { return Object.prototype.hasOwnProperty.call(payload, h) ? payload[h] : ''; });
  sh.appendRow(row);
  return sh.getLastRow();
}

function compactError_(json) {
  return JSON.stringify((json && (json.error || json.errors)) || json || {}).slice(0, 4000);
}
function text_(v) { return v == null ? '' : String(v); }
function makeId_(prefix) {
  return prefix + '_' + Utilities.formatDate(new Date(), Session.getScriptTimeZone() || 'Asia/Seoul', 'yyyyMMdd_HHmmss') + '_' + Utilities.getUuid().slice(0, 8);
}
function digestHex_(s) {
  return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, s, Utilities.Charset.UTF_8).map(function(b) { const x = b < 0 ? b + 256 : b; return ('0' + x.toString(16)).slice(-2); }).join('');
}
