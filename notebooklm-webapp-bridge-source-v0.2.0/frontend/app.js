const FILE_CONFIG = window.NLM_BRIDGE_CONFIG || {};
const STORAGE_KEY = "nlmBridgeFrontendConfig";
const SOURCE = "notebooklm-webapp-bridge";
const state = { sessionToken: sessionStorage.getItem("nlmSessionToken") || "", user: null, extension: null };
const $ = (selector) => document.querySelector(selector);

function loadRuntimeConfig(){
  let saved={};
  try{ saved=JSON.parse(localStorage.getItem(STORAGE_KEY)||"{}"); }catch{}
  return {
    GOOGLE_CLIENT_ID: saved.GOOGLE_CLIENT_ID || (String(FILE_CONFIG.GOOGLE_CLIENT_ID||"").startsWith("REPLACE_WITH_") ? "" : FILE_CONFIG.GOOGLE_CLIENT_ID || ""),
    APPS_SCRIPT_URL: saved.APPS_SCRIPT_URL || (String(FILE_CONFIG.APPS_SCRIPT_URL||"").startsWith("REPLACE_WITH_") ? "" : FILE_CONFIG.APPS_SCRIPT_URL || ""),
    EXTENSION_ID: saved.EXTENSION_ID || (String(FILE_CONFIG.EXTENSION_ID||"").startsWith("REPLACE_WITH_") ? "" : FILE_CONFIG.EXTENSION_ID || "")
  };
}
let CONFIG=loadRuntimeConfig();

function setMessage(text,error=false){ $("#message").textContent=text; $("#message").className=`message ${error?"error":""}`; }
function fillConfigForm(){
  $("#googleClientId").value=CONFIG.GOOGLE_CLIENT_ID||"";
  $("#appsScriptUrl").value=CONFIG.APPS_SCRIPT_URL||"";
  $("#extensionId").value=CONFIG.EXTENSION_ID||"";
}
function saveBridgeConfig(){
  const next={
    GOOGLE_CLIENT_ID: $("#googleClientId").value.trim(),
    APPS_SCRIPT_URL: $("#appsScriptUrl").value.trim(),
    EXTENSION_ID: $("#extensionId").value.trim()
  };
  const errors=[];
  if(next.GOOGLE_CLIENT_ID && !next.GOOGLE_CLIENT_ID.endsWith(".apps.googleusercontent.com")) errors.push("Google OAuth Client ID 형식");
  if(next.APPS_SCRIPT_URL && !next.APPS_SCRIPT_URL.startsWith("https://script.google.com/macros/s/")) errors.push("Apps Script URL 형식");
  if(next.EXTENSION_ID && !/^[a-p]{32}$/.test(next.EXTENSION_ID)) errors.push("확장프로그램 ID 형식");
  if(errors.length) throw new Error(`설정값을 확인하세요: ${errors.join(", ")}`);
  localStorage.setItem(STORAGE_KEY,JSON.stringify(next));
  CONFIG=next;
  state.extension=null;
  setMessage("브리지 설정을 저장했습니다. 연결 진단을 실행하세요.");
  initGoogle(true);
}
async function api(action,payload={}){
  if(!CONFIG.APPS_SCRIPT_URL.startsWith("https://script.google.com/macros/s/")) throw new Error("Apps Script Web App URL이 설정되지 않았습니다.");
  const response=await fetch(CONFIG.APPS_SCRIPT_URL,{method:"POST",redirect:"follow",headers:{"Content-Type":"text/plain;charset=utf-8"},body:JSON.stringify({action,sessionToken:state.sessionToken,...payload})});
  if(!response.ok) throw new Error(`Apps Script HTTP ${response.status}`);
  let data;
  try{ data=await response.json(); }catch{ throw new Error("Apps Script 응답이 JSON이 아닙니다. 배포 URL/접근 권한을 확인하세요."); }
  if(!data.ok) throw new Error(data.error||"API 오류"); return data;
}
function extensionMessage(type,payload={}){
  return new Promise((resolve,reject)=>{
    if(!globalThis.chrome?.runtime?.sendMessage) return reject(new Error("Chrome 확장 메시지 API를 사용할 수 없습니다. Chrome에서 이 페이지를 여세요."));
    if(!/^[a-p]{32}$/.test(CONFIG.EXTENSION_ID)) return reject(new Error("Chrome 확장프로그램 ID가 설정되지 않았습니다."));
    chrome.runtime.sendMessage(CONFIG.EXTENSION_ID,{source:SOURCE,type,...payload},(response)=>{
      if(chrome.runtime.lastError) return reject(new Error(`확장 연결 실패: ${chrome.runtime.lastError.message}`));
      if(!response?.ok) return reject(new Error(response?.error||"확장프로그램 응답 없음")); resolve(response);
    });
  });
}
async function connectExtension(){
  const result=await extensionMessage("PING"); state.extension=result;
  $("#extensionStatus").textContent=`연결됨 v${result.version}`;
  $("#chromeProfile").textContent=result.profile?.email||"이메일 확인 불가";
  return result;
}
async function diagnoseBridge(){
  const problems=[];
  if(!CONFIG.GOOGLE_CLIENT_ID.endsWith(".apps.googleusercontent.com")) problems.push("Google OAuth Client ID 미설정");
  if(!CONFIG.APPS_SCRIPT_URL.startsWith("https://script.google.com/macros/s/")) problems.push("Apps Script URL 미설정");
  if(!/^[a-p]{32}$/.test(CONFIG.EXTENSION_ID)) problems.push("확장 ID 미설정");
  if(problems.length){ setMessage(`설정 필요: ${problems.join(" / ")}`,true); return; }
  try{
    const ext=await connectExtension();
    const health=await api("health");
    setMessage(`진단 통과: 확장 v${ext.version} / Apps Script ${health.ok?"정상":"응답"}`);
  }catch(error){ setMessage(`진단 실패: ${error.message}`,true); }
}
function renderTasks(tasks){
  const list=$("#taskList"); list.replaceChildren();
  if(!tasks.length){list.textContent="실행 대기 작업이 없습니다.";return;}
  for(const task of tasks){
    const card=document.createElement("article");card.className="task";
    const info=document.createElement("div");
    const title=document.createElement("h3");title.textContent=task.title||task.taskId;
    const meta=document.createElement("p");meta.textContent=`${task.taskType} · ${task.language} · ${task.status}`;
    const id=document.createElement("p");id.textContent=`TASK_ID: ${task.taskId} / CONTENT_ID: ${task.contentId||"-"}`;
    const button=document.createElement("button");button.textContent="NotebookLM 실행";
    button.addEventListener("click",()=>runTask(task.taskId,button));
    info.append(title,meta,id);card.append(info,button);list.append(card);
  }
}
async function loadTasks(){
  if(!state.sessionToken) throw new Error("먼저 Google 로그인하세요.");
  const data=await api("listTasks",{date:new Date().toISOString().slice(0,10)});renderTasks(data.tasks||[]);setMessage(`${(data.tasks||[]).length}개 작업을 불러왔습니다.`);
}
async function runTask(taskId,button){
  try{button.disabled=true;button.textContent="실행 중…"; if(!state.extension) await connectExtension();
    const result=await extensionMessage("RUN_TASK",{apiUrl:CONFIG.APPS_SCRIPT_URL,sessionToken:state.sessionToken,taskId});
    setMessage(`${taskId} 완료: ${result.result?.resultUrl||result.result?.driveUrl||"결과 등록됨"}`); await loadTasks();
  }catch(error){setMessage(error.message,true);button.disabled=false;button.textContent="다시 실행";}
}
function handleGoogleCredential(response){
  api("login",{credential:response.credential}).then((data)=>{
    state.sessionToken=data.sessionToken;state.user=data.user;sessionStorage.setItem("nlmSessionToken",state.sessionToken);
    $("#loginStatus").textContent=data.user.email;setMessage("로그인되었습니다. 확장 연결 후 작업을 불러오세요.");
  }).catch((error)=>setMessage(error.message,true));
}
let googleInitializedFor="";
function initGoogle(force=false){
  if(force){ googleInitializedFor=""; $("#googleButton").replaceChildren(); }
  const timer=setInterval(()=>{if(!globalThis.google?.accounts?.id)return;clearInterval(timer);
    if(!CONFIG.GOOGLE_CLIENT_ID.endsWith(".apps.googleusercontent.com")){setMessage("브리지 연결 설정에서 Google OAuth Web Client ID를 입력하세요.",true);return;}
    if(googleInitializedFor===CONFIG.GOOGLE_CLIENT_ID) return;
    googleInitializedFor=CONFIG.GOOGLE_CLIENT_ID;
    google.accounts.id.initialize({client_id:CONFIG.GOOGLE_CLIENT_ID,callback:handleGoogleCredential,auto_select:false});
    google.accounts.id.renderButton($("#googleButton"),{theme:"outline",size:"large",text:"signin_with"});
  },250);
}
$("#saveBridgeConfig").addEventListener("click",()=>{try{saveBridgeConfig();}catch(e){setMessage(e.message,true);}});
$("#diagnoseBridge").addEventListener("click",()=>diagnoseBridge());
$("#connectExtension").addEventListener("click",()=>connectExtension().then(()=>setMessage("확장프로그램이 정상 연결되었습니다.")).catch((e)=>setMessage(e.message,true)));
$("#loadTasks").addEventListener("click",()=>loadTasks().catch((e)=>setMessage(e.message,true)));
if(state.sessionToken) $("#loginStatus").textContent="세션 복원됨";
fillConfigForm();
initGoogle();
