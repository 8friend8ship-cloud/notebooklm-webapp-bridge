const TABLET_TRAFFIC_MANAGER_V1 = Object.freeze({
  tabletSheetId: '1pZFNTeu-F0CjhYAuoKazD92UMn6A-9nkse6QyYwj2yA',
  centralManagerSheetId: '147pycCA4XT2u4TxFYZOaR9na0RtpplbNmRJmmN2o-3w',
  workerStatusFileId: '1jJrdrC1u8a2ic-0aWrQpMfmJj5Ib_Qho',
  actionStatusFileId: '1s0iZXTqL5dOIkQk9LuJr6Ijk63lHDdZ0',
  workerId: 'TABLET_ANDROID_01',
  notebookPrimaryJob: 'TASK_TABLET_NOTEBOOKLM_E2E_20260901_1005',
  lockKey: 'LOCK_TABLET_ANDROID_01_UI',
  staleHeartbeatSec: 180,
  timeZone: 'Asia/Seoul'
});

/**
 * Hourly fail-closed tablet traffic manager.
 *
 * Contract:
 * - One mutating tablet UI job maximum.
 * - NotebookLM stays tablet-primary until VERIFIED unless the tablet is explicitly
 *   CAPABILITY_BLOCKED at a safe checkpoint.
 * - A fresh heartbeat proves worker life, not service UI capability.
 * - Known capability block releases tablet ownership and permits existing laptop fallback.
 * - Flow/Gemini work is held, never deleted, only while tablet NotebookLM truly owns UI.
 * - No physical trigger creation occurs here. Existing central scheduler calls it.
 * - Quota/objective manager is called logically in the same hourly cycle.
 */
function runTabletTrafficHourlyManagerV1(context) {
  let quotaDecision = null;
  if (typeof runGoogleAiQuotaObjectiveManagerV1 === 'function') {
    try {
      quotaDecision = runGoogleAiQuotaObjectiveManagerV1({
        source: 'runTabletTrafficHourlyManagerV1',
        context: context || {}
      });
    } catch (quotaErr) {
      quotaDecision = { ok: false, status: 'QUOTA_MANAGER_ERROR', error: String(quotaErr) };
    }
  }

  const cfg = TABLET_TRAFFIC_MANAGER_V1;
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) {
    return { ok: false, status: 'LOCK_BUSY', lockKey: cfg.lockKey, quotaDecision: quotaDecision };
  }

  try {
    const now = new Date();
    const tablet = SpreadsheetApp.openById(cfg.tabletSheetId);
    const queue = tablet.getSheetByName('QUEUE');
    const traffic = tablet.getSheetByName('TRAFFIC_HOURLY');
    if (!queue || !traffic) throw new Error('TABLET_QUEUE_OR_TRAFFIC_SHEET_MISSING');

    const workerStatus = readDriveJsonV1_(cfg.workerStatusFileId);
    const actionStatus = readDriveJsonV1_(cfg.actionStatusFileId);
    const automateAcc = parseStatusIntV1_(workerStatus.status || '', 'automate_acc');
    const workerTime = workerStatus.time ? new Date(workerStatus.time) : null;
    const heartbeatAgeSec = workerTime && !isNaN(workerTime.getTime())
      ? Math.max(0, Math.floor((now.getTime() - workerTime.getTime()) / 1000))
      : 999999;
    const heartbeatStale = heartbeatAgeSec > cfg.staleHeartbeatSec;

    const values = queue.getDataRange().getValues();
    if (values.length < 2) throw new Error('TABLET_QUEUE_EMPTY');
    const header = values[0].map(String);
    const idx = indexMapV1_(header);
    const rows = values.slice(1);

    const notebookRow = findJobRowV1_(rows, idx, cfg.notebookPrimaryJob);
    const notebookVerified = notebookRow ? truthyV1_(notebookRow[idx.VERIFIED]) : false;
    const notebookStatus = notebookRow ? String(notebookRow[idx.STATUS] || '').toUpperCase() : '';
    const notebookCapabilityBlocked = /CAPABILITY_BLOCKED/.test(notebookStatus);

    const primaryJob = (notebookVerified || notebookCapabilityBlocked)
      ? chooseNextApprovedUiJobV1_(rows, idx, cfg.workerId)
      : cfg.notebookPrimaryJob;

    const heldJobs = [];
    if (!notebookVerified && !notebookCapabilityBlocked) {
      rows.forEach((row, i) => {
        const jobId = String(row[idx.JOB_ID] || '');
        const worker = String(row[idx.WORKER] || '');
        const taskType = String(row[idx.TASK_TYPE] || '').toUpperCase();
        const status = String(row[idx.STATUS] || '');
        if (!jobId || jobId === primaryJob || worker !== cfg.workerId) return;
        if (!/(FLOW|GEMINI)/.test(taskType)) return;
        if (/DONE|VERIFIED|STOPPED|SUPERSEDED/.test(status)) return;
        heldJobs.push(jobId);
        if (!/^HOLD_TRAFFIC_LOCK_/.test(status)) {
          const sheetRow = i + 2;
          queue.getRange(sheetRow, idx.STATUS + 1).setValue('HOLD_TRAFFIC_LOCK_NOTEBOOKLM_PRIMARY');
          queue.getRange(sheetRow, idx.RESUME_POINT + 1).setValue('AFTER_' + primaryJob + '_VERIFIED');
        }
      });
    }

    const activeUiJobs = rows.filter(row => isActiveUiRowV1_(row, idx, cfg.workerId));
    let decision = 'HEALTHY_SERIAL';
    let nextGate = 'CONTINUE_PRIMARY';

    if (notebookCapabilityBlocked) {
      decision = 'NOTEBOOKLM_TABLET_CAPABILITY_BLOCKED_RELEASED';
      nextGate = 'LAPTOP_NOTEBOOKLM_FALLBACK_EXISTING_LINEAGE';
    } else if (heartbeatStale) {
      decision = 'BLOCKED_STALE_HEARTBEAT';
      nextGate = 'RECOVER_TABLET_WORKER_HEARTBEAT';
    } else if (activeUiJobs.length > 1) {
      decision = 'BLOCKED_UI_CONCURRENCY_GT_1';
      nextGate = 'HOLD_LOWER_PRIORITY_UI_JOBS';
    } else if (!notebookVerified && automateAcc !== 1) {
      decision = 'BLOCKED_ACCESSIBILITY';
      nextGate = 'ENABLE_AUTOMATE_ACCESSIBILITY_THEN_NOTEBOOKLM_UI';
    } else if (!notebookVerified) {
      decision = 'NOTEBOOKLM_PRIMARY_READY';
      nextGate = 'OPEN_NOTEBOOKLM_NEW_NOTEBOOK_SOURCE_CHAT_STUDIO_REQUIRED_ONLY';
    }

    const hourBucket = Utilities.formatDate(now, cfg.timeZone, 'yyyy-MM-dd HH:00');
    const lastRow = traffic.getLastRow();
    const lastBucket = lastRow >= 2 ? String(traffic.getRange(lastRow, 1).getValue() || '') : '';
    const record = [
      Utilities.formatDate(now, cfg.timeZone, "yyyy-MM-dd'T'HH:mm:ssXXX"),
      cfg.workerId,
      primaryJob || '',
      String(workerStatus.status || ''),
      automateAcc,
      String(actionStatus.action_id || ''),
      String(actionStatus.result || ''),
      activeUiJobs.length,
      heldJobs.join(';'),
      decision,
      cfg.lockKey,
      nextGate,
      true,
      false,
      'workerTime=' + String(workerStatus.time || '') + ';heartbeatAgeSec=' + heartbeatAgeSec + ';actionTime=' + String(actionStatus.time || ''),
      'hourBucket=' + hourBucket + ';capabilityBlocked=' + notebookCapabilityBlocked + ';quotaStatus=' + String(quotaDecision && quotaDecision.status || '')
    ];
    if (lastBucket.indexOf(hourBucket) !== 0) traffic.appendRow(record);

    if (decision !== 'HEALTHY_SERIAL' && decision !== 'NOTEBOOKLM_PRIMARY_READY') {
      writeCentralTabletTrafficHistoryV1_(cfg, now, decision, record, nextGate);
    }

    return {
      ok: true,
      checkedAt: record[0],
      primaryJob: primaryJob,
      notebookVerified: notebookVerified,
      notebookCapabilityBlocked: notebookCapabilityBlocked,
      automateAcc: automateAcc,
      heartbeatAgeSec: heartbeatAgeSec,
      activeUiCount: activeUiJobs.length,
      heldJobs: heldJobs,
      decision: decision,
      nextGate: nextGate,
      actionResult: String(actionStatus.result || ''),
      quotaDecision: quotaDecision
    };
  } finally {
    lock.releaseLock();
  }
}

function readDriveJsonV1_(fileId) {
  const text = DriveApp.getFileById(fileId).getBlob().getDataAsString('UTF-8');
  return JSON.parse(text || '{}');
}

function parseStatusIntV1_(status, key) {
  const m = String(status || '').match(new RegExp('(?:^|\\s)' + key + '=(-?\\d+)'));
  return m ? Number(m[1]) : -1;
}

function indexMapV1_(header) {
  const out = {};
  header.forEach((name, i) => { out[String(name)] = i; });
  ['JOB_ID','WORKER','TASK_TYPE','APPROVAL_STATE','CLAIM','STATUS','RESUME_POINT','DRIVE_SYNCED','VERIFIED'].forEach(k => {
    if (out[k] === undefined) throw new Error('QUEUE_COLUMN_MISSING_' + k);
  });
  return out;
}

function findJobRowV1_(rows, idx, jobId) {
  return rows.find(row => String(row[idx.JOB_ID] || '') === jobId) || null;
}

function chooseNextApprovedUiJobV1_(rows, idx, workerId) {
  const candidate = rows.find(row => {
    const worker = String(row[idx.WORKER] || '');
    const approved = /APPROVED/.test(String(row[idx.APPROVAL_STATE] || ''));
    const status = String(row[idx.STATUS] || '').toUpperCase();
    const taskType = String(row[idx.TASK_TYPE] || '').toUpperCase();
    return worker === workerId &&
      approved &&
      !/DONE|VERIFIED|STOPPED|SUPERSEDED|CAPABILITY_BLOCKED/.test(status) &&
      /(NOTEBOOKLM|GEMINI|FLOW)/.test(taskType);
  });
  return candidate ? String(candidate[idx.JOB_ID] || '') : '';
}

function isActiveUiRowV1_(row, idx, workerId) {
  if (String(row[idx.WORKER] || '') !== workerId) return false;
  const taskType = String(row[idx.TASK_TYPE] || '').toUpperCase();
  if (!/(NOTEBOOKLM|GEMINI|FLOW)/.test(taskType)) return false;
  const status = String(row[idx.STATUS] || '').toUpperCase();
  const claim = String(row[idx.CLAIM] || '').toUpperCase();
  if (/HOLD|DONE|VERIFIED|STOPPED|SUPERSEDED|CAPABILITY_BLOCKED/.test(status)) return false;
  return /CLAIMED|STARTED|RUNNING/.test(status) || (claim && claim !== 'UNCLAIMED');
}

function truthyV1_(value) {
  return value === true || String(value).toUpperCase() === 'TRUE' || String(value).toUpperCase() === 'VERIFIED';
}

function writeCentralTabletTrafficHistoryV1_(cfg, now, decision, record, nextGate) {
  const central = SpreadsheetApp.openById(cfg.centralManagerSheetId);
  const history = central.getSheetByName('15_HISTORY_READBACK');
  if (!history) return;
  const evidence = String(record[14] || '');
  const lastRow = history.getLastRow();
  if (lastRow >= 2) {
    const lastEvent = String(history.getRange(lastRow, 2).getValue() || '');
    const lastResult = String(history.getRange(lastRow, 5).getValue() || '');
    if (lastEvent === 'TABLET_TRAFFIC_HOURLY_CHANGED_EVIDENCE' && lastResult.indexOf(decision) >= 0) return;
  }
  history.appendRow([
    Utilities.formatDate(now, cfg.timeZone, 'yyyy-MM-dd HH:mm KST'),
    'TABLET_TRAFFIC_HOURLY_CHANGED_EVIDENCE',
    'TABLET_WORKER_STATUS + TABLET_ACTION_STATUS + TABLET_WORKER_QUEUE + GOOGLE_AI_QUOTA_OBJECTIVE',
    'Hourly traffic manager observed ' + decision + '. NotebookLM primary=' + cfg.notebookPrimaryJob + '; maxConcurrentUI=1.',
    'DECISION=' + decision + ';' + evidence,
    'NEXT_RESUME_POINT=' + nextGate + '; preserve held jobs; no duplicate notebook/task.'
  ]);
}
