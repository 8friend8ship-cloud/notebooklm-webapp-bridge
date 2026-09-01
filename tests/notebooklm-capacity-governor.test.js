const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const source = fs.readFileSync('apps-script/NotebookLmMaxSafeCapacityGovernor.gs','utf8');

function sheet(rows){const writes=[];return {rows,writes,getDataRange(){return{getValues:()=>rows}},getRange(r,c){return{setValue(v){writes.push({r,c,v});rows[r-1][c-1]=v}}},appendRow(r){writes.push({append:r})}}}
function scenario({heartbeat='',ui='POSITIVE_UI_PASS',notes='',triggers=1}){
 const queue=sheet([['TASK_ID','TASK_TYPE','TARGET_ID','ACTION','STATUS','OWNER','NOTES'],['T1','NOTEBOOKLM_SLIDES','APP_NLM_BRIDGE','CREATE_SLIDES','READY','',''],['T2','NOTEBOOKLM_SUMMARY','APP_NLM_BRIDGE','CREATE_SUMMARY','READY','',''],['T3','NOTEBOOKLM_AUDIO','APP_NLM_BRIDGE','REUSE COMPLETED AUDIO','READY','','']]);
 const runners=sheet([['RUNNER_ID','TARGET','CENTRAL_HEARTBEAT','UI_CONTROL_STATE','STATUS','NOTES'],['TABLET_ANDROID_01','NOTEBOOKLM_UI_AUTOMATION',heartbeat,ui,ui,notes]]);
 const qa=sheet([]); const ss={getSheetByName:n=>({'07_EXECUTION_QUEUE':queue,'51_LOCAL_BRIDGE_RUNNERS':runners,'80_DATA_RUNTIME_QA_LOG':qa}[n])};
 const c={Date,JSON,Math,Number,String,RegExp,LockService:{getScriptLock:()=>({tryLock:()=>true,releaseLock(){}})},SpreadsheetApp:{openById:()=>ss},ScriptApp:{getProjectTriggers:()=>Array.from({length:triggers},()=>({getHandlerFunction:()=> 'processTaskQueue'}))},Utilities:{getUuid:()=> 'uuid'}};
 vm.createContext(c); vm.runInContext(source,c);
 const result=vm.runInContext('runNotebookLmMaxSafeCapacityGovernor5mIfDue_',c)(new Date('2026-09-02T00:00:00Z'));
 const route=vm.runInContext('verifyNotebookLmCapacityGovernorRouteV1',c)();
 return {result,route,queue};
}
const stale=scenario({}); assert.equal(stale.result.status,'TABLET_PRIMARY_HOLD'); assert.equal(stale.queue.writes.length,0);
const one=scenario({heartbeat:'2026-09-01T23:55:00Z'}); assert.equal(one.result.claimed,1); assert.equal(one.result.safeSlots,1); assert.equal(one.queue.rows[2][4],'READY');
const two=scenario({heartbeat:'2026-09-01T23:55:00Z',notes:'SAFE_CONCURRENCY=2'}); assert.equal(two.result.claimed,2); assert.equal(two.queue.rows[3][4],'READY');
const dup=scenario({heartbeat:'2026-09-01T23:55:00Z',triggers:2}); assert.equal(dup.route.status,'DUPLICATE_PHYSICAL_WAKE_HOLD');
assert.equal(one.route.status,'EXISTING_5M_WAKE_REUSED');
console.log('NotebookLM max-safe-capacity governor: 5 tests PASS');
