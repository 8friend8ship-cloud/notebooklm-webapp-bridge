const HD_CHAT_ACTIVE_KEY="nlmAutoRunnerStateV025";
const HD_CHAT_CONFIG_KEY="nlmBridgeConfig";
const HD_CHAT_SESSION_KEYS=["homeDesignBridgeSessionV7","nlmPersistentSessionV5"];
const HD_CHAT_GUARD_ALARM="nlm-chat-active-guard";
const HD_CHAT_CANONICAL_API="https://script.google.com/macros/s/AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P/exec";
const HD_CHAT_TERMINAL=new Set(["DONE","ERROR","HOLD_RECOVERY","CANCELLED","CANCELED","COMPLETE","COMPLETED"]);
let hdChatGuardBusy=false;

async function hdChatGuardSession(){
  const stored=await chrome.storage.local.get(HD_CHAT_SESSION_KEYS);
  for(const key of HD_CHAT_SESSION_KEYS){const value=stored[key];const token=typeof value==="string"?value:value?.token;if(token)return String(token);}
  return "";
}
async function hdChatGuardApiUrl(){
  const stored=await chrome.storage.local.get(HD_CHAT_CONFIG_KEY);
  return String(stored?.[HD_CHAT_CONFIG_KEY]?.appsScriptUrl||HD_CHAT_CANONICAL_API);
}
async function hdChatGuardList(apiUrl,sessionToken){
  const response=await fetch(apiUrl,{method:"POST",redirect:"follow",headers:{"Content-Type":"text/plain;charset=utf-8"},body:JSON.stringify({action:"listTasks",sessionToken,includeClaimed:true})});
  const data=await response.json();
  if(!response.ok||!data?.ok)throw new Error(data?.error||`HTTP_${response.status}`);
  return Array.isArray(data.tasks)?data.tasks:[];
}
function hdChatTaskId(task){return String(task?.taskId||task?.TASK_ID||"");}
function hdChatTaskStatus(task){return String(task?.status||task?.STATUS||"").toUpperCase();}
async function hdChatClear(reason,taskStatus=""){
  const stored=await chrome.storage.local.get(HD_CHAT_ACTIVE_KEY);
  const state=stored?.[HD_CHAT_ACTIVE_KEY]||{};
  await chrome.storage.local.set({[HD_CHAT_ACTIVE_KEY]:{...state,runningTaskId:"",busyUntil:0,lastError:reason,lastGuardStatus:taskStatus,lastGuardAt:new Date().toISOString()}});
}
async function hdChatActiveGuard(reason="alarm"){
  if(hdChatGuardBusy)return {ok:true,skipped:"busy"};
  hdChatGuardBusy=true;
  try{
    const stored=await chrome.storage.local.get(HD_CHAT_ACTIVE_KEY);
    const state=stored?.[HD_CHAT_ACTIVE_KEY]||{};
    const runningTaskId=String(state.runningTaskId||"");
    if(!runningTaskId)return {ok:true,skipped:"no_active"};
    const token=await hdChatGuardSession();
    if(!token)return {ok:true,skipped:"no_session",runningTaskId};
    const tasks=await hdChatGuardList(await hdChatGuardApiUrl(),token);
    const task=tasks.find(item=>hdChatTaskId(item)===runningTaskId);
    if(!task){await hdChatClear("D35_CHAT_ACTIVE_CLEARED_TASK_NOT_LISTED","NOT_LISTED");return {ok:true,cleared:true,runningTaskId,status:"NOT_LISTED",reason};}
    const status=hdChatTaskStatus(task);
    if(HD_CHAT_TERMINAL.has(status)){await hdChatClear(`D35_CHAT_ACTIVE_CLEARED_TERMINAL_${status}`,status);return {ok:true,cleared:true,runningTaskId,status,reason};}
    return {ok:true,cleared:false,runningTaskId,status,reason};
  }catch(error){return {ok:false,reason,error:String(error?.message||error)};}
  finally{hdChatGuardBusy=false;}
}
async function hdEnsureChatGuardAlarm(){
  try{const existing=await chrome.alarms.get(HD_CHAT_GUARD_ALARM);if(!existing)await chrome.alarms.create(HD_CHAT_GUARD_ALARM,{delayInMinutes:0.1,periodInMinutes:1});}catch{}
}
chrome.alarms.onAlarm.addListener(alarm=>{if(alarm.name===HD_CHAT_GUARD_ALARM)hdChatActiveGuard("alarm").catch(()=>{});});
chrome.runtime.onStartup.addListener(()=>hdEnsureChatGuardAlarm().then(()=>hdChatActiveGuard("startup")).catch(()=>{}));
chrome.runtime.onInstalled.addListener(()=>hdEnsureChatGuardAlarm().then(()=>hdChatActiveGuard("installed")).catch(()=>{}));
hdEnsureChatGuardAlarm().then(()=>hdChatActiveGuard("worker-load")).catch(()=>{});
