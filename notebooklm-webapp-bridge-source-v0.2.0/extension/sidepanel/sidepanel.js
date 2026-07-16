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
async function waitForTabComplete(tabId, timeoutMs=45000){
  const started=Date.now();
  while(Date.now()-started<timeoutMs){
    const tab=await chrome.tabs.get(tabId);
    if(tab.status==="complete") return tab;
    await new Promise((resolve)=>setTimeout(resolve,500));
  }
  throw new Error("NotebookLM 페이지 로딩 시간이 초과되었습니다.");
}
async function runNotebookInputTest(){
  const tabs=await chrome.tabs.query({url:"https://notebooklm.google.com/*"});
  let tab=tabs.find((item)=>item.active)||tabs[0];
  if(!tab) tab=await chrome.tabs.create({url:"https://notebooklm.google.com/",active:true});
  else tab=await chrome.tabs.update(tab.id,{active:true});
  if(!tab?.id) throw new Error("NotebookLM 탭을 열지 못했습니다.");
  await waitForTabComplete(tab.id);

  const [execution]=await chrome.scripting.executeScript({
    target:{tabId:tab.id},
    func:()=>{
      const visible=(element)=>{
        if(!(element instanceof HTMLElement)) return false;
        const style=getComputedStyle(element);
        const rect=element.getBoundingClientRect();
        return style.display!=="none"&&style.visibility!=="hidden"&&rect.width>2&&rect.height>2;
      };
      const normalize=(value)=>String(value||"").replace(/\s+/g," ").trim().toLowerCase();
      const dialogs=[...document.querySelectorAll("[role='dialog'],dialog")].filter(visible);
      if(dialogs.length){
        return {ok:false,error:"NotebookLM에 열린 대화상자가 있습니다. 대화상자를 닫고 다시 실행하세요."};
      }

      const raw=[...document.querySelectorAll("textarea,[contenteditable='true'][role='textbox'],[contenteditable='true']")];
      const candidates=[...new Set(raw)].filter((element)=>visible(element)&&!element.closest("[role='dialog'],dialog")&&!element.disabled&&!element.readOnly);
      if(!candidates.length) return {ok:false,error:"NotebookLM 입력창을 찾지 못했습니다. 먼저 노트북 하나를 열어 주세요."};

      const keywords=["질문","메시지","대화","채팅","ask","message","chat","prompt"];
      const scored=candidates.map((element)=>{
        const text=normalize([
          element.getAttribute("aria-label"),
          element.getAttribute("placeholder"),
          element.getAttribute("data-placeholder"),
          element.getAttribute("title")
        ].join(" "));
        return {element,score:keywords.reduce((sum,word)=>sum+(text.includes(word)?1:0),0),text};
      }).sort((a,b)=>b.score-a.score);

      let selected=null;
      if(scored.length===1) selected=scored[0];
      else if(scored[0].score>0&&scored[0].score>scored[1].score) selected=scored[0];
      if(!selected){
        return {ok:false,error:`입력창 후보가 ${scored.length}개라 안전하게 선택할 수 없습니다. 다른 편집창을 닫고 다시 실행하세요.`};
      }

      const marker=`[BRIDGE TEST ${new Date().toLocaleString("ko-KR")}] 전송하지 않은 연결 확인 문구입니다.`;
      const element=selected.element;
      element.focus();
      if(element instanceof HTMLTextAreaElement){
        const setter=Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,"value")?.set;
        setter?.call(element,marker);
      }else{
        const selection=window.getSelection();
        const range=document.createRange();
        range.selectNodeContents(element);
        selection?.removeAllRanges();
        selection?.addRange(range);
        document.execCommand("insertText",false,marker);
        selection?.removeAllRanges();
      }
      element.dispatchEvent(new InputEvent("input",{bubbles:true,inputType:"insertText",data:marker}));
      element.dispatchEvent(new Event("change",{bubbles:true}));
      const actual=element instanceof HTMLTextAreaElement?element.value:(element.innerText||element.textContent||"");
      if(!String(actual).includes("BRIDGE TEST")) return {ok:false,error:"입력 이벤트는 실행했지만 시험 문구가 반영되지 않았습니다."};
      return {ok:true,pageTitle:document.title,url:location.href,marker,locator:selected.text||"single-visible-editor"};
    }
  });
  const result=execution?.result;
  if(!result?.ok) throw new Error(result?.error||"NotebookLM 입력 테스트 결과를 받지 못했습니다.");
  return result;
}
$("#save").addEventListener("click",async()=>{try{
  const result=await send("SAVE_CONFIG",{config:{appsScriptUrl:apiUrl.value.trim(),frontendOrigin:frontendOrigin.value.trim()}});
  setStatus(`저장됨: ${result.config.frontendOrigin||"프런트 주소 미설정"}`);
}catch(e){setStatus(String(e),true)}});
$("#test").addEventListener("click",async()=>{try{setStatus("API 확인 중…"); const result=await send("TEST_API"); setStatus(`API 정상: ${result.response.version}`)}catch(e){setStatus(String(e),true)}});
$("#testNotebook").addEventListener("click",async()=>{try{
  setStatus("NotebookLM 탭과 입력창을 확인 중…");
  const result=await runNotebookInputTest();
  setStatus(`NotebookLM 제어 정상 · ${result.pageTitle} · 시험 문구 입력 완료(전송 안 함)`);
}catch(e){setStatus(e instanceof Error?e.message:String(e),true)}});
load().catch((e)=>setStatus(String(e),true));
