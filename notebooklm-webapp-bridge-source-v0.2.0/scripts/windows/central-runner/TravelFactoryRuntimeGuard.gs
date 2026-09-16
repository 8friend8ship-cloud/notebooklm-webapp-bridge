/**
 * Automatic runtime guard for APP_TRAVEL / CENTRAL_FACTORY_V2.
 * Called at the beginning of the existing processTaskQueue().
 * No new deployment is created and upstream Queens/Seed remains untouched.
 */
var TRAVEL_FACTORY_RUNTIME_GUARD_VERSION = 'TRAVEL_FACTORY_RUNTIME_GUARD_V1_20260820';
var TRAVEL_FACTORY_RUNTIME_GUARD_KEY = 'TRAVEL_DRYWRITER_RUNTIME_CONFIG_GUARD_V1';

function travelFactoryEnsureRuntimeConfig_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var config = ss.getSheetByName('CONFIG');
  if (!config) return { ok: false, skipped: true, reason: 'CONFIG_MISSING' };

  var values = config.getRange(1, 1, Math.max(config.getLastRow(), 1), 2).getValues();
  var map = {};
  for (var i = 1; i < values.length; i++) map[String(values[i][0] || '').trim()] = values[i][1];
  if (String(map.APP_ID || '').trim() !== 'APP_TRAVEL') return { ok: true, skipped: true, reason: 'NOT_APP_TRAVEL' };

  var url = String(map.DRYWRITER_WEBAPP_URL || '').trim();
  if (!/^https:\/\/script\.google\.com\/macros\/s\/[^/]+\/exec(?:\?.*)?$/.test(url)) {
    return { ok: false, skipped: true, reason: 'CONFIG_DRYWRITER_URL_INVALID_OR_MISSING' };
  }

  var props = PropertiesService.getScriptProperties();
  var before = String(props.getProperty('DRYWRITER_WEBAPP_URL') || '').trim();
  var changed = before !== url;
  if (changed) props.setProperty('DRYWRITER_WEBAPP_URL', url);
  var after = String(props.getProperty('DRYWRITER_WEBAPP_URL') || '').trim();
  if (after !== url) throw new Error('TRAVEL_DRYWRITER_SCRIPT_PROPERTY_READBACK_FAILED');

  var resetCount = 0;
  if (changed) {
    var dry = ss.getSheetByName('DRYWRITER_QUEUE');
    if (dry && dry.getLastRow() > 1) {
      var dryRows = dry.getRange(2, 1, dry.getLastRow() - 1, Math.min(dry.getLastColumn(), 9)).getValues();
      for (var d = 0; d < dryRows.length; d++) {
        if (String(dryRows[d][4] || '') === 'WAITING_BRIDGE' && String(dryRows[d][8] || '') === 'DRYWRITER_WEBAPP_URL_NOT_CONFIGURED') {
          dry.getRange(d + 2, 5).setValue('PENDING');
          dry.getRange(d + 2, 9).clearContent();
          resetCount++;
        }
      }
    }
  }

  var queuedTaskId = '';
  if (changed) {
    var task = ss.getSheetByName('TASK_QUEUE');
    if (!task) throw new Error('TASK_QUEUE_MISSING');
    var existing = false;
    if (task.getLastRow() > 1) {
      var taskRows = task.getRange(2, 1, task.getLastRow() - 1, 13).getValues();
      for (var t = 0; t < taskRows.length; t++) {
        if (String(taskRows[t][12] || '') === TRAVEL_FACTORY_RUNTIME_GUARD_KEY) { existing = true; break; }
      }
    }
    if (!existing) {
      queuedTaskId = 'TASK_' + Utilities.getUuid();
      task.appendRow([
        queuedTaskId,
        'APP_TRAVEL',
        'FACTORY_CYCLE',
        JSON.stringify({ source: 'runtime_guard', run_date: Utilities.formatDate(new Date(), 'Asia/Seoul', 'yyyyMMdd'), repair_version: TRAVEL_FACTORY_RUNTIME_GUARD_VERSION, drywriter_nonblocking: true }),
        'QUEUED',
        5,
        new Date().toISOString(),
        '', '', 0, '', '', TRAVEL_FACTORY_RUNTIME_GUARD_KEY
      ]);
    }
  }

  return {
    ok: true,
    version: TRAVEL_FACTORY_RUNTIME_GUARD_VERSION,
    scriptId: ScriptApp.getScriptId(),
    changed: changed,
    resetDryWriterRows: resetCount,
    queuedTaskId: queuedTaskId,
    propertyConfigured: true,
    at: new Date().toISOString()
  };
}
