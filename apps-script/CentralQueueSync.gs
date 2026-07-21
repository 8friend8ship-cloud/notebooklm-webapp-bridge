const CENTRAL_QUEUE_CONFIG = Object.freeze({
  spreadsheetId: '1uN6HMbPpo9vSF-hARLKjN-jipy1SJiK75Zc41t8zE98',
  sourceSheet: '30_TASK_QUEUE',
  targetSheet: 'NotebookLM_Task',
  acceptedTaskTypes: ['NOTEBOOKLM', 'NOTEBOOKLM_EDIT', 'NOTEBOOKLM_EXPORT', 'APP_REBUILD'],
});

/**
 * 중앙 에이전트 작업큐의 READY 작업을 현재 NotebookLM 브리지 시트로 가져옵니다.
 * 원본 중앙 시트는 삭제하지 않고, 가져온 작업만 CLAIMED로 변경합니다.
 */
function syncCentralQueueToNotebookLM() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) return { ok: false, skipped: true, reason: 'LOCKED' };

  try {
    const centralBook = SpreadsheetApp.openById(CENTRAL_QUEUE_CONFIG.spreadsheetId);
    const source = centralBook.getSheetByName(CENTRAL_QUEUE_CONFIG.sourceSheet);
    if (!source) throw new Error('중앙 30_TASK_QUEUE 시트를 찾지 못했습니다.');

    const localBook = SpreadsheetApp.getActive();
    const target = ensureNotebookTaskSheet_(localBook);
    const existingIds = loadTaskIds_(target);
    const rows = source.getDataRange().getValues();
    if (rows.length < 2) return { ok: true, imported: 0 };

    const header = rows[0].map(String);
    const index = header.reduce((map, name, i) => (map[name] = i, map), {});
    const required = ['TASK_ID', 'TASK_TYPE', 'SOURCE_ID', 'REQUEST', 'STATUS', 'PRIORITY', 'CREATED_AT', 'DUE_AT'];
    required.forEach(name => {
      if (index[name] === undefined) throw new Error(`중앙 작업큐 필수 열 누락: ${name}`);
    });

    const imported = [];
    rows.slice(1).forEach((row, offset) => {
      const taskId = String(row[index.TASK_ID] || '').trim();
      const taskType = String(row[index.TASK_TYPE] || '').trim();
      const status = String(row[index.STATUS] || '').trim();
      if (!taskId || existingIds.has(taskId) || status !== 'READY') return;
      if (!CENTRAL_QUEUE_CONFIG.acceptedTaskTypes.includes(taskType)) return;

      target.appendRow([
        taskId,
        taskType,
        row[index.SOURCE_ID] || '',
        row[index.REQUEST] || '',
        row[index.PRIORITY] || 'NORMAL',
        'READY',
        row[index.CREATED_AT] || new Date(),
        row[index.DUE_AT] || '',
        '',
        '',
        new Date(),
      ]);

      source.getRange(offset + 2, index.STATUS + 1).setValue('CLAIMED');
      source.getRange(offset + 2, header.indexOf('UPDATED_AT') + 1).setValue(new Date());
      existingIds.add(taskId);
      imported.push(taskId);
    });

    return { ok: true, imported: imported.length, taskIds: imported };
  } finally {
    lock.releaseLock();
  }
}

function ensureNotebookTaskSheet_(book) {
  let sheet = book.getSheetByName(CENTRAL_QUEUE_CONFIG.targetSheet);
  if (!sheet) sheet = book.insertSheet(CENTRAL_QUEUE_CONFIG.targetSheet);

  const headers = [
    'TASK_ID', 'TASK_TYPE', 'SOURCE_ID', 'REQUEST', 'PRIORITY', 'STATUS',
    'CREATED_AT', 'DUE_AT', 'RESULT_URL', 'ERROR_MESSAGE', 'UPDATED_AT'
  ];
  if (sheet.getLastRow() === 0) {
    sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    sheet.setFrozenRows(1);
  }
  return sheet;
}

function loadTaskIds_(sheet) {
  if (sheet.getLastRow() < 2) return new Set();
  return new Set(sheet.getRange(2, 1, sheet.getLastRow() - 1, 1).getDisplayValues().flat().filter(Boolean));
}

function installCentralQueueSyncTrigger() {
  const handler = 'syncCentralQueueToNotebookLM';
  ScriptApp.getProjectTriggers()
    .filter(trigger => trigger.getHandlerFunction() === handler)
    .forEach(trigger => ScriptApp.deleteTrigger(trigger));

  ScriptApp.newTrigger(handler).timeBased().everyHours(1).create();
}
