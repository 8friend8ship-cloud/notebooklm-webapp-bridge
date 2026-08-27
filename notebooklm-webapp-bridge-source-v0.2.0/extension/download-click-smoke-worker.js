const SMOKE_KEY='nlmDownloadClickSmoke_0_2_66';
async function triggerDownloadClickSmoke(){
  try{
    const state=await chrome.storage.local.get(SMOKE_KEY);
    if(state[SMOKE_KEY]?.done) return;
    const tabs=await chrome.tabs.query({url:['https://notebook.google.com/*','https://notebooklm.google.com/*']});
    for(const tab of tabs){
      if(!tab?.id) continue;
      try{
        await chrome.scripting.executeScript({target:{tabId:tab.id},files:['content/download-click-smoke.js']});
        return;
      }catch{}
    }
    await chrome.storage.local.set({[SMOKE_KEY]:{done:false,status:'NO_NOTEBOOK_TAB',at:new Date().toISOString()}});
  }catch{}
}
chrome.runtime.onInstalled.addListener(()=>{setTimeout(triggerDownloadClickSmoke,1500);});
chrome.runtime.onStartup.addListener(()=>{setTimeout(triggerDownloadClickSmoke,1500);});
setTimeout(triggerDownloadClickSmoke,1800);
