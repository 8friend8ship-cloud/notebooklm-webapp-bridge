const CENTRAL_MEDIA_MASTER_REGISTRY_ID = '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI';
const CENTRAL_MEDIA_BRIDGE_SHEET_ID = '1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk';
const CENTRAL_MEDIA_TZ = 'Asia/Seoul';
const CENTRAL_MEDIA_ROOT_NAME = '00_중앙에이전트';

/**
 * Strict closed-loop QA for generated image/video assets.
 * This is a logical handler: reuse an existing central 10m/15m wake.
 * Do not create another physical time trigger for this function.
 */
function runCentralMediaQaSeedLoop(context) {
  context = context || {};
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) return {ok:true, skipped:'LOCKED'};
  try {
    const props = PropertiesService.getScriptProperties();
    const now = new Date();
    const files = context.files || scanCentralMediaArtifactsV1_(props, now);
    const out = [];
    files.forEach(function(fileMeta){
      try { out.push(reviewCentralMediaArtifactStrictV1_(fileMeta, context)); }
      catch (e) {
        const failure = {ok:false,fileId:fileMeta && fileMeta.fileId || '',error:String(e && e.message || e)};
        out.push(failure);
        writeCentralMediaRuntimeEvidenceV1_({fileMeta:fileMeta||{},decision:{status:'HANDLER_ERROR',pass:false,score:0,hardFails:['HANDLER_ERROR']},requirement:{},readback:{},runtime:{},error:failure.error}, now);
      }
    });
    props.setProperty('CENTRAL_MEDIA_QA_LAST_SCAN_AT', now.toISOString());
    const summary = {
      ok:true,
      scanned:files.length,
      passX2:out.filter(function(x){return x.status==='STRICT_PASS_X2_PROMOTED';}).length,
      passX1:out.filter(function(x){return x.status==='STRICT_PASS_X1_CANDIDATE';}).length,
      hold:out.filter(function(x){return /^HOLD_/.test(String(x.status||''));}).length,
      fail:out.filter(function(x){return /FAIL|ERROR/.test(String(x.status||''));}).length,
      results:out,
      at:now
    };
    writeCentralMediaCycleReadbackV1_(summary);
    return summary;
  } finally {
    lock.releaseLock();
  }
}

function scanCentralMediaArtifactsV1_(props, now) {
  const maxFiles = Math.max(1, Math.min(20, Number(props.getProperty('CENTRAL_MEDIA_QA_MAX_FILES_PER_CYCLE') || 10)));
  const lastIso = props.getProperty('CENTRAL_MEDIA_QA_LAST_SCAN_AT') || new Date(now.getTime()-15*60*1000).toISOString();
  const rootId = props.getProperty('CENTRAL_ROOT_FOLDER_ID') || '';
  let root = null;
  if (rootId) { try { root = DriveApp.getFolderById(rootId); } catch(e){} }
  if (!root) {
    const it = DriveApp.getFoldersByName(CENTRAL_MEDIA_ROOT_NAME);
    if (it.hasNext()) root = it.next();
  }
  if (!root) throw new Error('CENTRAL_ROOT_FOLDER_NOT_FOUND');
  const out = [];
  collectRecentMediaFilesV1_(root, new Date(lastIso), 0, 3, maxFiles, out);
  return out.sort(function(a,b){return b.updatedAt-a.updatedAt;}).slice(0,maxFiles);
}

function collectRecentMediaFilesV1_(folder, since, depth, maxDepth, maxFiles, out) {
  if (out.length >= maxFiles) return;
  const files = folder.getFiles();
  while (files.hasNext() && out.length < maxFiles) {
    const f = files.next();
    const updated = f.getLastUpdated();
    if (updated <= since) continue;
    const name = f.getName();
    const mt = String(f.getMimeType()||'').toLowerCase();
    if (!(/^image\//.test(mt) || /^video\//.test(mt) || /\.(png|jpe?g|webp|gif|mp4|mov|webm|mkv)$/i.test(name))) continue;
    out.push({fileId:f.getId(),name:name,mimeType:f.getMimeType(),size:safeCentralMediaFileSizeV1_(f),url:f.getUrl(),updatedAt:updated,folderId:folder.getId()});
  }
  if (depth >= maxDepth || out.length >= maxFiles) return;
  const folders = folder.getFolders();
  while (folders.hasNext() && out.length < maxFiles) collectRecentMediaFilesV1_(folders.next(), since, depth+1, maxDepth, maxFiles, out);
}

function safeCentralMediaFileSizeV1_(f) { try { return Number(f.getSize()||0); } catch(e) { return 0; } }

function reviewCentralMediaArtifactStrictV1_(fileMeta, context) {
  const now = new Date();
  const mediaType = inferCentralMediaTypeV1_(fileMeta);
  if (!mediaType) return {ok:true,fileId:fileMeta.fileId,status:'SKIP_NON_MEDIA'};

  const requirement = resolveCentralMediaRequirementV1_(fileMeta, context);
  const readback = readCentralMediaBinaryEvidenceV1_(fileMeta, requirement);
  const routeId = String(requirement.route_id || requirement.routeId || 'MMR_MEDIA_QA_CLOSED_LOOP_V1');
  const templateId = String(requirement.template_id || requirement.templateId || 'MMT_MEDIA_PROMPT_SEED_GATE_V1');
  const workerId = String(requirement.worker_id || requirement.workerId || (requirement.runtime||{}).workerId || '');
  const tabletRoute = workerId === 'TABLET_ANDROID_01' || /TABLET/i.test(routeId);
  const runtime = tabletRoute ? readTabletScreenOffContinuityV1_() : {required:false,pass:true,status:'NOT_REQUIRED'};
  const qa = normalizeCentralMediaQaV1_(requirement.qa || requirement.quality || {});
  const lineageOk = normalizeBool100V1_(requirement.lineage_ok, requirement.lineage || requirement.source_asset_refs || requirement.sourceAssetRefs);
  const resultHash = readback.resultHash || String(requirement.result_hash || requirement.resultHash || '');
  const gateInput = {
    mediaType:mediaType,
    originalPrompt:String(requirement.original_prompt || requirement.originalPrompt || requirement.prompt || ''),
    promptVersion:String(requirement.prompt_version || requirement.promptVersion || ''),
    requirementId:String(requirement.requirement_id || requirement.requirementId || ''),
    expectedConstraints:requirement.expected_constraints || requirement.expectedConstraints || null,
    fileReadbackOk:readback.ok,
    fileSize:readback.size,
    resultHash:resultHash,
    lineagePct:lineageOk ? 100 : 0,
    qa:qa,
    tabletRequired:tabletRoute,
    screenOffContinuity:runtime.pass,
    userSatisfactionPct:normalizeOptionalNumberV1_(requirement.user_satisfaction_pct || requirement.userSatisfactionPct || (requirement.user_feedback||{}).satisfaction_pct),
    hardFails:qa.hardFails || []
  };
  const decision = evaluateCentralMediaGateV1(gateInput);
  const inputHash = String(requirement.input_hash || requirement.inputHash || hashCentralMediaTextV1_(gateInput.originalPrompt+'|'+JSON.stringify(gateInput.expectedConstraints||{})+'|'+gateInput.promptVersion));

  let priorStrict = 0;
  let x2 = false;
  if (decision.pass) {
    priorStrict = countPriorCentralMediaStrictPassesV1_(gateInput.requirementId, templateId, resultHash);
    x2 = priorStrict >= 1;
  }

  let status = decision.status;
  if (decision.pass) status = x2 ? 'STRICT_PASS_X2_PROMOTED' : 'STRICT_PASS_X1_CANDIDATE';

  const reviewQueue = (!decision.pass && decision.reviewRequired && gateInput.originalPrompt && gateInput.requirementId)
    ? queueCentralMediaPromptQaV1_(fileMeta, requirement, mediaType, decision)
    : {queued:false,reason:'NOT_REQUIRED_OR_MISSING_PROMPT'};

  const fix = buildCentralMediaMinimumFixV1_(decision, requirement, mediaType);
  const qaRunId = 'QA_MEDIA_'+Utilities.formatDate(now,CENTRAL_MEDIA_TZ,'yyyyMMdd_HHmmss')+'_'+shortCentralMediaIdV1_(fileMeta.fileId);

  writeCentralMediaQaHistoryV1_({
    qaRunId:qaRunId, now:now, fileMeta:fileMeta, requirement:requirement, routeId:routeId, templateId:templateId,
    inputHash:inputHash, mediaType:mediaType, readback:readback, runtime:runtime, decision:decision,
    status:status, fix:fix, resultHash:resultHash, reviewQueue:reviewQueue
  });

  // Legacy generic audit can temporarily auto-promote media. Strict media gate owns final promotion.
  quarantineLegacyGenericMediaSeedV1_(fileMeta.fileId, status, qaRunId+'|'+(resultHash||'NO_HASH'));

  let promotion = {promoted:false,state:status};
  if (status === 'STRICT_PASS_X2_PROMOTED') {
    promotion = promoteCentralMediaStrictPassV1_({
      qaRunId:qaRunId, now:now, fileMeta:fileMeta, requirement:requirement, routeId:routeId, templateId:templateId,
      inputHash:inputHash, mediaType:mediaType, readback:readback, decision:decision, resultHash:resultHash
    });
  } else {
    writeCentralMediaEvolutionV1_({qaRunId:qaRunId,now:now,fileMeta:fileMeta,requirement:requirement,decision:decision,status:status,fix:fix,mediaType:mediaType,resultHash:resultHash,templateId:templateId});
  }

  writeCentralMediaRuntimeEvidenceV1_({
    fileMeta:fileMeta, requirement:requirement, decision:decision, status:status, readback:readback, runtime:runtime,
    resultHash:resultHash, qaRunId:qaRunId, fix:fix, promotion:promotion, reviewQueue:reviewQueue, priorStrict:priorStrict
  }, now);

  return {ok:decision.pass,fileId:fileMeta.fileId,mediaType:mediaType,status:status,score:decision.score,hardFails:decision.hardFails,reviewRequired:decision.reviewRequired,x2:x2,priorStrict:priorStrict,resultHash:resultHash,promotion:promotion,reviewQueue:reviewQueue,fix:fix,runtime:runtime};
}

/** Pure gate: intentionally free of Apps Script services so CI can execute it. */
function evaluateCentralMediaGateV1(input) {
  input = input || {};
  const qa = input.qa || {};
  const hard = [];
  function add(x){ if (hard.indexOf(x)<0) hard.push(x); }
  (input.hardFails || []).forEach(add);
  (qa.hardFails || []).forEach(add);

  const prompt = String(input.originalPrompt || '').trim();
  const reqId = String(input.requirementId || '').trim();
  const promptVersion = String(input.promptVersion || '').trim();
  const constraints = input.expectedConstraints;
  const constraintsPresent = !!constraints && (typeof constraints !== 'object' || Object.keys(constraints).length>0) && (!Array.isArray(constraints) || constraints.length>0);

  if (!reqId) add('REQUIREMENT_ID_MISSING');
  if (!prompt) add('ORIGINAL_PROMPT_MISSING');
  if (!promptVersion) add('PROMPT_VERSION_MISSING');
  if (!constraintsPresent) add('EXPECTED_CONSTRAINTS_MISSING');
  if (!input.fileReadbackOk || Number(input.fileSize||0)<=0) add('FILE_READBACK_FAILED');
  if (!String(input.resultHash||'')) add('RESULT_HASH_MISSING');
  if (Number(input.lineagePct||0) < 100) add('LINEAGE_INCOMPLETE');
  if (input.tabletRequired && !input.screenOffContinuity) add('TABLET_SCREEN_OFF_CONTINUITY_FAIL');

  const critical = normalizeGateNumberV1_(qa.criticalConstraintsPct);
  const promptFidelity = normalizeGateNumberV1_(qa.promptFidelity);
  const purposeFit = normalizeGateNumberV1_(qa.purposeFit);
  const mediaSpecific = normalizeGateNumberV1_(qa.mediaSpecific);
  const continuity = normalizeGateNumberV1_(qa.continuity);
  const satisfaction = input.userSatisfactionPct === null || typeof input.userSatisfactionPct === 'undefined' ? null : Number(input.userSatisfactionPct);

  let reviewRequired = false;
  if (critical === null || promptFidelity === null || purposeFit === null || mediaSpecific === null) {
    add('PROMPT_MEDIA_QA_MISSING'); reviewRequired = true;
  }
  if (critical !== null && critical < 100) add('CRITICAL_CONSTRAINT_MISS');
  if (promptFidelity !== null && promptFidelity < 90) add('PROMPT_FIDELITY_BELOW_90');
  if (purposeFit !== null && purposeFit < 90) add('PURPOSE_FIT_BELOW_90');
  if (mediaSpecific !== null && mediaSpecific < 90) add('MEDIA_SPECIFIC_QA_BELOW_90');
  if (String(input.mediaType||'').toUpperCase()==='VIDEO' && continuity === null) { add('VIDEO_CONTINUITY_QA_MISSING'); reviewRequired = true; }
  if (String(input.mediaType||'').toUpperCase()==='VIDEO' && continuity !== null && continuity < 90) add('VIDEO_CONTINUITY_BELOW_90');
  if (satisfaction !== null && !isNaN(satisfaction) && satisfaction < 80) add('USER_SATISFACTION_BELOW_80');

  const scores = [critical,promptFidelity,purposeFit,mediaSpecific];
  if (String(input.mediaType||'').toUpperCase()==='VIDEO' && continuity !== null) scores.push(continuity);
  if (satisfaction !== null && !isNaN(satisfaction)) scores.push(satisfaction);
  const valid = scores.filter(function(v){return v !== null && !isNaN(v);});
  const score = valid.length ? Math.round(valid.reduce(function(a,b){return a+b;},0)/valid.length) : 0;
  const pass = hard.length===0;
  let status = pass ? 'STRICT_BASE_PASS' : (reviewRequired ? 'HOLD_PROMPT_QA_REQUIRED' : 'STRICT_FAIL_RETEST');
  return {pass:pass,status:status,score:score,hardFails:hard,reviewRequired:reviewRequired,scores:{criticalConstraintsPct:critical,promptFidelity:promptFidelity,purposeFit:purposeFit,mediaSpecific:mediaSpecific,continuity:continuity,userSatisfactionPct:satisfaction}};
}

function normalizeGateNumberV1_(v) {
  if (v === null || typeof v === 'undefined' || v === '') return null;
  const n = Number(v); return isNaN(n) ? null : Math.max(0,Math.min(100,n));
}

function inferCentralMediaTypeV1_(fileMeta) {
  const n = String(fileMeta.name||''); const mt = String(fileMeta.mimeType||'').toLowerCase();
  if (/^image\//.test(mt) || /\.(png|jpe?g|webp|gif)$/i.test(n)) return 'IMAGE';
  if (/^video\//.test(mt) || /\.(mp4|mov|webm|mkv)$/i.test(n)) return 'VIDEO';
  return '';
}

function resolveCentralMediaRequirementV1_(fileMeta, context) {
  context = context || {};
  const direct = context.requirementsByResultId && context.requirementsByResultId[fileMeta.fileId];
  if (direct) return normalizeCentralMediaRequirementV1_(direct);
  if (context.requirement && (!context.requirement.result_file_id || context.requirement.result_file_id===fileMeta.fileId)) return normalizeCentralMediaRequirementV1_(context.requirement);
  const sidecar = findCentralMediaManifestV1_(fileMeta);
  return normalizeCentralMediaRequirementV1_(sidecar || {});
}

function normalizeCentralMediaRequirementV1_(r) {
  r = r || {};
  if (r.manifest && typeof r.manifest === 'object') r = r.manifest;
  return r;
}

function findCentralMediaManifestV1_(fileMeta) {
  try {
    const file = DriveApp.getFileById(fileMeta.fileId);
    const parents = file.getParents();
    if (!parents.hasNext()) return null;
    const folder = parents.next();
    const name = file.getName();
    const stem = name.replace(/\.[^.]+$/,'');
    const candidates = [name+'.manifest.json',stem+'.manifest.json',fileMeta.fileId+'.manifest.json','manifest_'+fileMeta.fileId+'.json','QA_MEDIA_'+fileMeta.fileId+'.json'];
    for (let i=0;i<candidates.length;i++) {
      const it = folder.getFilesByName(candidates[i]);
      if (it.hasNext()) { const parsed = parseCentralMediaJsonFileV1_(it.next()); if (manifestMatchesResultV1_(parsed,fileMeta.fileId,true)) return parsed; }
    }
    const files = folder.getFiles(); let scanned=0;
    while (files.hasNext() && scanned<80) {
      const f=files.next(); scanned++;
      if (!/manifest|QA_MEDIA/i.test(f.getName()) || !/json|text/.test(String(f.getMimeType()||''))) continue;
      const parsed=parseCentralMediaJsonFileV1_(f);
      if (manifestMatchesResultV1_(parsed,fileMeta.fileId,false)) return parsed;
    }
  } catch(e) {}
  return null;
}

function parseCentralMediaJsonFileV1_(f) {
  try { return JSON.parse(f.getBlob().getDataAsString('UTF-8')); } catch(e) { return null; }
}
function manifestMatchesResultV1_(m,fileId,allowBlank) {
  if (!m || typeof m!=='object') return false;
  const x = m.manifest && typeof m.manifest==='object' ? m.manifest : m;
  const id = String(x.result_file_id || x.resultFileId || x.file_id || x.fileId || x.result_id || x.resultId || '');
  return id ? id===String(fileId) : !!allowBlank;
}

function readCentralMediaBinaryEvidenceV1_(fileMeta, requirement) {
  const out={ok:false,size:Number(fileMeta.size||0),mimeType:String(fileMeta.mimeType||''),url:fileMeta.url||'',resultHash:''};
  try {
    const f=DriveApp.getFileById(fileMeta.fileId);
    out.size=safeCentralMediaFileSizeV1_(f); out.mimeType=f.getMimeType(); out.url=f.getUrl();
    if (out.size>0 && out.size<=10*1024*1024) {
      out.resultHash=bytesToHexCentralMediaV1_(Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256,f.getBlob().getBytes()));
    } else {
      out.resultHash=String(requirement.result_hash || requirement.resultHash || '');
    }
    out.ok=out.size>0 && !!inferCentralMediaTypeV1_({name:f.getName(),mimeType:out.mimeType});
  } catch(e) { out.error=String(e && e.message || e); }
  return out;
}

function bytesToHexCentralMediaV1_(bytes) {
  return bytes.map(function(b){const v=(b<0?b+256:b).toString(16);return v.length===1?'0'+v:v;}).join('');
}
function hashCentralMediaTextV1_(s) { return bytesToHexCentralMediaV1_(Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256,String(s||''),Utilities.Charset.UTF_8)); }
function shortCentralMediaIdV1_(s) { return String(s||'').replace(/[^A-Za-z0-9]/g,'').slice(-10) || 'NA'; }
function normalizeOptionalNumberV1_(v) { if (v===null || typeof v==='undefined' || v==='') return null; const n=Number(v); return isNaN(n)?null:n; }
function normalizeBool100V1_(explicit, fallback) {
  if (explicit===true || explicit===100 || String(explicit).toUpperCase()==='PASS' || String(explicit).toUpperCase()==='TRUE') return true;
  if (explicit===false || explicit===0 || String(explicit).toUpperCase()==='FAIL' || String(explicit).toUpperCase()==='FALSE') return false;
  if (Array.isArray(fallback)) return fallback.length>0;
  if (fallback && typeof fallback==='object') return Object.keys(fallback).length>0;
  return !!String(fallback||'').trim();
}

function normalizeCentralMediaQaV1_(qa) {
  qa=qa||{};
  return {
    criticalConstraintsPct:firstMediaQaNumberV1_(qa,['critical_constraints_pct','criticalConstraintsPct','critical_constraints','criticalConstraints']),
    promptFidelity:firstMediaQaNumberV1_(qa,['prompt_fidelity','promptFidelity','PROMPT_FIDELITY']),
    purposeFit:firstMediaQaNumberV1_(qa,['purpose_fit','purposeFit','PURPOSE_FIT','goal_alignment']),
    mediaSpecific:firstMediaQaNumberV1_(qa,['media_specific','mediaSpecific','image_quality','video_quality','quality_level']),
    continuity:firstMediaQaNumberV1_(qa,['continuity','video_continuity','av_continuity','timeline_continuity']),
    hardFails:qa.hard_fails || qa.hardFails || []
  };
}
function firstMediaQaNumberV1_(obj,keys){ for(let i=0;i<keys.length;i++){ if(Object.prototype.hasOwnProperty.call(obj,keys[i])) return normalizeGateNumberV1_(obj[keys[i]]); } return null; }

function readTabletScreenOffContinuityV1_() {
  const out={required:true,pass:false,status:'MISSING',evidence:''};
  try {
    const it=DriveApp.getFilesByName('TABLET_SCREEN_OFF_CONTINUITY.json');
    let latest=null;
    while(it.hasNext()){const f=it.next(); if(!latest || f.getLastUpdated()>latest.getLastUpdated()) latest=f;}
    if(!latest) return out;
    const j=JSON.parse(latest.getBlob().getDataAsString('UTF-8'));
    const screen=String(j.screen||j.screen_state||'').toUpperCase();
    const hb=Number(j.off_heartbeat_count||j.offHeartbeatCount||j.consecutive_off_heartbeats||0);
    const watcher=String(j.watcher||j.watcher_status||'').toUpperCase();
    const supervisor=String(j.supervisor||j.supervisor_status||'').toUpperCase();
    const uploaded=!!(j.drive_upload_verified || j.driveUploadVerified || j.upload_verified);
    out.pass=screen==='OFF' && hb>=2 && /RUNNING/.test(watcher) && /RUNNING/.test(supervisor) && uploaded;
    out.status=out.pass?'PASS':'FAIL'; out.evidence=latest.getId(); out.payload=j; return out;
  } catch(e) { out.status='ERROR'; out.error=String(e && e.message || e); return out; }
}

function queueCentralMediaPromptQaV1_(fileMeta, requirement, mediaType, decision) {
  try {
    const props=PropertiesService.getScriptProperties();
    const promptVersion=String(requirement.prompt_version||requirement.promptVersion||'NA');
    const dedupe='CENTRAL_MEDIA_UI_QA_'+fileMeta.fileId+'_'+promptVersion;
    if(props.getProperty(dedupe)) return {queued:false,reason:'ALREADY_QUEUED',ids:props.getProperty(dedupe)};
    const ss=SpreadsheetApp.openById(CENTRAL_MEDIA_BRIDGE_SHEET_ID); const sh=ss.getSheetByName('TASK_QUEUE');
    if(!sh) return {queued:false,reason:'TASK_QUEUE_MISSING'};
    const providers=['GEMINI_AI_STUDIO','OPENAI_CHATGPT_CENTRAL_AGENT']; const ids=[];
    providers.forEach(function(provider){
      const taskId='TASK_MEDIA_QA_'+provider.replace(/[^A-Z0-9]/g,'_')+'_'+shortCentralMediaIdV1_(fileMeta.fileId)+'_'+Utilities.formatDate(new Date(),CENTRAL_MEDIA_TZ,'yyyyMMddHHmmss');
      const payload={
        provider:provider,task:'CENTRAL_MEDIA_PROMPT_QA_V1',requirementId:requirement.requirement_id||requirement.requirementId||'',promptVersion:promptVersion,
        resultFileId:fileMeta.fileId,resultFileUrl:fileMeta.url,mediaType:mediaType,originalPrompt:requirement.original_prompt||requirement.originalPrompt||requirement.prompt||'',
        expectedConstraints:requirement.expected_constraints||requirement.expectedConstraints||{},
        returnOnly:{critical_constraints_pct:'0-100',prompt_fidelity:'0-100',purpose_fit:'0-100',media_specific:'0-100',continuity:'0-100 if video',hard_fails:'array',weak_dimensions:'array',minimum_prompt_patch:'string',seed_worthiness:'0-100'},
        successCriteria:'ACTUAL_FILE_VS_PROMPT_JSON_QA+DRIVE_READBACK;NO_SEED_PROMOTION_BY_REVIEWER',usagePolicy:'SUBSCRIPTION_UI_FIRST;API_ONLY_IF_EXISTING_CAP_PROPERTY>0'
      };
      sh.appendRow([taskId,'CENTRAL_AGENT','AI_REVIEW_'+provider,JSON.stringify(payload),'QUEUED',4,new Date(),'','','','','','MEDIA_QA_'+fileMeta.fileId]); ids.push(taskId);
    });
    props.setProperty(dedupe,ids.join('|')); return {queued:true,ids:ids};
  } catch(e) { return {queued:false,reason:'QUEUE_ERROR',error:String(e && e.message || e)}; }
}

function buildCentralMediaMinimumFixV1_(decision, requirement, mediaType) {
  const hard=decision.hardFails||[]; const patches=[];
  if(hard.indexOf('TABLET_SCREEN_OFF_CONTINUITY_FAIL')>=0) patches.push('RUNTIME_ONLY: fix tablet OS wake/Automate/Boot continuity; do not regenerate media merely to mask screen-off failure');
  if(hard.indexOf('ORIGINAL_PROMPT_MISSING')>=0 || hard.indexOf('EXPECTED_CONSTRAINTS_MISSING')>=0) patches.push('RESTORE_SOURCE_REQUIREMENT: preserve original prompt and critical/preferred/forbidden constraints in sidecar manifest');
  if(hard.indexOf('CRITICAL_CONSTRAINT_MISS')>=0) patches.push('PROMPT_DELTA: reassert only missed critical constraints; preserve passing clauses');
  if(hard.indexOf('PROMPT_FIDELITY_BELOW_90')>=0) patches.push('PROMPT_DELTA: clarify weak prompt dimension without rewriting passing dimensions');
  if(hard.indexOf('PURPOSE_FIT_BELOW_90')>=0) patches.push('PROMPT_DELTA: add exact use/platform/audience intent');
  if(hard.indexOf('MEDIA_SPECIFIC_QA_BELOW_90')>=0) patches.push(mediaType==='VIDEO'?'VIDEO_DELTA: patch only weak scene/camera/motion/visual dimension':'IMAGE_DELTA: patch only weak composition/persona/material/text/geometry dimension');
  if(hard.indexOf('VIDEO_CONTINUITY_BELOW_90')>=0 || hard.indexOf('VIDEO_CONTINUITY_QA_MISSING')>=0) patches.push('VIDEO_DELTA: enforce scene continuity, A/V sync, temporal consistency');
  if(hard.indexOf('FILE_READBACK_FAILED')>=0 || hard.indexOf('RESULT_HASH_MISSING')>=0) patches.push('ARTIFACT_DELTA: fix binary download/readback/hash before content regeneration');
  if(hard.indexOf('LINEAGE_INCOMPLETE')>=0) patches.push('LINEAGE_DELTA: restore source asset/seed/template/result lineage');
  if(hard.indexOf('PROMPT_MEDIA_QA_MISSING')>=0) patches.push('QA_ONLY: run actual-file vs original-prompt visual/video review; hold Seed/Template promotion');
  if(hard.indexOf('USER_SATISFACTION_BELOW_80')>=0) patches.push('USER_FEEDBACK_DELTA: preserve passing dimensions and patch only explicit user dissatisfaction');
  return patches.length?patches.join(' | '):'NO_CONTENT_PATCH_REQUIRED';
}

function countPriorCentralMediaStrictPassesV1_(requirementId, templateId, currentHash) {
  if(!requirementId) return 0;
  const ss=SpreadsheetApp.openById(CENTRAL_MEDIA_MASTER_REGISTRY_ID); const sh=ss.getSheetByName('71_MULTIMODAL_QA_HISTORY'); if(!sh)return 0;
  const data=sh.getDataRange().getValues(); if(data.length<2)return 0; const h={}; data[0].forEach(function(x,i){h[x]=i;});
  const hashes={};
  for(let i=data.length-1;i>=1;i--){
    const row=data[i]; if(String(row[h.REQUIREMENT_ID]||'')!==String(requirementId))continue;
    if(templateId && String(row[h.TEMPLATE_ID]||'')!==String(templateId))continue;
    if(!/^STRICT_PASS_X[12]/.test(String(row[h.STATUS]||'')))continue;
    const blob=String(row[h.IMAGE_QA]||row[h.VIDEO_QA]||''); let j={}; try{j=JSON.parse(blob);}catch(e){}
    const rh=String(j.resultHash||''); if(rh && rh!==String(currentHash||''))hashes[rh]=1;
  }
  return Object.keys(hashes).length;
}

function writeCentralMediaQaHistoryV1_(x) {
  const qaPayload={resultHash:x.resultHash,scores:x.decision.scores,hardFails:x.decision.hardFails,readback:x.readback,runtime:x.runtime,reviewQueue:x.reviewQueue};
  appendCentralMediaByHeaderV1_('71_MULTIMODAL_QA_HISTORY',{
    RUN_ID:x.qaRunId,RUN_AT:x.now,REQUIREMENT_ID:x.requirement.requirement_id||x.requirement.requirementId||'',ROUTE_ID:x.routeId,TEMPLATE_ID:x.templateId,
    INPUT_HASH:x.inputHash,PRIMARY_RESULT:x.fileMeta.fileId,FALLBACK_USED:x.requirement.fallback_used||x.requirement.fallbackUsed||'NO',
    TEXT_QA:'N/A',IMAGE_QA:x.mediaType==='IMAGE'?JSON.stringify(qaPayload):'N/A',VIDEO_QA:x.mediaType==='VIDEO'?JSON.stringify(qaPayload):'N/A',
    LINEAGE_QA:x.decision.hardFails.indexOf('LINEAGE_INCOMPLETE')<0?'PASS':'FAIL',
    READBACK_X2:x.status==='STRICT_PASS_X2_PROMOTED'?'PASS_X2':(x.readback.ok?'PASS_X1_OR_HOLD':'FAIL'),SCORE:x.decision.score,
    ERROR_CLASS:(x.decision.hardFails||[]).join('|'),FIX_APPLIED:x.fix,LEARNED_RULE_OR_CHANGE_ID:'CHG_CENTRAL_MEDIA_QA_SEED_LOOP_20260831_001',STATUS:x.status
  });
}

function quarantineLegacyGenericMediaSeedV1_(fileId, strictStatus, evidence) {
  try {
    const ss=SpreadsheetApp.openById(CENTRAL_MEDIA_MASTER_REGISTRY_ID); const sh=ss.getSheetByName('35_INTERNAL_SEED_REGISTRY'); if(!sh)return 0;
    const data=sh.getDataRange().getValues(); if(data.length<2)return 0; const h={}; data[0].forEach(function(x,i){h[x]=i;}); let changed=0;
    for(let i=data.length-1;i>=1;i--){
      const row=data[i]; if(String(row[h.SOURCE_TYPE]||'')!=='CENTRAL_AUDIT_PASS')continue; if(String(row[h.SOURCE_IDS]||'').indexOf(String(fileId))<0)continue;
      const next = strictStatus==='STRICT_PASS_X2_PROMOTED' ? 'SUPERSEDED_BY_STRICT_MEDIA_X2' : (strictStatus==='STRICT_PASS_X1_CANDIDATE'?'SEED_CANDIDATE_MEDIA_X1_HOLD':'SEED_HOLD_MEDIA_GATE_REQUIRED');
      if(h.STATUS>=0) sh.getRange(i+1,h.STATUS+1).setValue(next);
      if(h.UPDATED_AT>=0) sh.getRange(i+1,h.UPDATED_AT+1).setValue(new Date());
      if(h.EVIDENCE>=0) sh.getRange(i+1,h.EVIDENCE+1).setValue(String(row[h.EVIDENCE]||'')+'|STRICT_MEDIA_GATE:'+evidence);
      changed++;
    }
    return changed;
  } catch(e) { return 0; }
}

function promoteCentralMediaStrictPassV1_(x) {
  const reqId=String(x.requirement.requirement_id||x.requirement.requirementId||'');
  const promptVersion=String(x.requirement.prompt_version||x.requirement.promptVersion||'1');
  const stable=shortCentralMediaHashV1_(reqId+'|'+x.templateId+'|'+promptVersion);
  const seedId='SEED_MEDIA_STRICT_'+stable;
  const strictTemplateId='MMT_STRICT_'+x.mediaType+'_'+stable+'_V'+promptVersion.replace(/[^A-Za-z0-9]/g,'_');
  const sourceIds=x.fileMeta.fileId+'|'+x.resultHash+'|'+x.qaRunId;
  const evidence=x.qaRunId+'|RESULT:'+x.fileMeta.fileId+'|HASH:'+x.resultHash+'|PROMPT_VERSION:'+promptVersion;
  let seedInserted=false, templateInserted=false;
  if(!centralMediaSheetHasValueV1_('35_INTERNAL_SEED_REGISTRY','SEED_ID',seedId)) {
    appendCentralMediaByHeaderV1_('35_INTERNAL_SEED_REGISTRY',{
      SEED_ID:seedId,APP_ID:x.requirement.app_id||x.requirement.appId||'CENTRAL_AGENT',SOURCE_TYPE:'CENTRAL_MEDIA_STRICT_X2_PASS',SOURCE_IDS:sourceIds,
      TOPIC_ID:reqId,SEED_TEXT:String(x.requirement.seed_text||x.requirement.seedText||x.requirement.original_prompt||x.requirement.originalPrompt||x.requirement.prompt||''),
      INPUT_SCHEMA_VERSION:'CENTRAL_MEDIA_PROMPT_SEED_GATE_V1',QUEENS_STATUS:'STRICT_QA_X2_PASS',STATUS:'VERIFIED_ACTIVE',CREATED_AT:x.now,UPDATED_AT:x.now,EVIDENCE:evidence
    }); seedInserted=true;
  }
  if(!centralMediaSheetHasValueV1_('70_MULTIMODAL_TEMPLATE_LIBRARY','TEMPLATE_ID',strictTemplateId)) {
    appendCentralMediaByHeaderV1_('70_MULTIMODAL_TEMPLATE_LIBRARY',{
      TEMPLATE_ID:strictTemplateId,MEDIA_TYPE:x.mediaType,VERSION:promptVersion,USE_WHEN:'verified requirement family '+reqId,
      REQUIREMENT_SCHEMA:'requirement_id,prompt_version,original_prompt,expected_constraints,goal,use,audience/platform,source_asset_refs,worker/runtime',
      TOOL_CHAIN:String(x.requirement.tool_chain||x.requirement.toolChain||x.routeId),
      PROMPT_ASSEMBLY:'PRESERVE_ORIGINAL_PROMPT;APPLY_ONLY_VERIFIED_DELTA;'+String(x.requirement.original_prompt||x.requirement.originalPrompt||x.requirement.prompt||''),
      QA_RULE:'critical=100;prompt_fidelity>=90;purpose_fit>=90;media_specific>=90;file/hash/readback=100;lineage=100;hardFail=0;tablet screen-off if used',
      RETRY_RULE:'same JOB lineage; patch failed dimension only; x2 before general promotion',
      OUTPUT_SCHEMA:'result_pointer,prompt_version,input_hash,result_hash,qa_scores,hard_fails,error_class,fix_delta,seed_state,template_state,lineage',
      STORAGE:'Drive binary pointer + 71 QA + 35 seed + 77 evolution',PROMOTION_GATE:'STRICT_X2 + next-job reuse smoke',STATUS:'ACTIVE_VERIFIED_X2',NOTES:evidence
    }); templateInserted=true;
  }
  appendCentralMediaByHeaderV1_('77_TEMPLATE_EVOLUTION_FACTORY',{
    EVOLVE_ID:'EVOLVE_MEDIA_PROMOTE_'+stable+'_'+Utilities.formatDate(x.now,CENTRAL_MEDIA_TZ,'yyyyMMddHHmmss'),TRIGGER:'strict media x2 pass',INPUT_RESULT:x.fileMeta.fileId+'|'+x.resultHash,
    MEASURE:'critical/prompt/purpose/media/readback/lineage',BEST_COMPONENTS:'original prompt passing clauses + expected constraints + verified tool path',WEAK_COMPONENTS:'none critical',
    NEW_TEMPLATE:strictTemplateId,SOURCE_PACKS:'35:'+seedId+'|70:'+strictTemplateId,REPO_PATCH:'N/A',APPS_SCRIPT_PATCH:'runCentralMediaQaSeedLoop',API_DELTA:'NONE;UI/subscription-first',
    PROMOTION_GATE:'STRICT_X2_PASS',REGRESSION:'next-job reuse smoke required',WRITEBACK:'35/70/71/63/80/84/93',STATUS:'PROMOTED_X2_PENDING_REUSE_SMOKE',VERSION:'MEDIA_PROMPT_SEED_EVOLVE_V1',OWNER:'CENTRAL_AGENT',NOTES:evidence
  });
  appendCentralMediaByHeaderV1_('63_EVOLUTION_CHANGELOG',{
    CHANGE_ID:'CHG_MEDIA_PROMOTE_'+stable+'_'+Utilities.formatDate(x.now,CENTRAL_MEDIA_TZ,'yyyyMMddHHmmss'),CREATED_AT:x.now,SOURCE_RESEARCH_ID:reqId,
    APP_ID:x.requirement.app_id||x.requirement.appId||'CENTRAL_AGENT',CHANGE_LEVEL:'TEMPLATE_SEED',CHANGE_TYPE:'STRICT_MEDIA_X2_PROMOTION',BEFORE:'candidate/legacy generic media seed',
    PROPOSAL:'promote only verified strict x2 Seed/Template',WHY_NOW:'actual result passed prompt/purpose/media/readback/lineage x2 gate',EVIDENCE_IDS:evidence,
    EXPECTED_IMPACT:'quality consistency and reduced bad-seed contamination',RISK:'LOW',TASK_ID:'TASK_20260831_CENTRAL_MEDIA_QA_SEED_LOOP_001',GITHUB_REPO:'8friend8ship-cloud/notebooklm-webapp-bridge',
    BACKEND_FUNCTION:'runCentralMediaQaSeedLoop',TEST_CASE:'same requirement/template distinct result hash x2',TEST_RESULT:'PASS_X2',DECISION:'PROMOTE_STRICT',STATUS:'ACTIVE_VERIFIED_X2',ROLLED_BACK:false
  });
  return {promoted:true,seedId:seedId,templateId:strictTemplateId,seedInserted:seedInserted,templateInserted:templateInserted,evidence:evidence};
}

function writeCentralMediaEvolutionV1_(x) {
  const reqId=String(x.requirement.requirement_id||x.requirement.requirementId||'');
  const id=shortCentralMediaHashV1_(reqId+'|'+x.fileMeta.fileId+'|'+x.status);
  appendCentralMediaByHeaderV1_('77_TEMPLATE_EVOLUTION_FACTORY',{
    EVOLVE_ID:'EVOLVE_MEDIA_'+id+'_'+Utilities.formatDate(x.now,CENTRAL_MEDIA_TZ,'yyyyMMddHHmmss'),TRIGGER:'strict media '+x.status,INPUT_RESULT:x.fileMeta.fileId+'|'+x.resultHash,
    MEASURE:'prompt fidelity,purpose fit,critical constraints,media quality,readback,lineage,satisfaction',BEST_COMPONENTS:'preserve all passing dimensions',
    WEAK_COMPONENTS:(x.decision.hardFails||[]).join('|'),NEW_TEMPLATE:'HOLD_UNTIL_RETEST',SOURCE_PACKS:'existing 35/70/76/LAST_GOOD',REPO_PATCH:'only if route/code failure',
    APPS_SCRIPT_PATCH:'minimum only after exact source/version diff',API_DELTA:'UI/subscription-first; no budget creation',PROMOTION_GATE:'same fixture x2 + no hard fail',
    REGRESSION:'same requirement/template fixture',WRITEBACK:'71/63/80/84/93',STATUS:x.status,VERSION:'MEDIA_PROMPT_SEED_EVOLVE_V1',OWNER:'CENTRAL_AGENT',NOTES:x.fix
  });
  if(x.status!=='STRICT_PASS_X1_CANDIDATE') {
    appendCentralMediaByHeaderV1_('63_EVOLUTION_CHANGELOG',{
      CHANGE_ID:'CHG_MEDIA_FIX_'+id+'_'+Utilities.formatDate(x.now,CENTRAL_MEDIA_TZ,'yyyyMMddHHmmss'),CREATED_AT:x.now,SOURCE_RESEARCH_ID:reqId,
      APP_ID:x.requirement.app_id||x.requirement.appId||'CENTRAL_AGENT',CHANGE_LEVEL:'PROMPT_OR_RUNTIME',CHANGE_TYPE:'STRICT_MEDIA_FAILURE_LEARNING',BEFORE:'failed generated result '+x.fileMeta.fileId,
      PROPOSAL:x.fix,WHY_NOW:'strict media gate failure',EVIDENCE_IDS:x.fileMeta.fileId+'|'+x.resultHash,EXPECTED_IMPACT:'prevent repeat and preserve passing dimensions',
      RISK:'LOW',TASK_ID:'TASK_20260831_CENTRAL_MEDIA_QA_SEED_LOOP_001',GITHUB_REPO:'8friend8ship-cloud/notebooklm-webapp-bridge',BACKEND_FUNCTION:'runCentralMediaQaSeedLoop',
      TEST_CASE:'same JOB lineage retest',TEST_RESULT:'PENDING_RETEST',DECISION:'HOLD_PROMOTION_MIN_FIX',STATUS:'ACTIVE_RETEST_REQUIRED',ROLLED_BACK:false
    });
  }
}

function writeCentralMediaRuntimeEvidenceV1_(x, now) {
  const reqId=String((x.requirement||{}).requirement_id||(x.requirement||{}).requirementId||'');
  const status=String(x.status||x.decision.status||'UNKNOWN'); const hard=(x.decision.hardFails||[]).join('|');
  const resultId=String((x.fileMeta||{}).fileId||''); const evidence=String((x.readback||{}).url||(x.fileMeta||{}).url||resultId);
  appendCentralMediaByHeaderV1_('80_DATA_RUNTIME_QA_LOG',{
    QA_ID:x.qaRunId||('QA_MEDIA_ERR_'+Utilities.formatDate(now,CENTRAL_MEDIA_TZ,'yyyyMMddHHmmss')),RUN_ID:reqId||'MEDIA_SCAN',APP_ID:(x.requirement||{}).app_id||(x.requirement||{}).appId||'CENTRAL_AGENT',
    FUNCTION_ID:'runCentralMediaQaSeedLoop',TRIGGER_ID:'TRG_CENTRAL_MEDIA_QA_10M_LOGICAL',INPUT_DATA_IDS:reqId+'|'+((x.requirement||{}).prompt_version||(x.requirement||{}).promptVersion||''),
    INPUT_HASH:(x.requirement||{}).input_hash||(x.requirement||{}).inputHash||'',OUTPUT_DATA_IDS:resultId+'|'+String(x.resultHash||''),RESULT_ID:resultId,STARTED_AT:now,FINISHED_AT:now,
    STATUS:status,READBACK_STATE:(x.readback||{}).ok?'PASS':'FAIL',QUALITY_SCORE:Number(x.decision.score||0),ERROR_CLASS:hard,RETRY_COUNT:Number((x.requirement||{}).retry_count||0),
    EVIDENCE_POINTER:evidence,NEXT_ACTION:status==='STRICT_PASS_X2_PROMOTED'?'NEXT_JOB_REUSE_SMOKE':(status==='STRICT_PASS_X1_CANDIDATE'?'GENERATE_DISTINCT_SAME_FIXTURE_X2':(x.fix||'MIN_FIX_RETEST'))
  });
  appendCentralMediaByHeaderV1_('84_OPENAI_CENTRAL_AUDIT',{
    AUDIT_ID:'AUDIT_MEDIA_'+(x.qaRunId||Utilities.formatDate(now,CENTRAL_MEDIA_TZ,'yyyyMMddHHmmss')),AUDIT_AT:now,TASK_ID:'TASK_20260831_CENTRAL_MEDIA_QA_SEED_LOOP_001',
    APP_ID:(x.requirement||{}).app_id||(x.requirement||{}).appId||'CENTRAL_AGENT',AUDITOR_SOURCE:'OPENAI_CHATGPT_CENTRAL_AGENT',CENTRAL_CLAIM:'actual media must match original prompt and be seed-worthy before promotion',
    EVIDENCE_IDS:reqId+'|'+resultId+'|'+String(x.resultHash||''),OPENAI_CHECK:JSON.stringify({scores:x.decision.scores||{},hardFails:x.decision.hardFails||[],reviewQueue:x.reviewQueue||{}}),
    MATCH_STATE:x.decision.pass?'MATCH':'GAP',DISCREPANCY:hard,CORRECTED_STATE:status,ACTION:status==='STRICT_PASS_X2_PROMOTED'?'STRICT_PROMOTE_AND_REUSE':'HOLD_MIN_FIX_SAME_LINEAGE_RETEST',
    STATUS:status,API_MODE:'NO_NEW_OPENAI_API',REVIEW_METHOD:'CENTRAL_MEDIA_PROMPT_SEED_GATE_V1',VERSION:'CENTRAL_MEDIA_QA_LOOP_V1',FILE_EVIDENCE_COUNT:resultId?1:0,MAIL_EVIDENCE_COUNT:0,
    RUNTIME_EVIDENCE:JSON.stringify(x.runtime||{}),NOTES:JSON.stringify({promotion:x.promotion||{},priorStrict:x.priorStrict||0,fix:x.fix||'',error:x.error||''}).slice(0,4000)
  });
  appendCentralMediaByHeaderV1_('93_RUNTIME_EVIDENCE_CONTROL',{
    EVIDENCE_ID:'EVID_MEDIA_'+(x.qaRunId||Utilities.formatDate(now,CENTRAL_MEDIA_TZ,'yyyyMMddHHmmss')),PROJECT_ID:'P00_CENTRAL_MEDIA_QA',APP_ID:(x.requirement||{}).app_id||(x.requirement||{}).appId||'CENTRAL_AGENT',
    FUNCTION_OR_ROUTE:'runCentralMediaQaSeedLoop',RUN_ID:x.qaRunId||'',RESULT_ID:resultId,FRONT_URL:'',DRIVE_ACK:evidence,PASS_1:x.decision.pass?'STRICT_BASE_PASS':'FAIL',
    PASS_2:status==='STRICT_PASS_X2_PROMOTED'?'X2_PASS':'PENDING',LAST_GOOD:status==='STRICT_PASS_X2_PROMOTED'?resultId:'',STATUS:status,ROOT_CAUSE:hard,
    MIN_FIX:x.fix||'',NEXT_RESUME_POINT:status==='STRICT_PASS_X2_PROMOTED'?'NEXT_JOB_REUSE_SMOKE':'MIN_FIX→SAME_JOB_LINEAGE→RETEST→X2',UPDATED_AT:now
  });
}

function writeCentralMediaCycleReadbackV1_(summary) {
  try {
    appendCentralMediaByHeaderV1_('80_DATA_RUNTIME_QA_LOG',{
      QA_ID:'QA-MEDIA-CYCLE-'+Utilities.formatDate(new Date(),CENTRAL_MEDIA_TZ,'yyyyMMdd-HHmmss'),RUN_ID:'CENTRAL_MEDIA_LOGICAL_WAKE',APP_ID:'CENTRAL_AGENT',FUNCTION_ID:'runCentralMediaQaSeedLoop',
      TRIGGER_ID:'TRG_CENTRAL_MEDIA_QA_10M_LOGICAL',STARTED_AT:new Date(),FINISHED_AT:new Date(),STATUS:'PASS_CYCLE',READBACK_STATE:'PASS',QUALITY_SCORE:'',ERROR_CLASS:'',RETRY_COUNT:0,
      EVIDENCE_POINTER:JSON.stringify(summary).slice(0,4000),NEXT_ACTION:'CONTINUE_EXISTING_WAKE;NO_DUPLICATE_TRIGGER'
    });
  } catch(e) {}
}

function centralMediaSheetHasValueV1_(sheetName, headerName, value) {
  const ss=SpreadsheetApp.openById(CENTRAL_MEDIA_MASTER_REGISTRY_ID); const sh=ss.getSheetByName(sheetName); if(!sh)return false;
  const data=sh.getDataRange().getValues(); if(data.length<2)return false; const headers=data[0]; const idx=headers.indexOf(headerName); if(idx<0)return false;
  for(let i=1;i<data.length;i++) if(String(data[i][idx]||'')===String(value)) return true; return false;
}

function appendCentralMediaByHeaderV1_(sheetName,payload) {
  if (typeof appendByHeader_ === 'function') return appendByHeader_(sheetName,payload);
  const ss=SpreadsheetApp.openById(CENTRAL_MEDIA_MASTER_REGISTRY_ID); const sh=ss.getSheetByName(sheetName); if(!sh)throw new Error('SHEET_NOT_FOUND:'+sheetName);
  const width=sh.getLastColumn(); const headers=sh.getRange(1,1,1,width).getValues()[0]; const row=headers.map(function(h){return Object.prototype.hasOwnProperty.call(payload,h)?payload[h]:'';});
  sh.appendRow(row); return sh.getLastRow();
}

function shortCentralMediaHashV1_(s) { return hashCentralMediaTextV1_(s).slice(0,12).toUpperCase(); }

function testCentralMediaQaSeedLoopV1() {
  const base={mediaType:'IMAGE',originalPrompt:'Create a full-body interior persona in a bright kitchen',promptVersion:'1',requirementId:'REQ_FIXTURE',expectedConstraints:{fullBody:true,kitchen:true},fileReadbackOk:true,fileSize:2048,resultHash:'abc123',lineagePct:100,qa:{criticalConstraintsPct:100,promptFidelity:95,purposeFit:94,mediaSpecific:93,continuity:null,hardFails:[]},tabletRequired:false,screenOffContinuity:true,userSatisfactionPct:null,hardFails:[]};
  const pass=evaluateCentralMediaGateV1(base); if(!pass.pass)throw new Error('BASE_PASS_FAILED:'+JSON.stringify(pass));
  const missing=JSON.parse(JSON.stringify(base)); missing.originalPrompt=''; const r1=evaluateCentralMediaGateV1(missing); if(r1.pass||r1.hardFails.indexOf('ORIGINAL_PROMPT_MISSING')<0)throw new Error('MISSING_PROMPT_GATE_FAIL');
  const lowPrompt=JSON.parse(JSON.stringify(base)); lowPrompt.qa.promptFidelity=89; const r2=evaluateCentralMediaGateV1(lowPrompt); if(r2.pass||r2.hardFails.indexOf('PROMPT_FIDELITY_BELOW_90')<0)throw new Error('PROMPT_89_GATE_FAIL');
  const lowCritical=JSON.parse(JSON.stringify(base)); lowCritical.qa.criticalConstraintsPct=99; const r3=evaluateCentralMediaGateV1(lowCritical); if(r3.pass||r3.hardFails.indexOf('CRITICAL_CONSTRAINT_MISS')<0)throw new Error('CRITICAL_99_GATE_FAIL');
  const tablet=JSON.parse(JSON.stringify(base)); tablet.tabletRequired=true; tablet.screenOffContinuity=false; const r4=evaluateCentralMediaGateV1(tablet); if(r4.pass||r4.hardFails.indexOf('TABLET_SCREEN_OFF_CONTINUITY_FAIL')<0)throw new Error('TABLET_SCREEN_OFF_GATE_FAIL');
  const video=JSON.parse(JSON.stringify(base)); video.mediaType='VIDEO'; video.qa.continuity=89; const r5=evaluateCentralMediaGateV1(video); if(r5.pass||r5.hardFails.indexOf('VIDEO_CONTINUITY_BELOW_90')<0)throw new Error('VIDEO_CONTINUITY_GATE_FAIL');
  return {ok:true,basePass:pass,missingPrompt:r1,lowPrompt:r2,lowCritical:r3,tabletScreenOff:r4,videoContinuity:r5,promotionRule:'X1=CANDIDATE;DISTINCT_RESULT_HASH_X2=PROMOTE'};
}
