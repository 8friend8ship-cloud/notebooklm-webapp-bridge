/**
 * Queens 조사자료 → 프런트앱 즉시 응답 라이브러리
 * 원본을 직접 수정하지 않고 01_MASTER_REGISTRY를 중앙 색인으로 사용한다.
 *
 * 설치:
 * 1) 기존 중앙 Apps Script 프로젝트에 이 파일 추가
 * 2) setupQueensFrontResponse() 1회 실행
 * 3) 기존 doGet(e) 첫 부분에 아래 2줄 추가
 *    var queensResponse = handleFrontResponseAction_(e);
 *    if (queensResponse) return queensResponse;
 */

var QUEENS_FRONT_RESPONSE = (function () {
  var TZ = 'Asia/Seoul';
  var MASTER_ID = '1C_CznU1Uo7dk-gKay3-oH8wFxutsGMlz27RSrbdVQwI';
  var SHEETS = {
    SOURCES: '10_QUEENS_SOURCE_REGISTRY',
    LIBRARY: '11_FRONT_RESPONSE_LIBRARY',
    APP_MAP: '12_APP_RESPONSE_MAP',
    CALL_LOG: '13_FRONT_CALL_LOG',
    RESEARCH_QUEUE: '14_QUEENS_RESEARCH_QUEUE',
    EXECUTION_QUEUE: '07_EXECUTION_QUEUE'
  };

  var HEADERS = {};
  HEADERS[SHEETS.SOURCES] = ['SOURCE_CODE','APP_ID','SPREADSHEET_NAME','SPREADSHEET_ID','SOURCE_TAB','DETAIL_TAB','OUTPUT_TAB','SOURCE_TYPE','ACTIVE_YN','REFRESH_HOURS','ACCEPT_STATUS','LAST_REFRESH_AT','STATUS','NOTES'];
  HEADERS[SHEETS.LIBRARY] = ['RESPONSE_ID','APP_ID','CONTENT_ID','SOURCE_CODE','SOURCE_ROW_ID','INTENT','QUESTION_PATTERN','ANSWER_SHORT','ANSWER_DETAIL','KEY_FACTS_JSON','ACTIONS_JSON','SOURCE_LABELS','SOURCE_LINKS','LOCALE_ID','MARKET_ID','VALID_FROM','EXPIRES_AT','STATUS','QA_STATUS','UPDATED_AT'];
  HEADERS[SHEETS.APP_MAP] = ['APP_ID','APP_NAME','DOMAIN','ALLOWED_INTENTS','RESPONSE_SOURCE','SOURCE_CODES','DEFAULT_LOCALE','DEFAULT_MARKET','MAX_AGE_HOURS','LIVE_QUEENS_YN','FALLBACK_POLICY','FRONT_ROUTE','STATUS','UPDATED_AT'];
  HEADERS[SHEETS.CALL_LOG] = ['CALL_ID','CALLED_AT','APP_ID','SESSION_ID','QUERY','INTENT','MATCH_RESPONSE_ID','MATCH_SCORE','SOURCE_CODE','RESPONSE_STATUS','LATENCY_MS','FEEDBACK','ERROR','UPDATED_AT'];
  HEADERS[SHEETS.RESEARCH_QUEUE] = ['QUEENS_TASK_ID','APP_ID','RESEARCH_TYPE','QUERY','MARKET_ID','LOCALE_ID','PERIOD','LIMIT','SOURCE_PROVIDER','PRIORITY','STATUS','NEXT_RUN_AT','LAST_RUN_AT','RESULT_COUNT','ERROR','UPDATED_AT'];

  function now_() { return Utilities.formatDate(new Date(), TZ, 'yyyy-MM-dd HH:mm:ss'); }
  function master_() { return SpreadsheetApp.openById(PropertiesService.getScriptProperties().getProperty('MASTER_REGISTRY_ID') || MASTER_ID); }

  function ensureSheet_(name) {
    var ss = master_();
    var sh = ss.getSheetByName(name) || ss.insertSheet(name);
    var headers = HEADERS[name] || [];
    if (headers.length) {
      var existing = sh.getLastColumn() ? sh.getRange(1, 1, 1, Math.max(sh.getLastColumn(), headers.length)).getDisplayValues()[0] : [];
      var mismatch = headers.some(function (h, i) { return existing[i] !== h; });
      if (mismatch) sh.getRange(1, 1, 1, headers.length).setValues([headers]);
      sh.setFrozenRows(1);
    }
    return sh;
  }

  function readObjects_(sheet) {
    if (!sheet || sheet.getLastRow() < 2 || sheet.getLastColumn() < 1) return [];
    var values = sheet.getDataRange().getValues();
    var headers = values.shift().map(function (v) { return String(v || '').trim(); });
    return values.map(function (row, index) {
      var out = { _row: index + 2 };
      headers.forEach(function (h, i) { if (h) out[h] = row[i]; });
      return out;
    }).filter(function (r) {
      return Object.keys(r).some(function (k) { return k !== '_row' && String(r[k] || '').trim(); });
    });
  }

  function appendObject_(sheet, object, headers) {
    var row = headers.map(function (h) { return object[h] == null ? '' : object[h]; });
    sheet.getRange(sheet.getLastRow() + 1, 1, 1, row.length).setValues([row]);
  }

  function upsertObject_(sheet, key, value, object, headers) {
    var rows = readObjects_(sheet);
    var found = rows.filter(function (r) { return String(r[key] || '') === String(value || ''); })[0];
    var rowValues = headers.map(function (h) { return object[h] == null ? '' : object[h]; });
    if (found) sheet.getRange(found._row, 1, 1, rowValues.length).setValues([rowValues]);
    else sheet.getRange(sheet.getLastRow() + 1, 1, 1, rowValues.length).setValues([rowValues]);
  }

  function first_(row, keys) {
    for (var i = 0; i < keys.length; i++) {
      var value = row[keys[i]];
      if (value !== null && value !== undefined && String(value).trim()) return String(value).trim();
    }
    return '';
  }

  function accepted_(row, accepted) {
    var allowed = String(accepted || '').toUpperCase().split('|').filter(Boolean);
    if (!allowed.length) return true;
    var status = first_(row, ['STATUS','QA_STATUS','PUBLISH_STATUS','STATE']).toUpperCase();
    return allowed.indexOf(status) >= 0;
  }

  function safeJson_(value) {
    try { return JSON.stringify(value || {}); } catch (e) { return '{}'; }
  }

  function rowId_(row) {
    return first_(row, ['CONTENT_ID','CORE_ID','DB_MAP_ID','SOURCE_ID','MAIL_ID','PROGRAM_ID','VIDEO_ID','TASK_ID','ID']) || ('ROW_' + row._row);
  }

  function inferIntent_(row, sourceType) {
    var direct = first_(row, ['INTENT','CATEGORY','DOMAIN','PROJECT_SCOPE','CORE_TOPIC','RESEARCH_TYPE']);
    if (direct) return direct.toLowerCase().replace(/\s+/g, '_');
    return String(sourceType || 'general').toLowerCase();
  }

  function normalizeRow_(source, row) {
    var sourceRowId = rowId_(row);
    var title = first_(row, ['QUESTION_PATTERN','QUESTION','TITLE','SUBJECT','PROGRAM_NAME','지원사업명','CORE_TOPIC','KEYWORD','QUERY']);
    var shortAnswer = first_(row, ['ANSWER_SHORT','SUMMARY','DESCRIPTION','EXTRACTED_THEME','MESSAGE','AGENT_ACTION','NEXT_ACTION','CORE_TOPIC','TITLE','SUBJECT']);
    var detailAnswer = first_(row, ['ANSWER_DETAIL','MASTER_TEXT','BODY','CONTENT','TEXT_FULL','PUBLIC_TEXT','SUMMARY','DESCRIPTION','MESSAGE']);
    if (!detailAnswer) detailAnswer = shortAnswer;
    if (!shortAnswer && detailAnswer) shortAnswer = detailAnswer.slice(0, 240);
    if (!title) title = [shortAnswer, first_(row, ['KEYWORDS','EMOTION_KEYWORDS','MAIN_CONFLICT'])].filter(Boolean).join(' ');
    if (!shortAnswer && !detailAnswer) return null;

    var contentId = first_(row, ['CONTENT_ID','CORE_ID','DB_MAP_ID','SOURCE_ID','MAIL_ID','PROGRAM_ID','VIDEO_ID']) || sourceRowId;
    var facts = {
      title: first_(row, ['TITLE','SUBJECT','PROGRAM_NAME','지원사업명']),
      deadline: first_(row, ['DEADLINE','마감일','DUE_AT']),
      cost: first_(row, ['TOTAL_PRICE','PRICE','COST','예상비용']),
      status: first_(row, ['STATUS','STATE','PUBLISH_STATUS']),
      category: first_(row, ['CATEGORY','DOMAIN','PROJECT_SCOPE']),
      updatedAt: first_(row, ['UPDATED_AT','CREATED_AT','RECEIVED_AT'])
    };
    var actions = {
      next: first_(row, ['NEXT_ACTION','AGENT_ACTION','CTA','REQUEST']),
      resultLink: first_(row, ['RESULT_LINK','DRIVE_LINKS','DRIVE_URL','PUBLIC_URL'])
    };
    var links = [first_(row, ['SOURCE_URL','URL','VIDEO_URL','공고/원문 링크']), first_(row, ['DRIVE_LINKS','DRIVE_URL','RESULT_LINK','PUBLIC_URL'])].filter(Boolean).join('\n');
    var responseId = 'RESP_' + Utilities.base64EncodeWebSafe(source.SOURCE_CODE + '|' + sourceRowId).replace(/=+$/,'').slice(0, 48);

    return {
      RESPONSE_ID: responseId,
      APP_ID: source.APP_ID || 'AGENT_CONSOLE',
      CONTENT_ID: contentId,
      SOURCE_CODE: source.SOURCE_CODE,
      SOURCE_ROW_ID: sourceRowId,
      INTENT: inferIntent_(row, source.SOURCE_TYPE),
      QUESTION_PATTERN: title,
      ANSWER_SHORT: shortAnswer.slice(0, 500),
      ANSWER_DETAIL: detailAnswer.slice(0, 12000),
      KEY_FACTS_JSON: safeJson_(facts),
      ACTIONS_JSON: safeJson_(actions),
      SOURCE_LABELS: source.SPREADSHEET_NAME + '/' + (source.OUTPUT_TAB || source.SOURCE_TAB),
      SOURCE_LINKS: links,
      LOCALE_ID: first_(row, ['LOCALE_ID','LOCALE']) || 'ko-KR',
      MARKET_ID: first_(row, ['MARKET_ID','MARKET']) || 'KR',
      VALID_FROM: first_(row, ['VALID_FROM','CREATED_AT','RECEIVED_AT']) || now_(),
      EXPIRES_AT: first_(row, ['EXPIRES_AT','DEADLINE','마감일']),
      STATUS: 'READY',
      QA_STATUS: 'SOURCE_STATUS_VERIFIED',
      UPDATED_AT: now_()
    };
  }

  function chooseSourceSheet_(source) {
    var ss = SpreadsheetApp.openById(String(source.SPREADSHEET_ID || '').trim());
    return ss.getSheetByName(String(source.OUTPUT_TAB || '').trim()) ||
      ss.getSheetByName(String(source.DETAIL_TAB || '').trim()) ||
      ss.getSheetByName(String(source.SOURCE_TAB || '').trim());
  }

  function refreshAll_() {
    var lock = LockService.getScriptLock();
    if (!lock.tryLock(10000)) return { ok: false, status: 'LOCKED' };
    try {
      Object.keys(HEADERS).forEach(ensureSheet_);
      var sourceSheet = ensureSheet_(SHEETS.SOURCES);
      var librarySheet = ensureSheet_(SHEETS.LIBRARY);
      var sources = readObjects_(sourceSheet).filter(function (s) {
        return String(s.ACTIVE_YN || '').toUpperCase() === 'Y' && String(s.SPREADSHEET_ID || '').trim();
      });
      var created = 0, skipped = 0, errors = [];

      sources.forEach(function (source) {
        try {
          var sh = chooseSourceSheet_(source);
          if (!sh) throw new Error('SOURCE_TAB_NOT_FOUND');
          readObjects_(sh).forEach(function (row) {
            if (!accepted_(row, source.ACCEPT_STATUS)) { skipped++; return; }
            var normalized = normalizeRow_(source, row);
            if (!normalized) { skipped++; return; }
            upsertObject_(librarySheet, 'RESPONSE_ID', normalized.RESPONSE_ID, normalized, HEADERS[SHEETS.LIBRARY]);
            created++;
          });
          source.LAST_REFRESH_AT = now_();
          source.STATUS = 'REFRESHED';
          upsertObject_(sourceSheet, 'SOURCE_CODE', source.SOURCE_CODE, source, HEADERS[SHEETS.SOURCES]);
        } catch (error) {
          source.STATUS = 'ERROR';
          source.NOTES = String(error && error.message || error);
          upsertObject_(sourceSheet, 'SOURCE_CODE', source.SOURCE_CODE, source, HEADERS[SHEETS.SOURCES]);
          errors.push({ source: source.SOURCE_CODE, error: source.NOTES });
        }
      });
      return { ok: true, refreshed: created, skipped: skipped, errors: errors };
    } finally {
      lock.releaseLock();
    }
  }

  function tokens_(text) {
    return String(text || '').toLowerCase().replace(/[^0-9a-zA-Z가-힣_\s]/g, ' ').split(/\s+/).filter(function (t) { return t.length >= 2; });
  }

  function score_(queryTokens, row, requestedIntent) {
    var hay = tokens_([row.QUESTION_PATTERN,row.ANSWER_SHORT,row.ANSWER_DETAIL,row.INTENT,row.KEY_FACTS_JSON].join(' '));
    var set = {};
    hay.forEach(function (t) { set[t] = true; });
    var score = 0;
    queryTokens.forEach(function (t) { if (set[t]) score += 4; });
    if (requestedIntent && String(row.INTENT || '') === requestedIntent) score += 12;
    if (String(row.QA_STATUS || '').indexOf('VERIFIED') >= 0) score += 3;
    return score;
  }

  function queueUnanswered_(appId, query, intent, locale, market) {
    var sheet = ensureSheet_(SHEETS.RESEARCH_QUEUE);
    var rows = readObjects_(sheet);
    var duplicate = rows.some(function (r) {
      return String(r.APP_ID) === appId && String(r.QUERY).toLowerCase() === query.toLowerCase() && ['READY','CLAIMED','QUEUED_TO_PROVIDER'].indexOf(String(r.STATUS)) >= 0;
    });
    if (duplicate) return '';
    var id = 'Q_AUTO_' + Utilities.getUuid().slice(0, 12).toUpperCase();
    appendObject_(sheet, {
      QUEENS_TASK_ID: id,
      APP_ID: appId,
      RESEARCH_TYPE: intent || 'UNANSWERED_FRONT_QUERY',
      QUERY: query,
      MARKET_ID: market || 'KR',
      LOCALE_ID: locale || 'ko-KR',
      PERIOD: '30d',
      LIMIT: 30,
      SOURCE_PROVIDER: 'QUEENS',
      PRIORITY: 'P1',
      STATUS: 'READY',
      NEXT_RUN_AT: '',
      LAST_RUN_AT: '',
      RESULT_COUNT: 0,
      ERROR: '',
      UPDATED_AT: now_()
    }, HEADERS[SHEETS.RESEARCH_QUEUE]);
    return id;
  }

  function answer_(params) {
    var started = new Date().getTime();
    var appId = String(params.appId || params.app_id || '').trim();
    var query = String(params.query || params.q || '').trim();
    var intent = String(params.intent || '').trim().toLowerCase();
    var sessionId = String(params.sessionId || params.session_id || '').trim();
    var locale = String(params.locale || 'ko-KR');
    var market = String(params.market || 'KR');
    if (!appId || !query) throw new Error('appId와 query가 필요합니다.');

    var library = readObjects_(ensureSheet_(SHEETS.LIBRARY)).filter(function (r) {
      return (String(r.APP_ID) === appId || String(r.APP_ID) === 'GLOBAL') && ['READY','ACTIVE','PUBLISHED'].indexOf(String(r.STATUS)) >= 0 && String(r.QA_STATUS) !== 'REJECTED';
    });
    var qTokens = tokens_(query);
    var ranked = library.map(function (row) { return { row: row, score: score_(qTokens, row, intent) }; }).sort(function (a,b) { return b.score - a.score; });
    var best = ranked[0];
    var responseStatus = 'ANSWERED';
    var result;
    if (!best || best.score < 4) {
      var taskId = queueUnanswered_(appId, query, intent, locale, market);
      responseStatus = 'QUEUED_FOR_RESEARCH';
      result = {
        ok: true,
        action: 'front_answer',
        status: responseStatus,
        answer: '현재 검증된 자료에서 정확한 답을 찾지 못했습니다. 질문은 Queens 조사 큐에 등록했습니다.',
        detail: '',
        taskId: taskId,
        sources: []
      };
    } else {
      var r = best.row;
      result = {
        ok: true,
        action: 'front_answer',
        status: responseStatus,
        responseId: r.RESPONSE_ID,
        contentId: r.CONTENT_ID,
        intent: r.INTENT,
        answer: r.ANSWER_SHORT,
        detail: r.ANSWER_DETAIL,
        keyFacts: parseJson_(r.KEY_FACTS_JSON),
        actions: parseJson_(r.ACTIONS_JSON),
        sources: String(r.SOURCE_LINKS || '').split(/\n+/).filter(Boolean),
        sourceLabels: r.SOURCE_LABELS,
        updatedAt: r.UPDATED_AT,
        score: best.score
      };
    }

    appendObject_(ensureSheet_(SHEETS.CALL_LOG), {
      CALL_ID: 'CALL_' + Utilities.getUuid().slice(0, 12).toUpperCase(),
      CALLED_AT: now_(),
      APP_ID: appId,
      SESSION_ID: sessionId,
      QUERY: query,
      INTENT: intent,
      MATCH_RESPONSE_ID: result.responseId || '',
      MATCH_SCORE: result.score || 0,
      SOURCE_CODE: best && best.row ? best.row.SOURCE_CODE : '',
      RESPONSE_STATUS: responseStatus,
      LATENCY_MS: new Date().getTime() - started,
      FEEDBACK: '',
      ERROR: '',
      UPDATED_AT: now_()
    }, HEADERS[SHEETS.CALL_LOG]);
    return result;
  }

  function parseJson_(text) {
    try { return JSON.parse(String(text || '{}')); } catch (e) { return {}; }
  }

  function installTrigger_() {
    ScriptApp.getProjectTriggers().filter(function (t) { return t.getHandlerFunction() === 'runQueensMaterialRefresh'; }).forEach(function (t) { ScriptApp.deleteTrigger(t); });
    ScriptApp.newTrigger('runQueensMaterialRefresh').timeBased().everyHours(1).create();
    return { ok: true, trigger: 'HOURLY' };
  }

  function handle_(e) {
    var p = e && e.parameter || {};
    var action = String(p.action || '').toLowerCase();
    if (['front_answer','get_front_answer','answer'].indexOf(action) < 0) return null;
    try {
      return ContentService.createTextOutput(JSON.stringify(answer_(p))).setMimeType(ContentService.MimeType.JSON);
    } catch (error) {
      return ContentService.createTextOutput(JSON.stringify({ ok: false, action: action, error: String(error && error.message || error) })).setMimeType(ContentService.MimeType.JSON);
    }
  }

  return {
    setup: function () { Object.keys(HEADERS).forEach(ensureSheet_); installTrigger_(); return refreshAll_(); },
    refresh: refreshAll_,
    answer: answer_,
    installTrigger: installTrigger_,
    handle: handle_
  };
})();

function setupQueensFrontResponse() { return QUEENS_FRONT_RESPONSE.setup(); }
function runQueensMaterialRefresh() { return QUEENS_FRONT_RESPONSE.refresh(); }
function getFrontAnswerV1(params) { return QUEENS_FRONT_RESPONSE.answer(params || {}); }
function installQueensRefreshTrigger() { return QUEENS_FRONT_RESPONSE.installTrigger(); }
function handleFrontResponseAction_(e) { return QUEENS_FRONT_RESPONSE.handle(e); }
