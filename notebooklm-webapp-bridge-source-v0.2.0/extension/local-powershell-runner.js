import "./background.js";

const SOURCE="notebooklm-webapp-bridge";
const CONFIG_KEY="nlmBridgeConfig";
const SESSION_KEYS=["homeDesignBridgeSessionV7","nlmPersistentSessionV5"];
const ACTIVE_KEY="nlmLocalPowerShellAsyncActiveV2";
const AUTH_KEY="nlmLocalPowerShellAsyncAuthV1";
const ALARM="local-powershell-async-poll";
const HOST="http://127.0.0.1:8765";
const ASYNC_TYPE="LOCAL_POWERSHELL_ASYNC";
const CANONICAL_API="https://script.google.com/macros/s/AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P/exec";
const CONTROL_ORIGIN="https://notebooklm-webapp-bridge.vercel.app";
const DEFAULT_TIMEOUT=600;
const STALE_GRACE=60;
const HANDOFF_GRACE=45;
const PENDING_STAGE="CLAIMED_PENDING_HOST";
const STARTED_STAGE="HOST_STARTED";
let busy=false;

async function config(){const s=await chrome.storage.local.get(CONFIG_KEY);const v=s[CONFIG_KEY]||{};return {...v,appsScriptUrl:v.appsScriptUrl||CANONICAL_API,frontendOrigin:v.frontendOrigin||CONTROL_ORIGIN};}
async function sessionToken(){const s=await chrome.storage.local.get(SESSION_KEYS);for(const k of SESSION_KEYS){const v=s[k];const t=typeof v==="string"?v:v?.token;if(t)return String(t);}return "";}
async function getActive(){const s=await chrome.storage.local.get(ACTIVE_KEY);return s[ACTIVE_KEY]||null;}
async function setActive(v){if(v)await chrome.storage.local.set({[ACTIVE_KEY]:v});else await chrome.storage.local.remove(ACTIVE_KEY);}
function field(t,...names){for(const n of names){const v=t?.[n];if(v!==undefined&&v!==null&&v!=="")return v;}return undefined;}
function taskId(t){return String(field(t,"taskId","TASK_ID")||"");}
function taskType(t){return String(field(t,"taskType","TASK_TYPE")||"").toUpperCase();}
function taskStatus(t){return String(field(t,"status","STATUS")||"READY").toUpperCase();}
function taskOwner(t){return String(field(t,"ownerEmail","OWNER_EMAIL")||"").toLowerCase();}
function timeoutSeconds(t){const n=Number(field(t,"timeoutSeconds","TIMEOUT_SECONDS","timeout_seconds")??DEFAULT_TIMEOUT);return Number.isFinite(n)&&n>0?Math.max(30,Math.min(1800,Math.round(n))):DEFAULT_TIMEOUT;}
function parseTime(v){const n=Date.parse(String(v||""));return Number.isFinite(n)?n:0;}
function claimedTime(t){return parseTime(field(t,"claimedAt","CLAIMED_AT"));}
function startedTime(t){return parseTime(field(t,"startedAt","STARTED_AT"));}
function taskTime(t){for(const k of ["claimedAt","CLAIMED_AT","startedAt","STARTED_AT","updatedAt","UPDATED_AT","createdAt","CREATED_AT"]){const n=parseTime(t?.[k]);if(n)return n;}return 0;}
function staleClaim(t){
  if(taskType(t)!==ASYNC_TYPE||taskStatus(t)!=="CLAIMED")return false;
  const claimed=claimedTime(t)||taskTime(t);if(!claimed)return false;
  const started=startedTime(t);
  const limitSec=started?(timeoutSeconds(t)+STALE_GRACE):HANDOFF_GRACE;
  return Date.now()-claimed>limitSec*1000;
}
function isSessionError(e){return /로그인 세션|세션.*만료|세션 서명|session/i.test(String(e?.message||e||""));}
async function wakeControlCenter(cfg,reason="AUTH_REQUIRED"){const now=Date.now();const a=(await chrome.storage.local.get(AUTH_KEY))[AUTH_KEY]||{};await chrome.storage.local.set({[AUTH_KEY]:{reason,updatedAt:new Date().toISOString(),lastWakeAt:a.lastWakeAt||0}});if(now-Number(a.lastWakeAt||0)<120000)return;await chrome.storage.local.set({[AUTH_KEY]:{reason,updatedAt:new Date().toISOString(),lastWakeAt:now}});const base=String(cfg?.frontendOrigin||CONTROL_ORIGIN).replace(/\/$/,"");try{const tabs=await chrome.tabs.query({url:`${base}/*`});if(tabs[0]?.id)await chrome.tabs.update(tabs[0].id,{url:`${base}/`,active:true});else await chrome.tabs.create({url:`${base}/`,active:true});}catch{}}
async function clearExpiredSessionAndWake(cfg,error){await chrome.storage.local.remove(SESSION_KEYS);await wakeControlCenter(cfg,String(error?.message||error||"SESSION_EXPIRED"));}
async function api(url,payload){if(!/^https:\/\/script\.google\.com\/macros\/s\//.test(url||""))throw new Error("Apps Script URL missing");const r=await fetch(url,{method:"POST",redirect:"follow",headers:{"Content-Type":"text/plain;charset=utf-8"},body:JSON.stringify(payload)});const d=await r.json();if(!r.ok||!d.ok)throw new Error(d.error||`HTTP ${r.status}`);return d;}
async function hostJson(url,options={}){const c=new AbortController();const timer=setTimeout(()=>c.abort(),12000);try{const r=await fetch(url,{...options,signal:c.signal});const d=await r.json().catch(()=>({ok:false,error:`HTTP ${r.status}`}));if(!r.ok||!d.ok)throw new Error(d.error||`Local host HTTP ${r.status}`);return d;}finally{clearTimeout(timer);}}
async function hostHealth(){return hostJson(`${HOST}/health`);}
function hostCompatibleTask(t){return {...t,taskType:"LOCAL_POWERSHELL",TASK_TYPE:"LOCAL_POWERSHELL"};}
async function hostStart(t){return hostJson(`${HOST}/run`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({source:SOURCE,task:hostCompatibleTask(t)})});}
async function hostResult(id){return hostJson(`${HOST}/result?taskId=${encodeURIComponent(id)}`);}
async function hostCancel(id){return hostJson(`${HOST}/cancel`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({taskId:id})});}
async function releaseClaim(cfg,token,id,reason){
  try{await api(cfg.appsScriptUrl,{action:"updateTask",sessionToken:token,taskId:id,status:"HOLD_RECOVERY",patch:{error:reason,clearClaim:true,claimedAt:"",startedAt:""}});return true;}catch(error){if(isSessionError(error))await wakeControlCenter(cfg,String(error?.message||error));return false;}
}
async function recoverStale(cfg,token,tasks){for(const t of tasks){if(!staleClaim(t))continue;const id=taskId(t);const reason=startedTime(t)?`D30_STALE_RUNNING_CLAIM_HOLD_AFTER_${timeoutSeconds(t)}s`:`D61_UNSTARTED_CLAIM_LEASE_EXPIRED_${HANDOFF_GRACE}s`;await releaseClaim(cfg,token,id,reason);}}

async function markStarted(cfg,token,id){try{await api(cfg.appsScriptUrl,{action:"updateTask",sessionToken:token,taskId:id,status:"STARTED",patch:{}});return true;}catch(error){if(isSessionError(error))await wakeControlCenter(cfg,String(error?.message||error));return false;}}

async function resumePendingHandoff(cfg,token,active){
  const id=String(active?.taskId||"");
  const task=active?.task||null;
  if(!id||active?.stage!==PENDING_STAGE||!task)return {handled:false};
  let existing=null;
  try{existing=await hostResult(id);}catch{}
  const state=String(existing?.state||"").toUpperCase();
  if(["RUNNING","STARTED"].includes(state)){
    const next={...active,stage:STARTED_STAGE,startedAtMs:Number(active.startedAtMs||Date.now()),hostState:state,resumedBy:"HOST_RESULT"};
    await setActive(next);await markStarted(cfg,token,id);return {handled:true,state,taskId:id};
  }
  if(state==="DONE"){
    const next={...active,stage:STARTED_STAGE,startedAtMs:Number(active.startedAtMs||active.claimedAtMs||Date.now()),hostState:"DONE",resumedBy:"HOST_RESULT_DONE"};
    await setActive(next);return {handled:true,state:"DONE",taskId:id,continueFinalize:true};
  }
  try{
    await hostHealth();
    const started=await hostStart(task);
    const next={...active,stage:STARTED_STAGE,startedAtMs:Date.now(),hostState:started.state||"STARTED",resumedBy:active.adoptedOrphan?"D30_ORPHAN_CLAIM_ADOPT":"D28_PENDING_HANDOFF"};
    await setActive(next);await markStarted(cfg,token,id);
    return {handled:true,state:String(started.state||"STARTED"),taskId:id};
  }catch(error){
    const age=Date.now()-Number(active.claimedAtMs||Date.now());
    if(age<HANDOFF_GRACE*1000)return {handled:true,state:"WAIT_PENDING_HOST",taskId:id,error:String(error?.message||error)};
    await releaseClaim(cfg,token,id,`D61_CLAIM_HOST_HANDOFF_HOLD_${HANDOFF_GRACE}S:${String(error?.message||error)}`);
    await setActive(null);
    return {handled:true,state:"HOLD_RECOVERY",taskId:id,error:String(error?.message||error)};
  }
}

async function finalize(cfg,token,active){
  const id=String(active?.taskId||"");if(!id){await setActive(null);return {state:"EMPTY"};}
  if(active?.stage===PENDING_STAGE){const resumed=await resumePendingHandoff(cfg,token,active);if(resumed.handled&&!resumed.continueFinalize)return resumed;active=await getActive();if(!active)return resumed;}
  const age=Date.now()-Number(active.startedAtMs||active.claimedAtMs||Date.now());const hard=(Number(active.timeoutSeconds||DEFAULT_TIMEOUT)+120)*1000;let host;
  try{host=await hostResult(id);}catch(error){if(age<=hard)return {state:"WAIT_HOST",error:String(error?.message||error)};try{await hostCancel(id);}catch{};await releaseClaim(cfg,token,id,"D30_LOCAL_ASYNC_HOST_RESULT_TIMEOUT");await setActive(null);return {state:"TIMEOUT_HOLD"};}
  if(["RUNNING","STARTED"].includes(String(host.state||""))){if(age<=hard)return {state:String(host.state),taskId:id};try{await hostCancel(id);}catch{};await releaseClaim(cfg,token,id,"D30_LOCAL_ASYNC_HARD_TIMEOUT_HOLD");await setActive(null);return {state:"HARD_TIMEOUT_HOLD",taskId:id,ageMs:age};}
  if(host.state==="DONE"){const result=host.result||{};try{if(result.ok)await api(cfg.appsScriptUrl,{action:"completeTask",sessionToken:token,taskId:id,result:{resultText:JSON.stringify(result,null,2),resultUrls:[],notebookUrl:""}});else{const detail=String(result.stderr||result.error||result.stdout||`LOCAL_EXIT_${result.exitCode??"UNKNOWN"}`);await api(cfg.appsScriptUrl,{action:"updateTask",sessionToken:token,taskId:id,status:"ERROR",patch:{error:detail}});}}catch(error){if(isSessionError(error)){await clearExpiredSessionAndWake(cfg,error);return {state:"WAIT_AUTH",taskId:id};}if(/TASK_ID/i.test(String(error?.message||error))){await setActive(null);return {state:"ORPHAN_RESULT_CLEARED",taskId:id,error:String(error?.message||error)};}throw error;}await setActive(null);return {state:result.ok?"COMPLETED":"FAILED",taskId:id};}
  if(["ERROR","NOT_FOUND"].includes(String(host.state||""))){await releaseClaim(cfg,token,id,`D30_LOCAL_HOST_${String(host.error||host.state)}`);await setActive(null);return {state:`${String(host.state)}_HOLD`,taskId:id};}
  return {state:String(host.state||"UNKNOWN"),taskId:id};
}

async function adoptRecentClaimed(cfg,token,tasks,profileEmail){
  const email=String(profileEmail||"").toLowerCase();
  const candidates=tasks.filter(t=>taskType(t)===ASYNC_TYPE&&taskStatus(t)==="CLAIMED"&&!staleClaim(t)&&taskId(t)).filter(t=>!taskOwner(t)||!email||taskOwner(t)===email).sort((a,b)=>(taskTime(a)||0)-(taskTime(b)||0));
  if(!candidates.length)return null;
  const t=candidates[0],id=taskId(t),claimedAtMs=claimedTime(t)||taskTime(t)||Date.now();
  await setActive({taskId:id,timeoutSeconds:timeoutSeconds(t),claimedAtMs,stage:PENDING_STAGE,task:t,adoptedOrphan:true});
  return finalize(cfg,token,await getActive());
}

function activeStableTime(active){
  const direct=Number(active?.startedAtMs||active?.claimedAtMs||0);
  if(Number.isFinite(direct)&&direct>0)return direct;
  const derived=taskTime(active?.task||{});
  return Number.isFinite(derived)&&derived>0?derived:0;
}
function queueTaskLiveForActive(t){
  const s=taskStatus(t);
  return ["CLAIMED","STARTED","RUNNING","NOTEBOOK_OPENED"].includes(s);
}
async function reconcileActive(cfg,token,active,listedTasks){
  const id=String(active?.taskId||"");
  if(!id){await setActive(null);return {cleared:true,reason:"LEGACY_ACTIVE_NO_TASK_ID"};}
  const queued=(listedTasks||[]).find(t=>taskId(t)===id)||null;
  if(queued&&!queueTaskLiveForActive(queued)){
    await setActive(null);
    return {cleared:true,reason:`ACTIVE_QUEUE_NOT_LIVE_${taskStatus(queued)}`,taskId:id};
  }
  if(!queued){
    let host=null;try{host=await hostResult(id);}catch{}
    const hs=String(host?.state||"").toUpperCase();
    if(!["RUNNING","STARTED"].includes(hs)){
      await setActive(null);
      return {cleared:true,reason:`ACTIVE_ORPHAN_QUEUE_MISSING_HOST_${hs||"UNKNOWN"}`,taskId:id};
    }
  }
  const stable=activeStableTime(active);
  if(!stable){
    const next={...active,claimedAtMs:Date.now(),legacyTimestampRecovered:true,legacyRecoveredAt:new Date().toISOString()};
    await setActive(next);
    return {cleared:false,active:next,reason:"LEGACY_ACTIVE_TIMESTAMP_ANCHORED"};
  }
  return {cleared:false,active,reason:"ACTIVE_RECONCILED"};
}
function activeStableTime(active){
  const direct=Number(active?.startedAtMs||active?.claimedAtMs||0);
  if(Number.isFinite(direct)&&direct>0)return direct;
  const derived=taskTime(active?.task||{});
  return Number.isFinite(derived)&&derived>0?derived:0;
}
function queueTaskLiveForActive(t){
  const s=taskStatus(t);
  return ["CLAIMED","STARTED","RUNNING","NOTEBOOK_OPENED"].includes(s);
}
async function reconcileActive(cfg,token,active,listedTasks){
  const id=String(active?.taskId||"");
  if(!id){await setActive(null);return {cleared:true,reason:"LEGACY_ACTIVE_NO_TASK_ID"};}
  const queued=(listedTasks||[]).find(t=>taskId(t)===id)||null;
  if(queued&&!queueTaskLiveForActive(queued)){
    await setActive(null);
    return {cleared:true,reason:`ACTIVE_QUEUE_NOT_LIVE_${taskStatus(queued)}`,taskId:id};
  }
  if(!queued){
    let host=null;try{host=await hostResult(id);}catch{}
    const hs=String(host?.state||"").toUpperCase();
    if(!["RUNNING","STARTED"].includes(hs)){
      await setActive(null);
      return {cleared:true,reason:`ACTIVE_ORPHAN_QUEUE_MISSING_HOST_${hs||"UNKNOWN"}`,taskId:id};
    }
  }
  const stable=activeStableTime(active);
  if(!stable){
    const next={...active,claimedAtMs:Date.now(),legacyTimestampRecovered:true,legacyRecoveredAt:new Date().toISOString()};
    await setActive(next);
    return {cleared:false,active:next,reason:"LEGACY_ACTIVE_TIMESTAMP_ANCHORED"};
  }
  return {cleared:false,active,reason:"ACTIVE_RECONCILED"};
}
async function pollCore(reason="alarm"){
  const cfg=await config();const token=await sessionToken();if(!token){await wakeControlCenter(cfg,"NO_SESSION");return {ok:true,skipped:"no_session",authRefreshRequested:true};}
  let listed;try{listed=await api(cfg.appsScriptUrl,{action:"listTasks",sessionToken:token,includeClaimed:true});}catch(error){if(isSessionError(error)){await clearExpiredSessionAndWake(cfg,error);return {ok:true,reason,skipped:"session_refresh_requested"};}throw error;}
  const listedTasks=Array.isArray(listed.tasks)?listed.tasks:[];
  const active=await getActive();
  if(active){
    const reconciled=await reconcileActive(cfg,token,active,listedTasks);
    if(!reconciled.cleared)return {ok:true,reason,active:await finalize(cfg,token,reconciled.active)};
  }
  await recoverStale(cfg,token,listedTasks);
  const profile=await chrome.identity.getProfileUserInfo({accountStatus:"ANY"}).catch(()=>({email:""}));
  const adopted=await adoptRecentClaimed(cfg,token,listedTasks,profile.email||"");
  if(adopted)return {ok:true,reason,adopted};
  const map=new Map();for(const t of listedTasks){if(taskType(t)!==ASYNC_TYPE)continue;if(!["READY","RETRY"].includes(taskStatus(t)))continue;if(taskId(t))map.set(taskId(t),t);}const tasks=[...map.values()];
  if(!tasks.length)return {ok:true,reason,processed:0,asyncAvailable:0};
  const t=tasks[0],id=taskId(t);
  try{await hostHealth();}catch(error){return {ok:false,reason,skipped:"local_host_unavailable_before_claim",taskId:id,error:String(error?.message||error)};}
  let claimed;try{claimed=await api(cfg.appsScriptUrl,{action:"claimTask",sessionToken:token,taskId:id,chromeProfileEmail:profile.email||""});}catch(error){if(isSessionError(error)){await clearExpiredSessionAndWake(cfg,error);return {ok:true,reason,skipped:"session_refresh_requested"};}throw error;}
  const claimedTask=claimed.task||t;
  const claimedAtMs=Date.now();
  await setActive({taskId:id,timeoutSeconds:timeoutSeconds(claimedTask),claimedAtMs,stage:PENDING_STAGE,task:claimedTask});
  let started;
  try{started=await hostStart(claimedTask);}catch(error){
    await releaseClaim(cfg,token,id,`D61_INITIAL_HOST_START_FAILED:${String(error?.message||error)}`);
    await setActive(null);
    return {ok:false,reason,state:"HOST_START_FAILED_CLAIM_RELEASED",taskId:id,error:String(error?.message||error)};
  }
  await setActive({taskId:id,timeoutSeconds:timeoutSeconds(claimedTask),claimedAtMs,startedAtMs:Date.now(),stage:STARTED_STAGE,task:claimedTask,hostState:started.state||"STARTED"});
  const marked=await markStarted(cfg,token,id);
  return {ok:true,reason,started:id,hostState:started.state||"STARTED",startMarkerWritten:marked,asyncAvailable:tasks.length};
}
async function poll(reason="alarm"){if(busy)return {ok:true,skipped:"busy"};busy=true;try{return await pollCore(reason);}catch(error){return {ok:false,reason,error:String(error?.message||error)};}finally{busy=false;}}
async function ensureAlarm(){await chrome.alarms.clear(ALARM);await chrome.alarms.create(ALARM,{delayInMinutes:0.2,periodInMinutes:1});}
chrome.alarms.onAlarm.addListener(a=>{if(a.name===ALARM)poll("alarm").catch(()=>{});});
chrome.runtime.onInstalled.addListener(()=>ensureAlarm().then(()=>poll("installed")).catch(()=>{}));
chrome.runtime.onStartup.addListener(()=>ensureAlarm().then(()=>poll("startup")).catch(()=>{}));
ensureAlarm().then(()=>poll("worker-load")).catch(()=>{});
