const DRIVE_AUTO_CLASSIFY_MASTER_ID = '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI';
const DRIVE_AUTO_CLASSIFY_ROOT_NAME = '00_중앙에이전트';
const DRIVE_AUTO_CLASSIFY_TZ = 'Asia/Seoul';
const DRIVE_AUTO_CLASSIFY_VERSION = 'DRIVE_AUTO_CLASSIFY_SEED_WRITEBACK_V1_20260831';
const DRIVE_AUTO_CLASSIFY_BUCKET_MS = 10 * 60 * 1000;

/**
 * Logical 10-minute Drive ingestion/classification handler.
 *
 * IMPORTANT:
 * - Reuse the already-verified physical processTaskQueue/factory wake.
 * - DO NOT create another physical Apps Script time trigger.
 * - Promotion is fail-closed: a new/changed Drive file becomes an inventory +
 *   Queens candidate first. Seed/Template promotion remains behind existing QA.
 *
 * Intended bound-script hook (after the existing queue cycle succeeds):
 *   runDriveAutoClassifySeedWriteback10m({source:'processTaskQueue'});
 */
function runDriveAutoClassifySeedWriteback10m(context) {
  context = context || {};
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) return {ok:true, skipped:'LOCKED', version:DRIVE_AUTO_CLASSIFY_VERSION};

  try {
    const now = context.now instanceof Date ? context.now : new Date();
    const props = PropertiesService.getScriptProperties();
    const bucket = driveAutoClassifyBucket10mV1_(now.getTime());
    const lastBucket = String(props.getProperty('DRIVE_AUTO_CLASSIFY_LAST_10M_BUCKET') || '');
    const force = context.force === true;

    if (!force && lastBucket === String(bucket)) {
      return {ok:true, skipped:'IDEMPOTENT_10M_BUCKET', bucket:bucket, version:DRIVE_AUTO_CLASSIFY_VERSION};
    }

    const sinceIso = String(
      context.sinceIso ||
      props.getProperty('DRIVE_AUTO_CLASSIFY_LAST_SCAN_AT') ||
      new Date(now.getTime() - 20 * 60 * 1000).toISOString()
    );
    const maxFiles = Math.max(1, Math.min(50, Number(context.maxFiles || props.getProperty('DRIVE_AUTO_CLASSIFY_MAX_FILES') || 20)));
    const root = driveAutoClassifyResolveRootV1_(props);
    const files = [];
    driveAutoClassifyCollectRecentV1_(root, new Date(sinceIso), 0, 4, maxFiles, files);
    files.sort(function(a,b){ return b.updatedAt.getTime() - a.updatedAt.getTime(); });

    const results = [];
    files.slice(0, maxFiles).forEach(function(meta){
      try {
        results.push(driveAutoClassifyOneV1_(meta, now, context));
      } catch (e) {
        const fail = {ok:false,fileId:meta.fileId,error:String(e && e.message || e),status:'CLASSIFY_HANDLER_ERROR'};
        results.push(fail);
        driveAutoClassifyRuntimeWriteV1_({
          qaId:'QA_DRIVE_AUTO_'+driveAutoClassifyShortIdV1_(meta.fileId)+'_'+Utilities.formatDate(now,DRIVE_AUTO_CLASSIFY_TZ,'yyyyMMdd_HHmmss'),
          fileId:meta.fileId,
          appId:'CENTRAL_AGENT',
          status:'CLASSIFY_HANDLER_ERROR',
          readback:'FILE_METADATA_READ_FAIL_OR_WRITEBACK_ERROR',
          error:fail.error,
          evidence:meta.url,
          next:'PRESERVE_ORIGINAL_AND_RETRY_FAILED_DIMENSION_ONLY'
        }, now);
      }
    });

    // Media strict QA already exists as a separate reusable logical handler.
    // Invoke only when present in the same bound project; otherwise leave the
    // candidates fail-closed for the next verified media QA cycle.
    let mediaQa = {invoked:false,reason:'HANDLER_NOT_BOUND'};
    if (typeof runCentralMediaQaSeedLoop === 'function' && context.skipMediaQa !== true) {
      try {
        mediaQa = runCentralMediaQaSeedLoop({
          files: files.filter(function(f){ return /^(IMAGE|VIDEO)$/.test(driveAutoClassifyTypeV1_(f)); }),
          source:'runDriveAutoClassifySeedWriteback10m'
        });
        mediaQa.invoked = true;
      } catch (e) {
        mediaQa = {invoked:true,ok:false,error:String(e && e.message || e)};
      }
    }

    props.setProperty('DRIVE_AUTO_CLASSIFY_LAST_10M_BUCKET', String(bucket));
    props.setProperty('DRIVE_AUTO_CLASSIFY_LAST_SCAN_AT', now.toISOString());

    const summary = {
      ok:true,
      version:DRIVE_AUTO_CLASSIFY_VERSION,
      source:String(context.source || 'logical_10m'),
      bucket:bucket,
      scanned:files.length,
      inventoried:results.filter(function(x){return x.inventoryCreated;}).length,
      alreadyKnown:results.filter(function(x){return x.status==='ALREADY_INVENTORIED';}).length,
      queensCandidates:results.filter(function(x){return x.queensCreated;}).length,
      failures:results.filter(function(x){return x.ok===false;}).length,
      mediaQa:mediaQa,
      at:now.toISOString()
    };
    driveAutoClassifyCycleReadbackV1_(summary, now);
    return summary;
  } finally {
    lock.releaseLock();
  }
}

/** Pure helper used by CI. */
function driveAutoClassifyBucket10mV1_(epochMs) {
  return Math.floor(Number(epochMs || 0) / DRIVE_AUTO_CLASSIFY_BUCKET_MS);
}

/** Hook helper for the existing 5-minute factory wake. No trigger creation. */
function runDriveAutoClassifySeedWriteback10mFromFactoryV1() {
  return runDriveAutoClassifySeedWriteback10m({source:'processTaskQueue'});
}

function driveAutoClassifyResolveRootV1_(props) {
  const rootId = String(props.getProperty('CENTRAL_ROOT_FOLDER_ID') || '');
  if (rootId) {
    try { return DriveApp.getFolderById(rootId); } catch (_e) {}
  }
  const it = DriveApp.getFoldersByName(DRIVE_AUTO_CLASSIFY_ROOT_NAME);
  if (!it.hasNext()) throw new Error('CENTRAL_ROOT_FOLDER_NOT_FOUND');
  return it.next();
}

function driveAutoClassifyCollectRecentV1_(folder, since, depth, maxDepth, maxFiles, out) {
  if (out.length >= maxFiles) return;
  const files = folder.getFiles();
  while (files.hasNext() && out.length < maxFiles) {
    const f = files.next();
    const updatedAt = f.getLastUpdated();
    if (updatedAt <= since) continue;
    const size = driveAutoClassifySafeSizeV1_(f);
    if (size <= 0) continue;
    out.push({
      fileId:f.getId(),
      name:f.getName(),
      mimeType:String(f.getMimeType() || ''),
      size:size,
      url:f.getUrl(),
      parentId:folder.getId(),
      parentName:folder.getName(),
      createdAt:f.getDateCreated(),
      updatedAt:updatedAt
    });
  }
  if (depth >= maxDepth || out.length >= maxFiles) return;
  const folders = folder.getFolders();
  while (folders.hasNext() && out.length < maxFiles) {
    driveAutoClassifyCollectRecentV1_(folders.next(), since, depth + 1, maxDepth, maxFiles, out);
  }
}

function driveAutoClassifySafeSizeV1_(file) {
  try { return Number(file.getSize() || 0); } catch (_e) { return 0; }
}

function driveAutoClassifyOneV1_(meta, now, context) {
  const type = driveAutoClassifyTypeV1_(meta);
  const appId = driveAutoClassifyAppV1_(meta, context);
  const sourceHash = driveAutoClassifyHashV1_(meta.fileId+'|'+meta.size+'|'+meta.updatedAt.toISOString());
  const inventoryId = 'DRIVE_'+driveAutoClassifyShortIdV1_(meta.fileId);
  const qresId = 'QRES_DRIVE_'+sourceHash.slice(0,12).toUpperCase();

  const existingInventory = driveAutoClassifyFindByHeaderV1_('23_FILE_ASSET_INVENTORY','SOURCE_ID',meta.fileId);
  if (existingInventory) {
    driveAutoClassifyRuntimeWriteV1_({
      qaId:'QA_DRIVE_AUTO_'+sourceHash.slice(0,12), fileId:meta.fileId, appId:appId,
      status:'ALREADY_INVENTORIED', readback:'SOURCE_ID_DEDUP_PASS', error:'',
      evidence:meta.url+'|'+existingInventory, next:'NO_DUPLICATE_WRITE'
    }, now);
    return {ok:true,fileId:meta.fileId,status:'ALREADY_INVENTORIED',inventoryCreated:false,queensCreated:false,type:type};
  }

  driveAutoClassifyAppendV1_('23_FILE_ASSET_INVENTORY', {
    ASSET_ID:inventoryId,
    PROJECT_ID:appId,
    ASSET_TYPE:type,
    TITLE:meta.name,
    SOURCE_SYSTEM:'GOOGLE_DRIVE_AUTO_INGEST',
    SOURCE_ID:meta.fileId,
    SOURCE_URL:meta.url,
    GITHUB_REPO:'',
    BRANCH:'',
    PARENT_OR_FOLDER:meta.parentId+'|'+meta.parentName,
    VERSION_OR_SHA:sourceHash,
    INVENTORY_STATUS:'AUTO_CLASSIFIED_QUEENS_CANDIDATE',
    TEST_STATUS:'DRIVE_METADATA_READBACK_PASS',
    LAST_VERIFIED_AT:now,
    CONTROL_RULE:'FILE_ID+SIZE+UPDATED_AT_DEDUP;RAW_PRESERVE;NO_AUTO_SEED_PROMOTION',
    NOTES:'MIME='+meta.mimeType+';SIZE='+meta.size+';VERSION='+DRIVE_AUTO_CLASSIFY_VERSION
  });

  let queensCreated = false;
  if (!driveAutoClassifyFindByHeaderV1_('37_QUEENS_RESEARCH_RESULTS','RESULT_ID',qresId)) {
    driveAutoClassifyAppendV1_('37_QUEENS_RESEARCH_RESULTS', {
      RESULT_ID:qresId,
      QUEENS_TASK_ID:'Q_DRIVE_AUTO_CLASSIFY_SEED',
      APP_ID:appId,
      RESEARCH_TYPE:'DRIVE_FILE_INGEST',
      QUERY:meta.name,
      SOURCE_PROVIDER:'GOOGLE_DRIVE_CANONICAL_ORIGINAL',
      SOURCE_TITLE:meta.name,
      SOURCE_URL:meta.url,
      SOURCE_PUBLISHED_AT:meta.createdAt,
      COLLECTED_AT:now,
      MARKET_ID:'INTERNAL',
      LOCALE_ID:'ko-KR',
      EVIDENCE_STATUS:'DRIVE_METADATA_READBACK_VERIFIED',
      SEED_STATUS:'CANDIDATE_REVIEW_REQUIRED',
      SOURCE_HASH:sourceHash,
      NOTES:'FILE_ID='+meta.fileId+';MIME='+meta.mimeType+';SIZE='+meta.size+';ASSET_TYPE='+type+';NO_AUTO_PROMOTION'
    });
    queensCreated = true;
  }

  driveAutoClassifyRuntimeWriteV1_({
    qaId:'QA_DRIVE_AUTO_'+sourceHash.slice(0,12), fileId:meta.fileId, appId:appId,
    status:'AUTO_CLASSIFIED_QUEENS_CANDIDATE', readback:'FILE_ID+MIME+SIZE+PARENT_PASS', error:'',
    evidence:meta.url+'|'+inventoryId+'|'+qresId,
    next:/^(IMAGE|VIDEO)$/.test(type)?'STRICT_MEDIA_QA_X2':'DOMAIN_QA_THEN_SEED_PROMOTION'
  }, now);

  return {ok:true,fileId:meta.fileId,status:'AUTO_CLASSIFIED_QUEENS_CANDIDATE',inventoryCreated:true,queensCreated:queensCreated,type:type,inventoryId:inventoryId,qresId:qresId};
}

/** Pure-ish deterministic classifier (no Apps Script services). */
function driveAutoClassifyTypeV1_(meta) {
  const mime = String((meta||{}).mimeType || '').toLowerCase();
  const name = String((meta||{}).name || '').toLowerCase();
  if (/^image\//.test(mime) || /\.(png|jpe?g|webp|gif|heic)$/.test(name)) return 'IMAGE';
  if (/^video\//.test(mime) || /\.(mp4|mov|webm|mkv)$/.test(name)) return 'VIDEO';
  if (/^audio\//.test(mime) || /\.(m4a|mp3|wav|aac|ogg)$/.test(name)) return 'AUDIO';
  if (mime === 'application/pdf' || /\.pdf$/.test(name)) return 'PDF';
  if (/spreadsheet|excel/.test(mime) || /\.(xlsx?|csv)$/.test(name)) return 'SHEET';
  if (/presentation|powerpoint/.test(mime) || /\.(pptx?)$/.test(name)) return 'SLIDE';
  if (/document|word/.test(mime) || /\.(docx?)$/.test(name)) return 'DOC';
  if (/json/.test(mime) || /\.json$/.test(name)) return 'JSON';
  if (/text\//.test(mime) || /\.(txt|md|html?)$/.test(name)) return 'TEXT';
  if (/zip|archive/.test(mime) || /\.(zip|7z|rar)$/.test(name)) return 'ARCHIVE';
  return 'OTHER';
}

function driveAutoClassifyAppV1_(meta, context) {
  if (context && context.appId) return String(context.appId);
  const hay = (String(meta.parentName||'')+' '+String(meta.name||'')).toLowerCase();
  if (/notebooklm|notebook/.test(hay)) return 'APP_NOTEBOOKLM_BRIDGE';
  if (/interior|인테리어/.test(hay)) return 'APP_INTERIOR';
  if (/travel|여행/.test(hay)) return 'APP_TRAVEL';
  if (/drywrite|건조/.test(hay)) return 'APP_DRYWRITE';
  if (/vtube|v-tube|animation|영상/.test(hay)) return 'APP_VTUBE_1011B';
  return 'CENTRAL_AGENT';
}

function driveAutoClassifyFindByHeaderV1_(sheetName, headerName, value) {
  const ss = SpreadsheetApp.openById(DRIVE_AUTO_CLASSIFY_MASTER_ID);
  const sh = ss.getSheetByName(sheetName);
  if (!sh || sh.getLastRow() < 2) return '';
  const width = sh.getLastColumn();
  const headers = sh.getRange(1,1,1,width).getValues()[0].map(String);
  const index = headers.indexOf(headerName);
  if (index < 0) throw new Error('HEADER_NOT_FOUND:'+sheetName+':'+headerName);
  const finder = sh.getRange(2,index+1,sh.getLastRow()-1,1).createTextFinder(String(value)).matchEntireCell(true).findNext();
  return finder ? sheetName+'!'+finder.getA1Notation() : '';
}

function driveAutoClassifyAppendV1_(sheetName, payload) {
  const ss = SpreadsheetApp.openById(DRIVE_AUTO_CLASSIFY_MASTER_ID);
  const sh = ss.getSheetByName(sheetName);
  if (!sh) throw new Error('SHEET_NOT_FOUND:'+sheetName);
  const width = sh.getLastColumn();
  const headers = sh.getRange(1,1,1,width).getValues()[0].map(String);
  const row = headers.map(function(h){return Object.prototype.hasOwnProperty.call(payload,h) ? payload[h] : '';});
  sh.appendRow(row);
  return sh.getLastRow();
}

function driveAutoClassifyRuntimeWriteV1_(evidence, now) {
  driveAutoClassifyAppendV1_('80_DATA_RUNTIME_QA_LOG', {
    QA_ID:evidence.qaId,
    RUN_ID:'RUN_DRIVE_AUTO_CLASSIFY_10M_'+Utilities.formatDate(now,DRIVE_AUTO_CLASSIFY_TZ,'yyyyMMdd_HHmm'),
    APP_ID:evidence.appId,
    FUNCTION_ID:'runDriveAutoClassifySeedWriteback10m',
    TRIGGER_ID:'TRG_DRIVE_AUTO_CLASSIFY_SEED_REUSE_20260831',
    INPUT_DATA_IDS:evidence.fileId,
    OUTPUT_DATA_IDS:evidence.evidence,
    RESULT_ID:evidence.fileId,
    STARTED_AT:now,
    FINISHED_AT:now,
    STATUS:evidence.status,
    READBACK_STATE:evidence.readback,
    QUALITY_SCORE:evidence.status==='CLASSIFY_HANDLER_ERROR'?0:100,
    ERROR_CLASS:evidence.error,
    RETRY_COUNT:0,
    EVIDENCE_POINTER:evidence.evidence,
    NEXT_ACTION:evidence.next
  });
}

function driveAutoClassifyCycleReadbackV1_(summary, now) {
  driveAutoClassifyRuntimeWriteV1_({
    qaId:'QA_DRIVE_AUTO_CYCLE_'+Utilities.formatDate(now,DRIVE_AUTO_CLASSIFY_TZ,'yyyyMMdd_HHmm'),
    fileId:'CYCLE_BUCKET_'+summary.bucket,
    appId:'CENTRAL_AGENT;ALL_PROJECTS;NOTEBOOKLM;MEDIA;ALL_FRONT_APPS',
    status:summary.failures ? 'PARTIAL_FAIL' : 'LOGICAL_10M_CYCLE_PASS',
    readback:'BUCKET='+summary.bucket+';SCANNED='+summary.scanned+';INVENTORIED='+summary.inventoried+';QUEENS='+summary.queensCandidates,
    error:summary.failures ? 'PER_FILE_FAILURE_PRESENT' : '',
    evidence:JSON.stringify({version:summary.version,source:summary.source,mediaQa:summary.mediaQa}),
    next:summary.failures?'FAILED_DIMENSION_ONLY_REPAIR':'WAIT_NEXT_10M_BUCKET'
  }, now);
}

function driveAutoClassifyHashV1_(text) {
  const bytes = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, String(text), Utilities.Charset.UTF_8);
  return bytes.map(function(b){const v=(b+256)%256;return ('0'+v.toString(16)).slice(-2);}).join('');
}

function driveAutoClassifyShortIdV1_(text) {
  return String(text || '').replace(/[^A-Za-z0-9]/g,'').slice(-16) || 'UNKNOWN';
}
