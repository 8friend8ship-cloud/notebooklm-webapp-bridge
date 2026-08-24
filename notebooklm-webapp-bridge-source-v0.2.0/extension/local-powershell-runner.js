import "./background.js";

const LP_SOURCE = "notebooklm-webapp-bridge";
const LP_CONFIG_KEY = "nlmBridgeConfig";
const LP_SESSION_KEYS = ["homeDesignBridgeSessionV7", "nlmPersistentSessionV5"];
const LP_ALARM = "local-powershell-ready-poll";
const LP_HOST = "http://127.0.0.1:8765";
const LP_MAX = 1;
const LP_DEFAULT_TIMEOUT_SECONDS = 600;
const LP_STALE_GRACE_SECONDS = 60;
let lpBusy=false;

async function lpConfig(){
  const stored=await chrome.storage.local.get(LP_CONFIG_KEY);
  return stored[LP_CONFIG_KEY]||{};
}
async function lpSession(){
  const stored=await chrome.storage.local.get(LP_SESSION_KEYS);
  for(const key of LP_SESSION_KEYS){
    const value=stored[key];
    const token=typeof value==="string"?value:value?.token;
    if(token) return String(token);
  }
  return "";
}
function lpTimeoutSeconds(task){
  const raw=Number(task?.timeoutSeconds??task?.TIMEOUT_SECONDS??task?.timeout_seconds??LP_DEFAULT_TIMEOUT_SECONDS);
  if(!Number.isFinite(raw)||raw<=0) return LP_DEFAULT_TIMEOUT_SECONDS;
  return Math.max(30,Math.min(1800,Math.round(raw)));
}
function lpParseTime(value){
  if(value instanceof Date) return value.getTime();
  if(typeof value==="number"&&Number.isFinite(value)) return value>1e12?value:value*1000;
  const text=String(value||"").trim();
  if(!text) return 0;
  const parsed=Date.parse(text);
  return Number.isFinite(parsed)?parsed:0;
}
function lpTaskTime(task){
  for(const key of ["claimedAt","CLAIMED_AT","startedAt","STARTED_AT","updatedAt","UPDATED_AT","createdAt","CREATED_AT"]){
    const parsed=lpParseTime(task?.[key]);
    if(parsed) return parsed;
  }
  const m=String(task?.taskId||"").match(/_(\d{8})_(\d{4})_/);
  if(m){
    const d=m[1],t=m[2];
    const iso=`${d.slice(0,4)}-${d.slice(4,6)}-${d.slice(6,8)}T${t.slice(0,2)}:${t.slice(2,4)}:00+09:00`;
    const parsed=Date.parse(iso);
    if(Number.isFinite(parsed)) return parsed;
  }
  return 0;
}
function lpIsStaleClaim(task){
  if(String(task?.status||task?.STATUS||"").toUpperCase()!=="CLAIMED") return false;
  const started=lpTaskTime(task);
  if(!started) return false;
  return Date.now()-started>(lpTimeoutSeconds(task)+LP_STALE_GRACE_SECONDS)*1000;
}
function lpIsClaimConflict(error){
  const text=String(error?.message||error||"");
  return text.includes("현재 실행할 수 없는 상태입니다: CLAIMED") || text.includes("TASK_ALREADY_CLAIMED");
}
async function lpApi(url,payload){
  if(!/^https:\/\/script\.google\.com\/macros\/s\//.test(url||"")) throw new Error("Apps Script URL missing");
  const r=await fetch(url,{method:"POST",redirect:"follow",headers:{"Content-Type":"text/plain;charset=utf-8"},body:JSON.stringify(payload)});
  const data=await r.json();
  if(!r.ok||!data.ok) throw new Error(data.error||`HTTP ${r.status}`);
  return data;
}
async function lpHost(task){
  const timeoutSeconds=lpTimeoutSeconds(task);
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),(timeoutSeconds+15)*1000);
  try{
    const r=await fetch(`${LP_HOST}/run`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({source:LP_SOURCE,task}),signal:controller.signal});
    const data=await r.json().catch(()=>({ok:false,error:`HTTP ${r.status}`}));
    if(!r.ok||!data.ok) throw new Error(data.error||`Local host HTTP ${r.status}`);
    return data;
  }catch(error){
    if(error?.name==="AbortError") throw new Error(`LOCAL_HOST_TIMEOUT_${timeoutSeconds}s`);
    throw error;
  }finally{clearTimeout(timer);}
}
async function lpRecoverStaleClaims(config,sessionToken,listedTasks){
  const recovered=[];
  for(const task of (Array.isArray(listedTasks)?listedTasks:[])){
    if(String(task?.taskType||"").toUpperCase()!=="LOCAL_POWERSHELL"||!lpIsStaleClaim(task)) continue;
    try{
      await lpApi(config.appsScriptUrl,{action:"updateTask",sessionToken,taskId:task.taskId,status:"RETRY",patch:{error:`STALE_CLAIM_RECOVERED_AFTER_${lpTimeoutSeconds(task)}s`,clearClaim:true,claimedAt:"",startedAt:""}});
      recovered.push({...task,status:"RETRY",claimedAt:"",startedAt:""});
    }catch{}
  }
  return recovered;
}
async function lpPollCore(reason="alarm"){
  const config=await lpConfig();
  if(!config.appsScriptUrl) return {ok:true,skipped:"api_not_configured"};
  const sessionToken=await lpSession();
  if(!sessionToken) return {ok:true,skipped:"no_session"};
  const listed=await lpApi(config.appsScriptUrl,{action:"listTasks",sessionToken,includeClaimed:true});
  const listedTasks=Array.isArray(listed.tasks)?listed.tasks:[];
  const recovered=await lpRecoverStaleClaims(config,sessionToken,listedTasks);
  const candidateMap=new Map();
  for(const task of [...recovered,...listedTasks]){
    if(String(task.taskType||"").toUpperCase()!=="LOCAL_POWERSHELL") continue;
    if(!["READY","RETRY","ERROR"].includes(String(task.status||"READY").toUpperCase())) continue;
    candidateMap.set(String(task.taskId),task);
  }
  const tasks=[...candidateMap.values()];
  let processed=0,claimConflicts=0;
  for(const task of tasks.slice(0,LP_MAX)){
    let claimed;
    try{
      const profile=await chrome.identity.getProfileUserInfo({accountStatus:"ANY"}).catch(()=>({email:""}));
      try{
        claimed=await lpApi(config.appsScriptUrl,{action:"claimTask",sessionToken,taskId:task.taskId,chromeProfileEmail:profile.email||""});
      }catch(error){
        if(lpIsClaimConflict(error)){claimConflicts++;continue;}
        throw error;
      }
      const result=await lpHost(claimed.task);
      await lpApi(config.appsScriptUrl,{action:"completeTask",sessionToken,taskId:task.taskId,result:{resultText:JSON.stringify(result,null,2),resultUrls:[],notebookUrl:""}});
      processed++;
    }catch(error){
      if(!claimed) continue;
      try{await lpApi(config.appsScriptUrl,{action:"updateTask",sessionToken,taskId:task.taskId,status:"ERROR",patch:{error:String(error?.message||error)}});}catch{}
    }
  }
  return {ok:true,reason,processed,available:tasks.length,claimConflicts,recoveredStaleClaims:recovered.map(t=>t.taskId)};
}
async function lpPoll(reason="alarm"){
  if(lpBusy) return {ok:true,skipped:"local_runner_busy",reason};
  lpBusy=true;
  try{return await lpPollCore(reason);}finally{lpBusy=false;}
}
async function lpEnsureAlarm(){
  await chrome.alarms.clear(LP_ALARM);
  await chrome.alarms.create(LP_ALARM,{delayInMinutes:0.2,periodInMinutes:1});
}
chrome.alarms.onAlarm.addListener(alarm=>{if(alarm.name===LP_ALARM) lpPoll("alarm").catch(()=>{});});
chrome.runtime.onInstalled.addListener(()=>lpEnsureAlarm().then(()=>lpPoll("installed")).catch(()=>{}));
chrome.runtime.onStartup.addListener(()=>lpEnsureAlarm().then(()=>lpPoll("startup")).catch(()=>{}));
lpEnsureAlarm().then(()=>lpPoll("worker-load")).catch(()=>{});
