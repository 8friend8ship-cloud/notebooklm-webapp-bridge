const VERSION = "0.2.0";
const DEFAULT_SHEET = "NotebookLM_Task_Queue";
const HEADERS = [
  "TASK_ID","CONTENT_ID","TASK_DATE","TASK_TYPE","TITLE","SOURCE_TEXT","INSTRUCTION","LANGUAGE",
  "NOTEBOOK_URL","DRIVE_FOLDER_ID","AUTO_SUBMIT","TIMEOUT_SECONDS","STATUS","OWNER_EMAIL",
  "CLAIMED_AT","STARTED_AT","COMPLETED_AT","RESULT_TYPE","RESULT_URL","RESULT_FILE_ID","RESULT_TEXT",
  "ERROR_MESSAGE","CALLBACK_URL","CALLBACK_TOKEN","CREATED_AT","UPDATED_AT"
];

function doGet(e){ return json_({ok:true,version:VERSION,service:"NotebookLM WebApp Bridge",time:new Date().toISOString()}); }
function doPost(e){
  try{
    const body=JSON.parse((e&&e.postData&&e.postData.contents)||"{}");
    const action=String(body.action||"");
    if(action==="health") return json_({ok:true,version:VERSION,time:new Date().toISOString()});
    if(action==="login") return json_(login_(body));
    if(action==="enqueueFromWriter") return json_(enqueueFromWriter_(body));
    const session=verifySession_(body.sessionToken);
    if(action==="listTasks") return json_(listTasks_(session,body));
    if(action==="claimTask") return json_(claimTask_(session,body));
    if(action==="updateTask") return json_(updateTask_(session,body));
    if(action==="completeTask") return json_(completeTask_(session,body));
    if(action==="createTask") return json_(createTask_(session,body.task||{}));
    throw new Error("지원되지 않는 action입니다: "+action);
  }catch(error){ return json_({ok:false,error:error&&error.message?error.message:String(error)}); }
}
function json_(data){ return ContentService.createTextOutput(JSON.stringify(data)).setMimeType(ContentService.MimeType.JSON); }
function props_(){ return PropertiesService.getScriptProperties(); }
function requiredProp_(name){ const value=props_().getProperty(name); if(!value) throw new Error(`Script Property ${name}가 없습니다.`); return value; }
function b64url_(bytes){ return Utilities.base64EncodeWebSafe(bytes).replace(/=+$/g,""); }
function sign_(text){ return b64url_(Utilities.computeHmacSha256Signature(text,requiredProp_("SESSION_SECRET"))); }
function issueSession_(profile){
  const payload={email:profile.email,name:profile.name||"",iat:Date.now(),exp:Date.now()+8*60*60*1000};
  const encoded=b64url_(Utilities.newBlob(JSON.stringify(payload)).getBytes()); return `${encoded}.${sign_(encoded)}`;
}
function verifySession_(token){
  if(!token||token.indexOf(".")<0) throw new Error("로그인 세션이 없습니다.");
  const parts=token.split("."); if(sign_(parts[0])!==parts[1]) throw new Error("세션 서명이 올바르지 않습니다.");
  const payload=JSON.parse(Utilities.newBlob(Utilities.base64DecodeWebSafe(parts[0])).getDataAsString());
  if(Number(payload.exp)<Date.now()) throw new Error("로그인 세션이 만료되었습니다.");
  assertAllowedEmail_(payload.email); return payload;
}
function assertAllowedEmail_(email){
  const allowed=(props_().getProperty("ALLOWED_EMAILS")||"").split(",").map(s=>s.trim().toLowerCase()).filter(Boolean);
  if(allowed.length&&allowed.indexOf(String(email||"").toLowerCase())<0) throw new Error("허용되지 않은 Google 계정입니다.");
}
function login_(body){
  if(!body.credential) throw new Error("Google ID credential이 없습니다.");
  const url="https://oauth2.googleapis.com/tokeninfo?id_token="+encodeURIComponent(body.credential);
  const response=UrlFetchApp.fetch(url,{muteHttpExceptions:true});
  if(response.getResponseCode()!==200) throw new Error("Google 로그인 토큰 검증에 실패했습니다.");
  const profile=JSON.parse(response.getContentText());
  if(profile.aud!==requiredProp_("GOOGLE_CLIENT_ID")) throw new Error("Google OAuth Client ID가 일치하지 않습니다.");
  if(String(profile.email_verified)!=="true") throw new Error("검증되지 않은 Google 이메일입니다.");
  assertAllowedEmail_(profile.email);
  return {ok:true,sessionToken:issueSession_(profile),user:{email:profile.email,name:profile.name||""}};
}
function spreadsheet_(){ return SpreadsheetApp.openById(requiredProp_("SPREADSHEET_ID")); }
function sheet_(){
  const name=props_().getProperty("TASK_SHEET_NAME")||DEFAULT_SHEET; const ss=spreadsheet_(); let sh=ss.getSheetByName(name);
  if(!sh) sh=ss.insertSheet(name); if(sh.getLastRow()===0) sh.getRange(1,1,1,HEADERS.length).setValues([HEADERS]);
  return sh;
}
function rows_(){
  const sh=sheet_(); const values=sh.getDataRange().getValues(); const headers=values.shift().map(String);
  return values.map((row,index)=>({rowNumber:index+2,data:Object.fromEntries(headers.map((h,i)=>[h,row[i]]))}));
}
function findTask_(taskId){ const found=rows_().find(item=>String(item.data.TASK_ID)===String(taskId)); if(!found) throw new Error("TASK_ID를 찾지 못했습니다: "+taskId); return found; }
function setTask_(rowNumber,patch){
  const sh=sheet_(); const map=Object.fromEntries(HEADERS.map((h,i)=>[h,i+1])); patch.UPDATED_AT=new Date();
  Object.keys(patch).forEach(key=>{if(map[key]) sh.getRange(rowNumber,map[key]).setValue(patch[key]);});
}
function taskDto_(data){ return {
  taskId:String(data.TASK_ID||""),contentId:String(data.CONTENT_ID||""),taskDate:fmtDate_(data.TASK_DATE),
  taskType:String(data.TASK_TYPE||"CHAT"),title:String(data.TITLE||""),sourceText:String(data.SOURCE_TEXT||""),
  instruction:String(data.INSTRUCTION||""),language:String(data.LANGUAGE||"ko-KR"),notebookUrl:String(data.NOTEBOOK_URL||"https://notebooklm.google.com/"),
  driveFolderId:String(data.DRIVE_FOLDER_ID||""),autoSubmit:String(data.AUTO_SUBMIT).toUpperCase()!=="FALSE",
  timeoutSeconds:Number(data.TIMEOUT_SECONDS||180),status:String(data.STATUS||"READY")
}; }
function fmtDate_(value){ return value instanceof Date?Utilities.formatDate(value,"Asia/Seoul","yyyy-MM-dd"):String(value||""); }
function listTasks_(session,body){
  const date=String(body.date||Utilities.formatDate(new Date(),"Asia/Seoul","yyyy-MM-dd"));
  const tasks=rows_().filter(item=>["READY","RETRY","ERROR"].indexOf(String(item.data.STATUS||"READY"))>=0)
    .filter(item=>!date||fmtDate_(item.data.TASK_DATE)===date).map(item=>taskDto_(item.data)); return {ok:true,tasks,user:session.email};
}
function claimTask_(session,body){
  const item=findTask_(body.taskId); const status=String(item.data.STATUS||"READY");
  if(["READY","RETRY","ERROR"].indexOf(status)<0) throw new Error("현재 실행할 수 없는 상태입니다: "+status);
  if(body.chromeProfileEmail&&String(body.chromeProfileEmail).toLowerCase()!==String(session.email).toLowerCase()) throw new Error("프런트앱 Google 계정과 Chrome Google 계정이 다릅니다.");
  setTask_(item.rowNumber,{STATUS:"CLAIMED",OWNER_EMAIL:session.email,CLAIMED_AT:new Date(),ERROR_MESSAGE:""});
  return {ok:true,task:taskDto_({...item.data,STATUS:"CLAIMED"})};
}
function updateTask_(session,body){
  const item=findTask_(body.taskId); if(item.data.OWNER_EMAIL&&String(item.data.OWNER_EMAIL)!==session.email) throw new Error("다른 사용자가 수령한 작업입니다.");
  const patch=body.patch||{}; setTask_(item.rowNumber,{STATUS:String(body.status||item.data.STATUS),STARTED_AT:item.data.STARTED_AT||new Date(),ERROR_MESSAGE:String(patch.error||"")});
  return {ok:true,taskId:body.taskId,status:body.status};
}
function completeTask_(session,body){
  const item=findTask_(body.taskId); const result=body.result||{}; const folder=resolveFolder_(item.data.DRIVE_FOLDER_ID);
  const manifest={taskId:body.taskId,contentId:item.data.CONTENT_ID,taskType:item.data.TASK_TYPE,completedAt:new Date().toISOString(),result};
  const file=folder.createFile(`notebooklm_${body.taskId}_result.json`,JSON.stringify(manifest,null,2),MimeType.PLAIN_TEXT);
  let textFile=null; if(result.resultText){ textFile=folder.createFile(`notebooklm_${body.taskId}_result.txt`,String(result.resultText),MimeType.PLAIN_TEXT); }
  const resultUrl=(result.resultUrls&&result.resultUrls[0])||result.notebookUrl||file.getUrl();
  setTask_(item.rowNumber,{STATUS:"DONE",COMPLETED_AT:new Date(),RESULT_TYPE:String(item.data.TASK_TYPE||"RESULT"),RESULT_URL:resultUrl,RESULT_FILE_ID:(textFile||file).getId(),RESULT_TEXT:String(result.resultText||"").slice(0,45000),ERROR_MESSAGE:""});
  notifyWriter_(item.data,{status:"DONE",resultUrl,resultFileId:(textFile||file).getId()});
  return {ok:true,result:{resultUrl,driveUrl:(textFile||file).getUrl(),resultFileId:(textFile||file).getId()}};
}
function resolveFolder_(folderId){
  if(folderId) try{return DriveApp.getFolderById(String(folderId));}catch(_e){}
  const root=props_().getProperty("DRIVE_ROOT_FOLDER_ID"); return root?DriveApp.getFolderById(root):DriveApp.getRootFolder();
}
function createTask_(session,task){ return appendTask_(task,session.email); }
function enqueueFromWriter_(body){
  if(String(body.writerSecret||"")!==requiredProp_("WRITER_SHARED_SECRET")) throw new Error("Writer shared secret가 올바르지 않습니다.");
  return appendTask_(body.task||{},String(body.ownerEmail||""));
}
function appendTask_(task,ownerEmail){
  const now=new Date(); const taskId=String(task.taskId||`NLM_${Utilities.formatDate(now,"Asia/Seoul","yyyyMMdd_HHmmss")}_${Utilities.getUuid().slice(0,6)}`);
  const row={TASK_ID:taskId,CONTENT_ID:task.contentId||"",TASK_DATE:task.taskDate||Utilities.formatDate(now,"Asia/Seoul","yyyy-MM-dd"),TASK_TYPE:task.taskType||"CHAT",TITLE:task.title||"",SOURCE_TEXT:task.sourceText||"",INSTRUCTION:task.instruction||"",LANGUAGE:task.language||"ko-KR",NOTEBOOK_URL:task.notebookUrl||"https://notebooklm.google.com/",DRIVE_FOLDER_ID:task.driveFolderId||"",AUTO_SUBMIT:task.autoSubmit===false?"FALSE":"TRUE",TIMEOUT_SECONDS:task.timeoutSeconds||180,STATUS:"READY",OWNER_EMAIL:ownerEmail||"",CALLBACK_URL:task.callbackUrl||"",CALLBACK_TOKEN:task.callbackToken||"",CREATED_AT:now,UPDATED_AT:now};
  sheet_().appendRow(HEADERS.map(h=>row[h]||"")); return {ok:true,taskId,status:"READY"};
}
function notifyWriter_(data,result){
  if(!data.CALLBACK_URL) return; try{UrlFetchApp.fetch(String(data.CALLBACK_URL),{method:"post",contentType:"application/json",payload:JSON.stringify({taskId:data.TASK_ID,contentId:data.CONTENT_ID,callbackToken:data.CALLBACK_TOKEN,...result}),muteHttpExceptions:true});}catch(_e){}
}
function setupNotebookLMBridge(){ sheet_(); return {version:VERSION,sheet:sheet_().getName(),headers:HEADERS}; }
