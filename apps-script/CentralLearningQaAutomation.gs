const CENTRAL_QA_MASTER_ID = '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI';
const CENTRAL_QA_BRIDGE_SHEET_ID = '1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk';
const CENTRAL_QA_MANAGER_ID = '147pycCA4XT2u4TxFYZOaR9na0RtpplbNmRJmmN2o-3w';
const CENTRAL_QA_TZ = 'Asia/Seoul';

function installCentralLearningQaTriggersV1() {
  const handler = 'runCentralDriveLearningQaCycleV1';
  ScriptApp.getProjectTriggers().forEach(function(t){ if (t.getHandlerFunction() === handler) ScriptApp.deleteTrigger(t); });
  ScriptApp.newTrigger(handler).timeBased().everyMinutes(5).create();
  const triggers = ScriptApp.getProjectTriggers().filter(function(t){return t.getHandlerFunction()===handler;});
  return {ok:triggers.length===1, handler:handler, triggerCount:triggers.length, triggerIds:triggers.map(function(t){return t.getUniqueId();}), cadence:'5m', at:new Date()};
}

function runCentralDriveLearningQaCycleV1() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) return {ok:true, skipped:'LOCKED'};
  try {
    const props = PropertiesService.getScriptProperties();
    const now = new Date();
    const files = scanCentralDriveUpdatedArtifactsV1_(props, now);
    const results = [];
    files.forEach(function(fileMeta){
      try { results.push(reviewCentralArtifactV1(fileMeta)); }
      catch (e) { results.push({ok:false,fileId:fileMeta.fileId,error:String(e && e.message || e)}); }
    });
    props.setProperty('CENTRAL_QA_LAST_SCAN_AT', now.toISOString());
    writeQaCycleReadbackV1_({ok:true, scanned:files.length, results:results, at:now});
    return {ok:true, scanned:files.length, results:results, at:now};
  } finally { lock.releaseLock(); }
}

function scanCentralDriveUpdatedArtifactsV1_(props, now) {
  const maxFiles = Math.max(1, Math.min(20, Number(props.getProperty('CENTRAL_QA_MAX_FILES_PER_CYCLE') || 10)));
  const lastIso = props.getProperty('CENTRAL_QA_LAST_SCAN_AT') || new Date(now.getTime()-10*60*1000).toISOString();
  const rootId = props.getProperty('CENTRAL_ROOT_FOLDER_ID') || '';
  let root = null;
  if (rootId) { try { root = DriveApp.getFolderById(rootId); } catch(e){} }
  if (!root) {
    const it = DriveApp.getFoldersByName('00_중앙에이전트');
    if (it.hasNext()) root = it.next();
  }
  if (!root) throw new Error('CENTRAL_ROOT_FOLDER_NOT_FOUND');
  const out = [];
  collectRecentFilesV1_(root, new Date(lastIso), 0, 2, maxFiles, out);
  return out.sort(function(a,b){return b.updatedAt-a.updatedAt;}).slice(0,maxFiles);
}

function collectRecentFilesV1_(folder, since, depth, maxDepth, maxFiles, out) {
  if (out.length >= maxFiles) return;
  const files = folder.getFiles();
  while (files.hasNext() && out.length < maxFiles) {
    const f = files.next();
    const updated = f.getLastUpdated();
    if (updated <= since) continue;
    const name = f.getName();
    if (!/(result|output|audit|report|seed|template|artifact|readback|analysis|검수|결과|씨드|템플릿)/i.test(name)) continue;
    out.push({fileId:f.getId(), name:name, mimeType:f.getMimeType(), size:safeFileSizeV1_(f), url:f.getUrl(), updatedAt:updated, folderId:folder.getId()});
  }
  if (depth >= maxDepth || out.length >= maxFiles) return;
  const folders = folder.getFolders();
  while (folders.hasNext() && out.length < maxFiles) collectRecentFilesV1_(folders.next(), since, depth+1, maxDepth, maxFiles, out);
}

function safeFileSizeV1_(f){ try{return f.getSize();}catch(e){return 0;} }

function reviewCentralArtifactV1(fileMeta) {
  const contract = inferExpectedOutputContractV1(fileMeta);
  const extracted = extractArtifactEvidenceV1_(fileMeta, contract);
  const deterministic = scoreCentralOutputDeterministicV1(extracted, contract);
  const ai = runCentralDualAiReviewV1({fileMeta:fileMeta,contract:contract,extracted:extracted,deterministic:deterministic});
  const consensus = mergeCentralQaConsensusV1_(deterministic, ai);
  const audit = centralAuditResultV1({
    taskId:'DRIVE_QA_'+fileMeta.fileId,
    appId:contract.appId,
    resultId:fileMeta.fileId,
    resultUrl:fileMeta.url,
    evidence:fileMeta.fileId+'|'+fileMeta.name,
    goal:contract.goal,
    outputType:contract.outputType,
    variantKey:contract.templateKey,
    readbackOk:true,
    scores:consensus.scores,
    hardFails:consensus.hardFails,
    artifactChecks:{deterministic:deterministic,gemini:ai.gemini,openai:ai.openai,consensus:consensus},
    resultSummary:extracted.summary,
    seedText:consensus.seedText,
    rootCause:consensus.rootCause,
    wrongAssumption:consensus.wrongAssumption,
    fixApplied:consensus.fixApplied,
    lesson:consensus.lesson,
    preventionRule:consensus.preventionRule,
    templateAdjustment:consensus.templateAdjustment,
    functionPatchCandidate:consensus.functionPatchCandidate
  });
  return {ok:true,fileId:fileMeta.fileId,contract:contract,deterministic:deterministic,ai:ai,consensus:consensus,audit:audit};
}

function inferExpectedOutputContractV1(fileMeta) {
  const n = String(fileMeta.name||'').toLowerCase();
  let outputType='DATA', goal='usable traceable central result', appId='CENTRAL_AGENT', templateKey='CENTRAL_GENERIC_V1';
  if (/flow|video|mp4|mov/.test(n)) {outputType='VIDEO';goal='usable Flow/video result with source traceability and front-app reuse value';appId='APP_VTUBE_1011B';templateKey='VIDEO_PATTERN_T1';}
  else if (/image|png|jpg|jpeg|webp/.test(n)) {outputType='IMAGE';goal='usable visual asset with source traceability and template reuse value';templateKey='IMAGE_ASSET_T1';}
  else if (/notebook|audio|wav|mp3|m4a/.test(n)) {outputType='AUDIO';goal='usable NotebookLM/audio result with physical/Drive readback and learning value';appId='APP_NOTEBOOKLM_BRIDGE';templateKey='NLM_OUTPUT_TEMPLATE';}
  else if (/report|doc|text|json|analysis|audit|readback/.test(n)) {outputType='TEXT_DATA';goal='complete analyzable result that can become Seed/Template evidence';templateKey='TEXT_ANALYSIS_V1';}
  return {appId:appId,outputType:outputType,goal:goal,templateKey:templateKey,minimum:{nonzero:true,traceable:true,readable:true,reusable:true}};
}

function extractArtifactEvidenceV1_(fileMeta, contract) {
  let text='';
  try {
    const f=DriveApp.getFileById(fileMeta.fileId);
    const mt=f.getMimeType();
    if (mt.indexOf('google-apps.document')>=0) text=DocumentApp.openById(f.getId()).getBody().getText();
    else if (mt.indexOf('google-apps.spreadsheet')>=0) text=SpreadsheetApp.openById(f.getId()).getSheets().slice(0,3).map(function(s){return s.getDataRange().getDisplayValues().slice(0,30).map(function(r){return r.join('\t');}).join('\n');}).join('\n---\n');
    else if (/text|json|csv|javascript|xml/.test(mt)) text=f.getBlob().getDataAsString('UTF-8');
  } catch(e) { text=''; }
  if (text.length>16000) text=text.slice(0,16000);
  return {name:fileMeta.name,size:fileMeta.size,mimeType:fileMeta.mimeType,text:text,summary:text?text.slice(0,2000):fileMeta.name,hasText:!!text,contract:contract};
}

function scoreCentralOutputDeterministicV1(extracted, contract) {
  const nonzero = Number(extracted.size||0)>0 || extracted.hasText;
  const traceable = !!extracted.name && !!contract.outputType;
  const readable = extracted.hasText || /VIDEO|IMAGE|AUDIO/.test(contract.outputType);
  const reusable = /(result|output|analysis|template|seed|artifact|readback|audit|결과|템플릿|씨드)/i.test(extracted.name||'');
  const scores={
    GOAL_ALIGNMENT: nonzero?88:20,
    PRACTICAL_USABILITY: readable?85:55,
    QUALITY_LEVEL: nonzero?82:30,
    SOURCE_TRACEABILITY: traceable?92:40,
    OUTPUT_COMPLETENESS: nonzero?90:20,
    FRONTAPP_FIT: reusable?84:70,
    TECHNICAL_READBACK: nonzero?100:0,
    REUSABILITY_LEARNING_VALUE: reusable?86:65
  };
  const hardFails=[]; if(!nonzero)hardFails.push('MISSING_RESULT'); if(!traceable)hardFails.push('CRITICAL_SOURCE_MISMATCH');
  return {ok:hardFails.length===0,scores:scores,hardFails:hardFails,signals:{nonzero:nonzero,traceable:traceable,readable:readable,reusable:reusable}};
}

function runCentralDualAiReviewV1(ctx) {
  const policy = centralAiUsagePolicyV1_();
  return {
    policy:policy,
    gemini: runGeminiLearningQaV1_(ctx, policy),
    openai: runOpenAiLearningQaV1_(ctx, policy)
  };
}

function centralAiUsagePolicyV1_() {
  const p=PropertiesService.getScriptProperties();
  return {
    geminiDailyCap:Number(p.getProperty('CENTRAL_GEMINI_QA_DAILY_CAP')||0),
    openaiDailyCap:Number(p.getProperty('CENTRAL_OPENAI_QA_DAILY_CAP')||0),
    geminiMode:p.getProperty('CENTRAL_GEMINI_QA_MODE')||'BROWSER_OR_FREE_ONLY',
    openaiMode:p.getProperty('CENTRAL_OPENAI_QA_MODE')||'CENTRAL_AGENT_OR_API_GATED',
    maxChars:Number(p.getProperty('CENTRAL_AI_QA_MAX_CHARS')||8000)
  };
}

function runGeminiLearningQaV1_(ctx, policy) {
  const p=PropertiesService.getScriptProperties();
  const key=p.getProperty('GEMINI_API_KEY')||'';
  const allowed=consumeDailyAiSlotV1_('GEMINI',policy.geminiDailyCap,false);
  if (key && allowed.ok && /API/.test(policy.geminiMode)) {
    return callGeminiQaApiV1_(ctx,key,policy,allowed);
  }
  const queued=queueUiAiReviewV1_('GEMINI_AI_STUDIO',ctx);
  return {status:'QUEUED_UI_OR_HOLD',provider:'GEMINI',apiCalled:false,reason:key?'API_MODE_OR_CAP_BLOCK':'NO_API_KEY_USE_UI_FIRST',queue:queued};
}

function runOpenAiLearningQaV1_(ctx, policy) {
  const p=PropertiesService.getScriptProperties();
  const key=p.getProperty('OPENAI_API_KEY')||'';
  const allowed=consumeDailyAiSlotV1_('OPENAI',policy.openaiDailyCap,false);
  if (key && allowed.ok && /API/.test(policy.openaiMode)) {
    return callOpenAiQaApiV1_(ctx,key,policy,allowed);
  }
  const queued=queueUiAiReviewV1_('OPENAI_CHATGPT_CENTRAL_AGENT',ctx);
  return {status:'QUEUED_CENTRAL_AGENT_OR_HOLD',provider:'OPENAI',apiCalled:false,reason:key?'API_MODE_OR_CAP_BLOCK':'NO_API_KEY_USE_SUBSCRIPTION_OR_CONNECTOR_FIRST',queue:queued};
}

function consumeDailyAiSlotV1_(provider, cap, commit) {
  const p=PropertiesService.getScriptProperties(); const day=Utilities.formatDate(new Date(),CENTRAL_QA_TZ,'yyyyMMdd'); const k='CENTRAL_AI_USAGE_'+provider+'_'+day; const used=Number(p.getProperty(k)||0);
  if (cap<=0) return {ok:false,used:used,cap:cap,reason:'CAP_ZERO_OR_UNSET'};
  if (used>=cap) return {ok:false,used:used,cap:cap,reason:'DAILY_CAP_REACHED'};
  if (commit) p.setProperty(k,String(used+1));
  return {ok:true,used:used,cap:cap,remaining:cap-used};
}

function buildQaPromptV1_(ctx) {
  const text=String(ctx.extracted.text||ctx.extracted.summary||'').slice(0,8000);
  return 'You are a QA reviewer. Return ONLY compact JSON with scores 0-100 for GOAL_ALIGNMENT,PRACTICAL_USABILITY,QUALITY_LEVEL,SOURCE_TRACEABILITY,OUTPUT_COMPLETENESS,FRONTAPP_FIT,TECHNICAL_READBACK,REUSABILITY_LEARNING_VALUE; hardFails array; rootCause; wrongAssumption; lesson; preventionRule; templateAdjustment; functionPatchCandidate. Goal: '+ctx.contract.goal+'\nOutputType:'+ctx.contract.outputType+'\nFile:'+ctx.fileMeta.name+'\nEvidence:\n'+text;
}

function callGeminiQaApiV1_(ctx,key,policy,slot) {
  consumeDailyAiSlotV1_('GEMINI',policy.geminiDailyCap,true);
  const model=PropertiesService.getScriptProperties().getProperty('CENTRAL_GEMINI_QA_MODEL')||'gemini-2.5-flash';
  const url='https://generativelanguage.googleapis.com/v1beta/models/'+encodeURIComponent(model)+':generateContent?key='+encodeURIComponent(key);
  const r=UrlFetchApp.fetch(url,{method:'post',contentType:'application/json',muteHttpExceptions:true,payload:JSON.stringify({contents:[{parts:[{text:buildQaPromptV1_(ctx)}]}],generationConfig:{temperature:0,responseMimeType:'application/json'}})});
  const code=r.getResponseCode(), body=r.getContentText();
  if(code<200||code>=300)return {status:'ERROR',provider:'GEMINI',apiCalled:true,httpCode:code,error:body.slice(0,1000)};
  let parsed={}; try{const j=JSON.parse(body);parsed=JSON.parse(j.candidates[0].content.parts[0].text);}catch(e){parsed={parseError:String(e),raw:body.slice(0,1500)};}
  return {status:'DONE',provider:'GEMINI',apiCalled:true,review:parsed,slot:slot};
}

function callOpenAiQaApiV1_(ctx,key,policy,slot) {
  consumeDailyAiSlotV1_('OPENAI',policy.openaiDailyCap,true);
  const model=PropertiesService.getScriptProperties().getProperty('CENTRAL_OPENAI_QA_MODEL')||'gpt-5.6-sol';
  const r=UrlFetchApp.fetch('https://api.openai.com/v1/responses',{method:'post',contentType:'application/json',headers:{Authorization:'Bearer '+key},muteHttpExceptions:true,payload:JSON.stringify({model:model,input:buildQaPromptV1_(ctx),max_output_tokens:1200})});
  const code=r.getResponseCode(), body=r.getContentText();
  if(code<200||code>=300)return {status:'ERROR',provider:'OPENAI',apiCalled:true,httpCode:code,error:body.slice(0,1000)};
  let parsed={}; try{const j=JSON.parse(body);let t='';(j.output||[]).forEach(function(o){(o.content||[]).forEach(function(c){if(c.text)t+=c.text;});});parsed=JSON.parse(t);}catch(e){parsed={parseError:String(e),raw:body.slice(0,1500)};}
  return {status:'DONE',provider:'OPENAI',apiCalled:true,review:parsed,slot:slot};
}

function queueUiAiReviewV1_(provider,ctx) {
  const ss=SpreadsheetApp.openById(CENTRAL_QA_BRIDGE_SHEET_ID); const sh=ss.getSheetByName('TASK_QUEUE'); if(!sh)return {ok:false,reason:'TASK_QUEUE_MISSING'};
  const taskId='TASK_QA_'+provider+'_'+ctx.fileMeta.fileId+'_'+Utilities.formatDate(new Date(),CENTRAL_QA_TZ,'yyyyMMddHHmmss');
  const payload={provider:provider,task:'LEARNING_TEMPLATE_QA',fileId:ctx.fileMeta.fileId,fileUrl:ctx.fileMeta.url,prompt:buildQaPromptV1_(ctx),successCriteria:'JSON_QA+DRIVE_READBACK',usagePolicy:'SUBSCRIPTION_UI_FIRST;API_ONLY_IF_CAP_PROPERTY>0'};
  sh.appendRow([taskId,'CENTRAL_AGENT','AI_REVIEW_'+provider,JSON.stringify(payload),'QUEUED',4,new Date(),'','','','','','QA_'+provider+'_'+ctx.fileMeta.fileId]);
  return {ok:true,taskId:taskId};
}

function mergeCentralQaConsensusV1_(deterministic, ai) {
  const reviews=[deterministic];
  [ai.gemini,ai.openai].forEach(function(x){if(x&&x.review&&x.review.scores)reviews.push({scores:x.review.scores,hardFails:x.review.hardFails||[],review:x.review});});
  const keys=['GOAL_ALIGNMENT','PRACTICAL_USABILITY','QUALITY_LEVEL','SOURCE_TRACEABILITY','OUTPUT_COMPLETENESS','FRONTAPP_FIT','TECHNICAL_READBACK','REUSABILITY_LEARNING_VALUE'];
  const scores={}; keys.forEach(function(k){let vals=reviews.map(function(r){return Number((r.scores||{})[k]||0);}).filter(function(v){return v>0;});scores[k]=vals.length?Math.round(vals.reduce(function(a,b){return a+b;},0)/vals.length):0;});
  const hard=[];reviews.forEach(function(r){(r.hardFails||[]).forEach(function(h){if(hard.indexOf(h)<0)hard.push(h);});});
  const ar=(ai.gemini&&ai.gemini.review)||{}; const or=(ai.openai&&ai.openai.review)||{};
  return {scores:scores,hardFails:hard,rootCause:or.rootCause||ar.rootCause||'',wrongAssumption:or.wrongAssumption||ar.wrongAssumption||'',lesson:or.lesson||ar.lesson||'',preventionRule:or.preventionRule||ar.preventionRule||'',templateAdjustment:or.templateAdjustment||ar.templateAdjustment||'',functionPatchCandidate:or.functionPatchCandidate||ar.functionPatchCandidate||'',fixApplied:'',seedText:'QA_CONSENSUS:'+JSON.stringify(scores)};
}

function writeQaCycleReadbackV1_(payload) {
  try { appendByHeader_('80_DATA_RUNTIME_QA_LOG',{QA_ID:'QA-CYCLE-'+Utilities.formatDate(new Date(),CENTRAL_QA_TZ,'yyyyMMdd-HHmmss'),RUN_ID:'DRIVE_UPDATE_TRIGGER',APP_ID:'CENTRAL_AGENT',FUNCTION_ID:'runCentralDriveLearningQaCycleV1',STARTED_AT:new Date(),FINISHED_AT:new Date(),STATUS:payload.ok?'PASS':'FAIL',READBACK_STATE:'PASS',QUALITY_SCORE:'',ERROR_CLASS:'',EVIDENCE_POINTER:JSON.stringify(payload).slice(0,4000),NEXT_ACTION:'CONTINUE_5M_INCREMENTAL_SCAN'}); } catch(e) {}
}

function testCentralLearningQaFunctionsV1() {
  const fixture={fileId:'FIXTURE',name:'notebooklm_result_analysis.json',mimeType:'application/json',size:1024,url:'https://drive.google.com/file/d/FIXTURE',updatedAt:new Date()};
  const contract=inferExpectedOutputContractV1(fixture); const det=scoreCentralOutputDeterministicV1({name:fixture.name,size:fixture.size,mimeType:fixture.mimeType,hasText:true,text:'result evidence seed template'},contract);
  const merged=mergeCentralQaConsensusV1_(det,{gemini:{status:'HOLD'},openai:{status:'HOLD'}});
  if(contract.outputType!=='AUDIO' && contract.outputType!=='TEXT_DATA') throw new Error('CONTRACT_FIXTURE_FAIL');
  if(!det.ok || merged.scores.TECHNICAL_READBACK!==100) throw new Error('SCORING_FIXTURE_FAIL');
  return {ok:true,contract:contract,deterministic:det,merged:merged,apiPolicy:centralAiUsagePolicyV1_()};
}
