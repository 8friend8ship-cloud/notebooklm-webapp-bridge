const VERSION='CENTRAL_PLATFORM_PUBLISHER_BRIDGE_0.1.0';
const PUBLISH_ALLOWED_KEY='publicPublishAllowed';
chrome.runtime.onInstalled.addListener(()=>{
  chrome.storage.local.set({bridgeVersion:VERSION,[PUBLISH_ALLOWED_KEY]:false,lastInstallAt:new Date().toISOString()});
});
chrome.runtime.onMessage.addListener((msg,sender,sendResponse)=>{
  (async()=>{
    if(!msg||!msg.type)return sendResponse({ok:false,error:'MESSAGE_TYPE_REQUIRED'});
    if(msg.type==='CENTRAL_BRIDGE_STATUS'){
      const state=await chrome.storage.local.get([PUBLISH_ALLOWED_KEY,'bridgeVersion']);
      return sendResponse({ok:true,version:VERSION,publicPublishAllowed:state[PUBLISH_ALLOWED_KEY]===true,tabUrl:sender?.tab?.url||''});
    }
    if(msg.type==='CENTRAL_BRIDGE_SET_PUBLISH_ALLOWED'){
      return sendResponse({ok:false,error:'USER_GATE_REQUIRED',detail:'Public publish cannot be enabled by background message. Central approval workflow must set this only after platform E2E verification.'});
    }
    sendResponse({ok:false,error:'UNKNOWN_MESSAGE'});
  })().catch(e=>sendResponse({ok:false,error:String(e&&e.message||e)}));
  return true;
});
