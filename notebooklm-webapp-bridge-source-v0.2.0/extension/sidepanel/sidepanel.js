const SOURCE = "notebooklm-webapp-bridge";
const $ = (selector) => document.querySelector(selector);
const apiUrl = $("#apiUrl");
const frontendOrigin = $("#frontendOrigin");
const status = $("#status");
const profile = $("#profile");
const logs = $("#logs");

function send(type, payload={}) {
  return chrome.runtime.sendMessage({ source: SOURCE, type, ...payload });
}
function setStatus(text, error=false){ status.textContent=text; status.className=error?"error":""; }
async function load(){
  const result=await send("GET_CONFIG");
  apiUrl.value=result.config.appsScriptUrl||"";
  frontendOrigin.value=result.config.frontendOrigin||"";
  profile.textContent=result.profile.email||"Chrome 프로필 이메일을 확인할 수 없습니다.";
  await loadLogs(); setStatus("설정을 확인했습니다.");
}
async function loadLogs(){
  const result=await send("GET_LOGS"); logs.replaceChildren();
  for(const item of (result.logs||[]).slice(0,30)){
    const div=document.createElement("div"); div.className=`log ${item.level==="error"?"error":""}`;
    div.textContent=`${new Date(item.createdAt).toLocaleString("ko-KR")} · ${item.message}`; logs.append(div);
  }
}
$("#save").addEventListener("click",async()=>{try{
  const result=await send("SAVE_CONFIG",{config:{appsScriptUrl:apiUrl.value.trim(),frontendOrigin:frontendOrigin.value.trim()}});
  setStatus(`저장됨: ${result.config.frontendOrigin||"프런트 주소 미설정"}`);
}catch(e){setStatus(String(e),true)}});
$("#test").addEventListener("click",async()=>{try{setStatus("API 확인 중…"); const result=await send("TEST_API"); setStatus(`API 정상: ${result.response.version}`)}catch(e){setStatus(String(e),true)}});
load().catch((e)=>setStatus(String(e),true));
