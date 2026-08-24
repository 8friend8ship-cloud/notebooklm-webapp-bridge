import "./background.js";

const LP_SOURCE = "notebooklm-webapp-bridge";
const LP_CONFIG_KEY = "nlmBridgeConfig";
const LP_SESSION_KEYS = ["homeDesignBridgeSessionV7", "nlmPersistentSessionV5"];
const LP_ALARM = "local-powershell-ready-poll";
const LP_HOST = "http://127.0.0.1:8765";
const LP_MAX = 1;

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
async function lpApi(url,payload){
  if(!/^https:\/\/script\.google\.com\/macros\/s\//.test(url||"")) throw new Error("Apps Script URL missing");
  const r=await fetch(url,{method:"POST",redirect:"follow",headers:{"Content-Type":"text/plain;charset=utf-8"},body:JSON.stringify(payload)});
  const data=await r.json();
  if(!r.ok||!data.ok) throw new Error(data.error||`HTTP ${r.status}`);
  return data;
}
async function lpHost(task){
  const r=await fetch(`${LP_HOST}/run`,{
    method:"POST",
    headers:{"Content-Type":"application/json"},
    body:JSON.stringify({source:LP_SOURCE,task})
  });
  const data=await r.json().catch(()=>({ok:false,error:`HTTP ${r.status}`}));
  if(!r.ok||!data.ok) throw new Error(data.error||`Local host HTTP ${r.status}`);
  return data;
}
async function lpPoll(reason="alarm"){
  const config=await lpConfig();
  if(!config.appsScriptUrl) return {ok:true,skipped:"api_not_configured"};
  const sessionToken=await lpSession();
  if(!sessionToken) return {ok:true,skipped:"no_session"};

  const listed=await lpApi(config.appsScriptUrl,{action:"listTasks",sessionToken});
  const tasks=(Array.isArray(listed.tasks)?listed.tasks:[]).filter(t=>
    String(t.taskType||"").toUpperCase()==="LOCAL_POWERSHELL" &&
    ["READY","RETRY","ERROR"].includes(String(t.status||"READY").toUpperCase())
  );

  let processed=0;
  for(const task of tasks.slice(0,LP_MAX)){
    try{
      const profile=await chrome.identity.getProfileUserInfo({accountStatus:"ANY"}).catch(()=>({email:""}));
      const claimed=await lpApi(config.appsScriptUrl,{
        action:"claimTask",sessionToken,taskId:task.taskId,chromeProfileEmail:profile.email||""
      });
      const result=await lpHost(claimed.task);
      await lpApi(config.appsScriptUrl,{
        action:"completeTask",
        sessionToken,
        taskId:task.taskId,
        result:{resultText:JSON.stringify(result,null,2),resultUrls:[],notebookUrl:""}
      });
      processed++;
    }catch(error){
      try{
        await lpApi(config.appsScriptUrl,{
          action:"updateTask",sessionToken,taskId:task.taskId,status:"ERROR",patch:{error:String(error?.message||error)}
        });
      }catch{}
    }
  }
  return {ok:true,reason,processed,available:tasks.length};
}
async function lpEnsureAlarm(){
  await chrome.alarms.clear(LP_ALARM);
  await chrome.alarms.create(LP_ALARM,{delayInMinutes:0.2,periodInMinutes:1});
}
chrome.alarms.onAlarm.addListener(alarm=>{if(alarm.name===LP_ALARM) lpPoll("alarm").catch(()=>{});});
chrome.runtime.onInstalled.addListener(()=>lpEnsureAlarm().then(()=>lpPoll("installed")).catch(()=>{}));
chrome.runtime.onStartup.addListener(()=>lpEnsureAlarm().then(()=>lpPoll("startup")).catch(()=>{}));
lpEnsureAlarm().then(()=>lpPoll("worker-load")).catch(()=>{});
