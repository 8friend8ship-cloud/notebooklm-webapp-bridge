import fs from 'node:fs';
import assert from 'node:assert/strict';

const src = fs.readFileSync('apps-script/TabletTrafficHourlyManager.gs', 'utf8');

const required = [
  'function runTabletTrafficHourlyManagerV1',
  "notebookPrimaryJob: 'TASK_TABLET_NOTEBOOKLM_E2E_20260901_1005'",
  "lockKey: 'LOCK_TABLET_ANDROID_01_UI'",
  "getSheetByName('TRAFFIC_HOURLY')",
  'automate_acc',
  'BLOCKED_ACCESSIBILITY',
  'BLOCKED_UI_CONCURRENCY_GT_1',
  'HOLD_TRAFFIC_LOCK_NOTEBOOKLM_PRIMARY',
  'KEEP_SCREEN_ON',
  'noScreenOffGate=true',
  'TABLET_TRAFFIC_HOURLY_CHANGED_EVIDENCE'
];
for (const token of required) assert.ok(src.includes(token), `missing contract token: ${token}`);

assert.ok(src.includes('LockService.getScriptLock()'), 'must use script lock');
assert.ok(src.includes('heartbeatAgeSec > cfg.staleHeartbeatSec'), 'must enforce stale heartbeat gate');
assert.ok(src.includes('activeUiJobs.length > 1'), 'must enforce one active UI job');
assert.ok(src.includes('automateAcc !== 1'), 'must fail closed when accessibility is disabled');
assert.ok(!src.includes('ScriptApp.newTrigger'), 'function must not create a physical trigger');
assert.ok(!src.includes('ScriptApp.deleteTrigger'), 'function must not delete triggers');
assert.ok(!src.includes('DriveApp.getFilesByName'), 'must use exact file IDs, not filename discovery');
assert.ok(!/deleteRow\s*\(/.test(src), 'must not delete queue jobs');
assert.ok(!/removeFile|setTrashed\s*\(/.test(src), 'must preserve existing files/jobs');

console.log('tablet traffic hourly manager contract PASS');
