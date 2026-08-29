import { CONFIG } from './config.js';
const VERSION='1.0.2';
chrome.runtime.onInstalled.addListener(()=>chrome.alarms.create('bridgeTick',{periodInMinutes:1}));
chrome.runtime.onStartup.addListener(()=>chrome.alarms.create('bridgeTick',{periodInMinutes:1}));
chrome.alarms.onAlarm.addListener(a=>{ if(a.name==='bridgeTick') tick(); });

async function api(action,extra={}) {
  const res=await fetch(CONFIG.webAppUrl,{method:'POST',headers:{'content-type':'text/plain;charset=utf-8'},body:JSON.stringify({token:CONFIG.token,action,runnerId:CONFIG.runnerId,...extra})});
  if(!res.ok) throw new Error(`HTTP ${res.status}`); return res.json();
}

async function tick(){
  try {
    await api('heartbeat',{label:CONFIG.label,version:VERSION});
    const claimed=await api('claim'); if(!claimed.task)return;
    await runTask(claimed.task);
  } catch(e) { console.error('bridge tick failed',e); }
}

async function runTask(task){
  try {
    const target=task.target==='FLOW'?'https://labs.google/fx/tools/flow':'https://notebooklm.google.com/';
    const tab=await chrome.tabs.create({url:target,active:false});
    await waitForTab(tab.id);
    const current=await chrome.tabs.get(tab.id);
    if(String(current?.url||'').includes('accounts.google.com')){
      await api('complete',{taskId:task.taskId,status:'NEEDS_USER',result:{version:VERSION,generateClicked:false,creditSpend:false},error:'Google login required'});
      return;
    }
    const result=await chrome.tabs.sendMessage(tab.id,{type:'RUN_BRIDGE_TASK',task});
    await api('complete',{taskId:task.taskId,status:result?.status||'FAILED',result:result||{},error:result?.error||''});
  } catch(e) { await api('complete',{taskId:task.taskId,status:'FAILED',error:String(e.message||e)}); }
}

function waitForTab(tabId){return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{chrome.tabs.onUpdated.removeListener(on);reject(new Error('tab timeout'));},45000);function on(id,info){if(id===tabId&&info.status==='complete'){clearTimeout(timer);chrome.tabs.onUpdated.removeListener(on);setTimeout(resolve,2500);}}chrome.tabs.onUpdated.addListener(on);});}
