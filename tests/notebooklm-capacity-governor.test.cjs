const fs = require('fs');
const vm = require('vm');
const assert = require('assert');

const sourcePath = fs.existsSync(__dirname + '/NotebookLmMaxSafeCapacityGovernor.gs')
  ? __dirname + '/NotebookLmMaxSafeCapacityGovernor.gs'
  : __dirname + '/../apps-script/NotebookLmMaxSafeCapacityGovernor.gs';
const source = fs.readFileSync(sourcePath, 'utf8');

function makeSheet(rows) {
  const writes = [];
  return {
    writes,
    rows,
    getDataRange() { return { getValues: () => rows }; },
    getRange(row, col) {
      return { setValue(value) { writes.push({row, col, value}); rows[row - 1][col - 1] = value; } };
    },
    appendRow(row) { writes.push({append: row}); }
  };
}

function runCase({heartbeat, uiState, notes = '', triggers = 1, queueRows}) {
  const queue = makeSheet(queueRows || [
    ['TASK_ID','TASK_TYPE','TARGET_ID','ACTION','STATUS','OWNER','NOTES'],
    ['T1','NOTEBOOKLM_SLIDES','APP_NLM_BRIDGE','CREATE_SLIDES','READY','',''],
    ['T2','NOTEBOOKLM_SUMMARY','APP_NLM_BRIDGE','CREATE_SUMMARY','READY','',''],
    ['T3','NOTEBOOKLM_AUDIO','APP_NLM_BRIDGE','REUSE COMPLETED AUDIO','READY','','']
  ]);
  const runners = makeSheet([
    ['RUNNER_ID','TARGET','CENTRAL_HEARTBEAT','UI_CONTROL_STATE','STATUS','NOTES'],
    ['TABLET_ANDROID_01','NOTEBOOKLM_UI_AUTOMATION',heartbeat,uiState,uiState,notes]
  ]);
  const qa = makeSheet([]);
  const ss = {
    getSheetByName(name) {
      return {
        '07_EXECUTION_QUEUE': queue,
        '51_LOCAL_BRIDGE_RUNNERS': runners,
        '80_DATA_RUNTIME_QA_LOG': qa
      }[name];
    }
  };
  const context = {
    Date, JSON, Math, Number, String, RegExp,
    LockService: {getScriptLock: () => ({tryLock: () => true, releaseLock: () => {}})},
    SpreadsheetApp: {openById: () => ss},
    ScriptApp: {getProjectTriggers: () => Array.from({length: triggers}, () => ({getHandlerFunction: () => 'processTaskQueue'}))},
    Utilities: {getUuid: () => 'uuid'}
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  const now = new Date('2026-09-02T00:00:00.000Z');
  const result = vm.runInContext('runNotebookLmMaxSafeCapacityGovernor5mIfDue_', context)(now);
  const route = vm.runInContext('verifyNotebookLmCapacityGovernorRouteV1', context)();
  return {result, route, queue, qa};
}

const stale = runCase({heartbeat:'', uiState:'POSITIVE_UI_PASS'});
assert.equal(stale.result.status, 'TABLET_RECOVERY_ARMED');
assert.equal(stale.result.pending, 2);
assert.equal(stale.result.workflowContinues, true);
assert.equal(stale.result.blockingScope, 'NOTEBOOKLM_UI_ONLY');
assert.equal(stale.queue.writes.length, 0);

const one = runCase({heartbeat:'2026-09-01T23:55:00.000Z', uiState:'POSITIVE_UI_PASS'});
assert.equal(one.result.status, 'MAX_SAFE_CAPACITY_CLAIMED');
assert.equal(one.result.claimed, 1);
assert.equal(one.result.safeSlots, 1);
assert.equal(one.queue.rows[1][4], 'CLAIMED_TABLET_MAX_SAFE_CAPACITY');
assert.equal(one.queue.rows[2][4], 'READY');

const two = runCase({heartbeat:'2026-09-01T23:55:00.000Z', uiState:'POSITIVE_UI_PASS', notes:'SAFE_CONCURRENCY=2'});
assert.equal(two.result.claimed, 2);
assert.equal(two.result.safeSlots, 2);
assert.equal(two.queue.rows[3][4], 'READY');

const duplicate = runCase({heartbeat:'2026-09-01T23:55:00.000Z', uiState:'POSITIVE_UI_PASS', triggers:2});
assert.equal(duplicate.route.ok, false);
assert.equal(duplicate.route.status, 'DUPLICATE_PHYSICAL_WAKE_HOLD');

assert.equal(one.route.ok, true);
assert.equal(one.route.status, 'EXISTING_5M_WAKE_REUSED');

console.log(JSON.stringify({
  tests: 6,
  status: 'PASS',
  stale: stale.result,
  defaultCapacity: one.result,
  provenCapacity: two.result,
  duplicateTrigger: duplicate.route,
  singleTrigger: one.route
}, null, 2));
