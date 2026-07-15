const CONFIG = window.NLM_BRIDGE_CONFIG;
const SOURCE = "notebooklm-webapp-bridge";
const state = { sessionToken: sessionStorage.getItem("nlmSessionToken") || "", user: null, extension: null };
const $ = (selector) => document.querySelector(selector);

function setMessage(text, error=false){ $("#message").textContent=text; $("#message").className=`message ${error?"error":""}`; }
async function api(action, payload={}){
  if(!CONFIG.APPS_SCRIPT_URL.startsWith("https://script.google.com/macros/s/")) throw new Error("frontend/config.js에 Apps Script URL을 설정하세요.");
  const response=await fetch(CONFIG.APPS_SCRIPT_URL,{method:"POST",redirect:"follow",headers:{"Content-Type":"text/plain;charset=utf-8"},body:JSON.stringify({action,sessionToken:state.sessionToken,...payload})});
  const data=await response.json(); if(!data.ok) throw new Error(data.error||"API 오류"); return data;
}
function extensionMessage(type,payload={}){
  return new Promise((resolve,reject)=>{
    if(!globalThis.chrome?.runtime?.sendMessage) return reject(new Error("Chrome 확장 메시지 API를 사용할 수 없습니다."));
    if(!/^[a-p]{32}$/.test(CONFIG.EXTENSION_ID)) return reject(new Error("frontend/config.js에 확장프로그램 ID를 설정하세요."));
    chrome.runtime.sendMessage(CONFIG.EXTENSION_ID,{source:SOURCE,type,...payload},(response)=>{
      if(chrome.runtime.lastError) return reject(new Error(chrome.runtime.lastError.message));
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
  const data=await api("listTasks",{date:new Date().toISOString().slice(0,10)});renderTasks(data.tasks||[]);setMessage(`${data.tasks.length}개 작업을 불러왔습니다.`);
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
function initGoogle(){
  const timer=setInterval(()=>{if(!globalThis.google?.accounts?.id)return;clearInterval(timer);
    if(!CONFIG.GOOGLE_CLIENT_ID.includes(".apps.googleusercontent.com")){setMessage("frontend/config.js에 Google OAuth Web Client ID를 설정하세요.",true);return;}
    google.accounts.id.initialize({client_id:CONFIG.GOOGLE_CLIENT_ID,callback:handleGoogleCredential,auto_select:false});
    google.accounts.id.renderButton($("#googleButton"),{theme:"outline",size:"large",text:"signin_with"});
  },250);
}
$("#connectExtension").addEventListener("click",()=>connectExtension().then(()=>setMessage("확장프로그램이 정상 연결되었습니다.")).catch((e)=>setMessage(e.message,true)));
$("#loadTasks").addEventListener("click",()=>loadTasks().catch((e)=>setMessage(e.message,true)));
if(state.sessionToken) $("#loginStatus").textContent="세션 복원됨";
initGoogle();
