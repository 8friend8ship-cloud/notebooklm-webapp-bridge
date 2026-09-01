const GOOGLE_AI_QUOTA_OBJECTIVE_V1 = Object.freeze({
  centralManagerSheetId: '147pycCA4XT2u4TxFYZOaR9na0RtpplbNmRJmmN2o-3w',
  tabletSheetId: '1pZFNTeu-F0CjhYAuoKazD92UMn6A-9nkse6QyYwj2yA',
  quotaSheetName: '16_GOOGLE_AI_QUOTA_OBJECTIVE',
  tabletQueueName: 'QUEUE',
  timeZone: 'Asia/Seoul',
  notebookJobId: 'TASK_TABLET_NOTEBOOKLM_E2E_20260901_1005'
});

/**
 * Logical quota/objective manager. It never creates another physical trigger and
 * never generates media itself. Existing service workers consume the decision.
 *
 * Canonical policy:
 * platform need -> live plan/usage/credit readback -> reuse -> value/cost score
 * -> required output only -> budget reservation -> existing worker/lock
 * -> raw Drive -> analysis -> Queens -> Seed -> Template -> platform adapter.
 */
function runGoogleAiQuotaObjectiveManagerV1(context) {
  const cfg = GOOGLE_AI_QUOTA_OBJECTIVE_V1;
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) return { ok: false, status: 'LOCK_BUSY' };

  try {
    const now = new Date();
    const central = SpreadsheetApp.openById(cfg.centralManagerSheetId);
    const quotaSheet = central.getSheetByName(cfg.quotaSheetName);
    if (!quotaSheet) throw new Error('GOOGLE_AI_QUOTA_SHEET_MISSING');

    const quota = readGoogleAiQuotaRowsV1_(quotaSheet);
    const tablet = SpreadsheetApp.openById(cfg.tabletSheetId);
    const queue = tablet.getSheetByName(cfg.tabletQueueName);
    if (!queue) throw new Error('TABLET_QUEUE_MISSING');

    const qValues = queue.getDataRange().getValues();
    const qHeader = qValues[0].map(String);
    const qIdx = mapHeaderV1_(qHeader);
    const candidates = qValues.slice(1)
      .map((row, i) => buildQuotaCandidateV1_(row, i + 2, qIdx, quota))
      .filter(Boolean)
      .sort((a, b) => b.score - a.score);

    const selected = candidates.length ? candidates[0] : null;
    const notebook = candidates.find(c => c.service === 'NOTEBOOKLM') || null;
    const tabletNotebookBlocked = notebook && /CAPABILITY_BLOCKED/.test(notebook.status);

    const decisions = {};
    ['NOTEBOOKLM', 'FLOW'].forEach(service => {
      const state = quota[service];
      if (!state) return;
      const liveReady = isLiveQuotaReadyV1_(service, state, now);
      let decision = 'NO_APPROVED_JOB';
      if (service === 'NOTEBOOKLM' && tabletNotebookBlocked) {
        decision = 'LAPTOP_FALLBACK_EXISTING_LINEAGE';
      } else if (!liveReady) {
        decision = 'LIVE_USAGE_READBACK_REQUIRED_BEFORE_NEW_GENERATION';
      } else if (selected && selected.service === service) {
        decision = 'SELECTED_' + selected.requiredOutput;
      } else if (candidates.some(c => c.service === service)) {
        decision = 'WAIT_HIGHER_VALUE_JOB_OR_REUSE';
      }
      decisions[service] = decision;
      writeQuotaDecisionV1_(quotaSheet, state.sheetRow, now, decision, liveReady ? 'QUOTA_READY' : 'LIVE_READBACK_PENDING');
    });

    return {
      ok: true,
      checkedAt: Utilities.formatDate(now, cfg.timeZone, "yyyy-MM-dd'T'HH:mm:ssXXX"),
      selected: selected,
      tabletNotebookCapabilityBlocked: !!tabletNotebookBlocked,
      decisions: decisions,
      candidateCount: candidates.length
    };
  } finally {
    lock.releaseLock();
  }
}

/**
 * Runtime bridges call this after reading the actual UI. Do not call with guessed values.
 * Patch keys: accountPlan, planVerified, usageSource, windowRemaining,
 * weeklyRemaining, monthlyCreditsRemaining, nextReset, liveModelCost, notes.
 */
function recordGoogleAiQuotaReadbackV1(service, patch) {
  service = String(service || '').toUpperCase();
  if (!/^(NOTEBOOKLM|FLOW)$/.test(service)) throw new Error('UNSUPPORTED_SERVICE_' + service);
  patch = patch || {};

  const cfg = GOOGLE_AI_QUOTA_OBJECTIVE_V1;
  const central = SpreadsheetApp.openById(cfg.centralManagerSheetId);
  const sheet = central.getSheetByName(cfg.quotaSheetName);
  if (!sheet) throw new Error('GOOGLE_AI_QUOTA_SHEET_MISSING');
  const rows = readGoogleAiQuotaRowsV1_(sheet);
  const state = rows[service];
  if (!state) throw new Error('GOOGLE_AI_QUOTA_ROW_MISSING_' + service);

  const row = state.sheetRow;
  const now = new Date();
  sheet.getRange(row, 1).setValue(Utilities.formatDate(now, cfg.timeZone, 'yyyy-MM-dd HH:mm:ss KST'));
  if (patch.accountPlan !== undefined) sheet.getRange(row, 3).setValue(String(patch.accountPlan));
  if (patch.planVerified !== undefined) sheet.getRange(row, 4).setValue(!!patch.planVerified);
  if (patch.usageSource !== undefined) sheet.getRange(row, 5).setValue(String(patch.usageSource));
  if (patch.windowRemaining !== undefined) sheet.getRange(row, 6).setValue(String(patch.windowRemaining));
  if (patch.weeklyRemaining !== undefined) sheet.getRange(row, 7).setValue(String(patch.weeklyRemaining));
  if (patch.monthlyCreditsRemaining !== undefined) sheet.getRange(row, 8).setValue(String(patch.monthlyCreditsRemaining));
  if (patch.nextReset !== undefined) sheet.getRange(row, 9).setValue(String(patch.nextReset));
  if (patch.liveModelCost !== undefined) sheet.getRange(row, 10).setValue(String(patch.liveModelCost));
  if (patch.notes !== undefined) sheet.getRange(row, 18).setValue(String(patch.notes));
  sheet.getRange(row, 17).setValue('LIVE_READBACK_RECORDED');

  return runGoogleAiQuotaObjectiveManagerV1({ source: 'recordGoogleAiQuotaReadbackV1', service: service });
}

function readGoogleAiQuotaRowsV1_(sheet) {
  const values = sheet.getDataRange().getValues();
  if (values.length < 2) return {};
  const idx = mapHeaderV1_(values[0].map(String));
  const out = {};
  values.slice(1).forEach((row, i) => {
    const service = String(row[idx.SERVICE] || '').toUpperCase();
    if (!service) return;
    out[service] = {
      sheetRow: i + 2,
      service: service,
      accountPlan: String(row[idx.ACCOUNT_PLAN] || ''),
      planVerified: row[idx.PLAN_VERIFIED] === true || String(row[idx.PLAN_VERIFIED]).toUpperCase() === 'TRUE',
      usageSource: String(row[idx.USAGE_SOURCE] || ''),
      windowRemaining: String(row[idx.WINDOW_REMAINING] || ''),
      weeklyRemaining: String(row[idx.WEEKLY_REMAINING] || ''),
      monthlyCreditsRemaining: String(row[idx.MONTHLY_CREDITS_REMAINING] || ''),
      nextReset: String(row[idx.NEXT_RESET] || ''),
      liveModelCost: String(row[idx.LIVE_MODEL_COST] || ''),
      platformObjective: String(row[idx.PLATFORM_OBJECTIVE] || ''),
      requiredOutput: String(row[idx.REQUIRED_OUTPUT] || ''),
      priorityScore: Number(row[idx.PRIORITY_SCORE] || 0),
      status: String(row[idx.STATUS] || '')
    };
  });
  return out;
}

function buildQuotaCandidateV1_(row, sheetRow, idx, quota) {
  const approval = String(row[idx.APPROVAL_STATE] || '');
  const status = String(row[idx.STATUS] || '');
  const taskType = String(row[idx.TASK_TYPE] || '').toUpperCase();
  if (!/APPROVED/.test(approval)) return null;
  if (/DONE|VERIFIED|STOPPED|SUPERSEDED/.test(status)) return null;
  const service = /NOTEBOOKLM/.test(taskType) ? 'NOTEBOOKLM' : (/FLOW/.test(taskType) ? 'FLOW' : '');
  if (!service) return null;

  const state = quota[service] || {};
  let score = Number(state.priorityScore || 0) || (service === 'NOTEBOOKLM' ? 100 : 80);
  if (/P0_TIMEBOUND/.test(status)) score += 50;
  if (/P0_BLOCKER|BLOCKER/.test(status)) score += 35;
  if (/CAPABILITY_BLOCKED/.test(status)) score -= 80;
  if (/HOLD|WAIT/.test(status)) score -= 10;

  return {
    sheetRow: sheetRow,
    jobId: String(row[idx.JOB_ID] || ''),
    service: service,
    status: status,
    score: score,
    platformObjective: String(state.platformObjective || ''),
    requiredOutput: normalizeRequiredOutputV1_(service, state.requiredOutput)
  };
}

function normalizeRequiredOutputV1_(service, configured) {
  configured = String(configured || '');
  if (configured) return configured;
  return service === 'NOTEBOOKLM' ? 'AUDIO_OVERVIEW|SLIDES' : 'IMAGE|VIDEO_ON_DEMAND';
}

function isLiveQuotaReadyV1_(service, state, now) {
  if (!state || !state.planVerified) return false;
  if (service === 'FLOW') {
    return !!state.monthlyCreditsRemaining && !/REFERENCE|PENDING|REQUIRED/.test(state.monthlyCreditsRemaining);
  }
  const cutover = new Date('2026-09-02T00:00:00+09:00');
  if (now.getTime() < cutover.getTime()) {
    return !!state.usageSource && !/PENDING/.test(state.status);
  }
  return !!state.windowRemaining && !!state.weeklyRemaining &&
    !/PENDING|REQUIRED/.test(state.windowRemaining + ' ' + state.weeklyRemaining);
}

function writeQuotaDecisionV1_(sheet, row, now, decision, status) {
  const cfg = GOOGLE_AI_QUOTA_OBJECTIVE_V1;
  sheet.getRange(row, 1).setValue(Utilities.formatDate(now, cfg.timeZone, 'yyyy-MM-dd HH:mm:ss KST'));
  sheet.getRange(row, 16).setValue(decision);
  sheet.getRange(row, 17).setValue(status);
}

function mapHeaderV1_(header) {
  const out = {};
  header.forEach((name, i) => { out[String(name)] = i; });
  return out;
}
