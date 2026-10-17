/**
 * NotebookLM maximum-safe-capacity logical governor.
 *
 * IMPORTANT:
 * - Called from the existing verified processTaskQueue 5-minute physical wake.
 * - Never installs a second physical trigger.
 * - Tablet is the NotebookLM execution owner. Laptop fallback is disabled.
 * - A task is claimed only with a fresh tablet heartbeat and positive runtime UI proof.
 * - Daily quantity is adaptive: use all safe live capacity, never a fixed item count.
 * - Existing completed audio is reused and must not be regenerated.
 */
const NLM_CAPACITY_GOVERNOR_V1 = Object.freeze({
  masterSpreadsheetId: '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI',
  queueSheet: '07_EXECUTION_QUEUE',
  runnerSheet: '51_LOCAL_BRIDGE_RUNNERS',
  qaSheet: '80_DATA_RUNTIME_QA_LOG',
  cycleMs: 5 * 60 * 1000,
  executionBudgetMs: 280000,
  stopAtRatio: 0.95,
  throttleAtRatio: 0.80,
  heartbeatFreshMs: 10 * 60 * 1000,
  recoveryRetryMs: 5 * 60 * 1000,
  leaseMs: 15 * 60 * 1000,
  owner: 'TABLET_ANDROID_01',
  laptopFallback: false
});

function runNotebookLmMaxSafeCapacityGovernor5mIfDue_(now) {
  const started = Date.now();
  const current = now instanceof Date ? now : new Date();
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(3000)) return {ok:true, status:'SKIP_LOCKED'};

  try {
    const ss = SpreadsheetApp.openById(NLM_CAPACITY_GOVERNOR_V1.masterSpreadsheetId);
    const queue = ss.getSheetByName(NLM_CAPACITY_GOVERNOR_V1.queueSheet);
    const runners = ss.getSheetByName(NLM_CAPACITY_GOVERNOR_V1.runnerSheet);
    if (!queue || !runners) throw new Error('REQUIRED_CENTRAL_SHEET_MISSING');

    const rows = queue.getDataRange().getValues();
    const headers = headerMap_(rows[0]);
    const candidates = rows.slice(1).map((row, i) => ({row, rowNumber:i + 2}))
      .filter(x => isNotebookLmReadyTask_(x.row, headers));

    const worker = findNotebookLmTabletWorker_(runners, current);
    if (!worker.fresh || !worker.uiProof) {
      return writeNotebookLmGovernorQa_(ss, {
        ok:true,
        status:'TABLET_RECOVERY_ARMED',
        owner:NLM_CAPACITY_GOVERNOR_V1.owner,
        reason:worker.reason || 'FRESH_HEARTBEAT_AND_POSITIVE_UI_PROOF_REQUIRED',
        claimed:0,
        pending:candidates.length,
        retryAt:new Date(current.getTime() + NLM_CAPACITY_GOVERNOR_V1.recoveryRetryMs).toISOString(),
        workflowContinues:true,
        blockingScope:'NOTEBOOKLM_UI_ONLY',
        queuePreserved:true,
        laptopFallback:false
      });
    }

    // Maximum safe capacity is live worker capacity, not all queued jobs at once.
    // Default tablet UI concurrency is 1 unless the runner explicitly proves a higher safe value.
    const safeSlots = Math.max(1, Math.min(5, Number(worker.safeConcurrency) || 1));
    let claimed = 0;
    for (const item of candidates) {
      if (claimed >= safeSlots) break;
      const elapsed = Date.now() - started;
      const ratio = elapsed / NLM_CAPACITY_GOVERNOR_V1.executionBudgetMs;
      if (ratio >= NLM_CAPACITY_GOVERNOR_V1.stopAtRatio) break;
      if (hasLiveClaim_(item.row, headers, current)) continue;

      claimNotebookLmTask_(queue, item, headers, current, worker.runnerId);
      claimed += 1;

      // Actual UI execution remains with the tablet worker and returns RESULT/ACK.
      // Another slot is claimed only when the runner has explicitly reported safe concurrency.
      if (ratio >= NLM_CAPACITY_GOVERNOR_V1.throttleAtRatio) break;
    }

    return writeNotebookLmGovernorQa_(ss, {
      ok:true,
      status:claimed ? 'MAX_SAFE_CAPACITY_CLAIMED' : 'NO_READY_NOTEBOOKLM_TASK',
      owner:worker.runnerId,
      claimed,
      safeSlots,
      laptopFallback:false,
      elapsedMs:Date.now() - started
    });
  } finally {
    lock.releaseLock();
  }
}

function verifyNotebookLmCapacityGovernorRouteV1() {
  const triggers = ScriptApp.getProjectTriggers();
  const wakes = triggers.filter(t => t.getHandlerFunction() === 'processTaskQueue');
  const duplicates = wakes.length > 1;
  return {
    ok:wakes.length === 1 && !duplicates,
    status:wakes.length === 1 ? 'EXISTING_5M_WAKE_REUSED' :
      (duplicates ? 'DUPLICATE_PHYSICAL_WAKE_HOLD' : 'BOUND_WAKE_MISSING'),
    physicalTriggerCount:wakes.length,
    governor:'runNotebookLmMaxSafeCapacityGovernor5mIfDue_',
    createsNewTrigger:false
  };
}

function findNotebookLmTabletWorker_(sheet, now) {
  const values = sheet.getDataRange().getValues();
  const h = headerMap_(values[0]);
  for (let i = 1; i < values.length; i++) {
    const row = values[i];
    const target = String(read_(row, h, ['TARGET']) || '').toUpperCase();
    const runnerId = String(read_(row, h, ['RUNNER_ID']) || '');
    const notes = String(read_(row, h, ['NOTES']) || '').toUpperCase();
    if (!(runnerId === NLM_CAPACITY_GOVERNOR_V1.owner ||
          (target.includes('NOTEBOOKLM') && notes.includes('TABLET')))) continue;

    const heartbeatRaw = read_(row, h, ['CENTRAL_HEARTBEAT','LAST_SUCCESS_AT']);
    const heartbeat = heartbeatRaw instanceof Date ? heartbeatRaw : new Date(heartbeatRaw);
    const age = now.getTime() - heartbeat.getTime();
    const uiState = String(read_(row, h, ['UI_CONTROL_STATE','STATUS']) || '').toUpperCase();
    const fresh = Number.isFinite(age) && age >= 0 && age <= NLM_CAPACITY_GOVERNOR_V1.heartbeatFreshMs;
    const uiProof = /POSITIVE|UI_PASS|RUNTIME_VERIFIED|READY/.test(uiState);
    const slotMatch = notes.match(/SAFE_CONCURRENCY=(\d+)/);
    const safeConcurrency = slotMatch ? Number(slotMatch[1]) : 1;
    return {runnerId, fresh, uiProof, safeConcurrency,
      reason:fresh ? 'POSITIVE_UI_PROOF_REQUIRED' : 'FRESH_HEARTBEAT_REQUIRED'};
  }
  return {runnerId:NLM_CAPACITY_GOVERNOR_V1.owner, fresh:false, uiProof:false, reason:'TABLET_RUNNER_NOT_REGISTERED'};
}

function isNotebookLmReadyTask_(row, h) {
  const target = String(read_(row, h, ['TARGET_ID']) || '').toUpperCase();
  const type = String(read_(row, h, ['TASK_TYPE']) || '').toUpperCase();
  const status = String(read_(row, h, ['STATUS']) || '').toUpperCase();
  const action = String(read_(row, h, ['ACTION']) || '').toUpperCase();
  const nlm = /NOTEBOOKLM|NLM/.test(target + ' ' + type + ' ' + action);
  const ready = /READY|QUEUED|PENDING/.test(status) && !/DONE|COMPLETE|HOLD/.test(status);
  const duplicateAudio = /AUDIO/.test(action + ' ' + type) && /REUSE|COMPLETED/.test(action + ' ' + status);
  return nlm && ready && !duplicateAudio;
}

function hasLiveClaim_(row, h, now) {
  const notes = String(read_(row, h, ['NOTES']) || '');
  const match = notes.match(/NLM_LEASE_UNTIL=([^;\s]+)/);
  if (!match) return false;
  const until = new Date(match[1]);
  return Number.isFinite(until.getTime()) && until > now;
}

function claimNotebookLmTask_(sheet, item, h, now, runnerId) {
  const statusCol = h.STATUS;
  const ownerCol = h.OWNER;
  const notesCol = h.NOTES;
  if (statusCol == null || notesCol == null) throw new Error('QUEUE_HEADERS_MISSING');
  const leaseUntil = new Date(now.getTime() + NLM_CAPACITY_GOVERNOR_V1.leaseMs).toISOString();
  const notes = String(item.row[notesCol] || '');
  sheet.getRange(item.rowNumber, statusCol + 1).setValue('CLAIMED_TABLET_MAX_SAFE_CAPACITY');
  if (ownerCol != null) sheet.getRange(item.rowNumber, ownerCol + 1).setValue(runnerId);
  sheet.getRange(item.rowNumber, notesCol + 1)
    .setValue(notes + ';NLM_CLAIM=' + runnerId + ';NLM_LEASE_UNTIL=' + leaseUntil);
}

function writeNotebookLmGovernorQa_(ss, result) {
  const sheet = ss.getSheetByName(NLM_CAPACITY_GOVERNOR_V1.qaSheet);
  if (sheet) {
    sheet.appendRow([
      'QA_NLM_MAX_SAFE_CAPACITY_' + Utilities.getUuid(),
      new Date(),
      'APP_NLM_BRIDGE',
      'NOTEBOOKLM_MAX_SAFE_CAPACITY_GOVERNOR',
      JSON.stringify(result),
      result.status,
      result.claimed || 0,
      'RESULT_ACK_AND_DRIVE_READBACK_X2_REQUIRED'
    ]);
  }
  return result;
}

function headerMap_(headers) {
  return headers.reduce((m, v, i) => {
    const key = String(v || '').trim().toUpperCase();
    if (key) m[key] = i;
    return m;
  }, {});
}

function read_(row, map, keys) {
  for (const key of keys) if (map[key] != null) return row[map[key]];
  return '';
}
