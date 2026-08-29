import fs from 'node:fs';
const code=fs.readFileSync('notebooklm-webapp-bridge-source-v0.2.0/apps-script/Code.gs','utf8').replace(/\r\n/g,'\n');
const required=[
  ['version','0.2.10-queue-lock'],
  ['script lock','LockService.getScriptLock()'],
  ['lock timeout','TASK_QUEUE_LOCK_TIMEOUT'],
  ['row id guard','TASK_ROW_ID_MISMATCH'],
  ['row mutation guard','TASK_ROW_ID_MUTATION_BLOCKED'],
  ['claim locked','function claimTask_(session,body){\n  return withQueueLock_'],
  ['update locked','function updateTask_(session,body){\n  return withQueueLock_'],
  ['complete locked','const out=withQueueLock_'],
  ['append locked','function appendTask_(task,ownerEmail){\n  return withQueueLock_'],
  ['duplicate task id idempotency','idempotent:true,rowNumber:duplicate.rowNumber'],
  ['done idempotency','if(String(item.data.STATUS)==="DONE")'],
  ['single-row atomic set','getRange(rowNumber,1,1,HEADERS.length).setValues'],
  ['expected task id before write','setTask_(item.rowNumber,write,body.taskId)']
];
for(const [name,needle] of required){if(!code.includes(needle)){throw new Error(`QUEUE_INTEGRITY_STATIC_FAIL ${name}: missing ${needle}`)}}
if(/function appendTask_[\s\S]*?appendRow\(/.test(code)){throw new Error('QUEUE_INTEGRITY_STATIC_FAIL appendTask still uses appendRow')}
console.log(JSON.stringify({ok:true,action:'APPS_SCRIPT_QUEUE_INTEGRITY_STATIC',checks:required.length,noAppendRow:true}));