(() => {
  if (globalThis.__GOOGLE_AI_ALWAYS_ON_NOTEBOOKLM_V102__) return;
  globalThis.__GOOGLE_AI_ALWAYS_ON_NOTEBOOKLM_V102__ = true;

  const VERSION = '1.0.2';
  const BUILD = 'NLM_FALLBACK_LAST_GOOD_ADAPTER_20260829';
  const HOSTS = new Set(['notebooklm.google.com']);
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const norm = value => String(value || '').replace(/\s+/g, ' ').trim().toLowerCase();

  function visible(el) {
    if (!(el instanceof HTMLElement)) return false;
    const style = getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    return style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || 1) !== 0 && rect.width > 2 && rect.height > 2;
  }

  function openRoots() {
    const roots = [document];
    const seen = new Set(roots);
    for (let i = 0; i < roots.length; i++) {
      const root = roots[i];
      for (const el of root.querySelectorAll?.('*') || []) {
        if (el.shadowRoot && !seen.has(el.shadowRoot)) {
          seen.add(el.shadowRoot);
          roots.push(el.shadowRoot);
        }
      }
    }
    return roots;
  }

  function deepQueryAll(selector) {
    const out = [];
    const seen = new Set();
    for (const root of openRoots()) {
      for (const el of root.querySelectorAll?.(selector) || []) {
        if (!seen.has(el)) {
          seen.add(el);
          out.push(el);
        }
      }
    }
    return out;
  }

  function label(el) {
    return norm([
      el?.innerText,
      el?.textContent,
      el?.getAttribute?.('aria-label'),
      el?.getAttribute?.('title'),
      el?.getAttribute?.('placeholder'),
      el?.getAttribute?.('data-placeholder'),
      el?.getAttribute?.('data-testid')
    ].filter(Boolean).join(' '));
  }

  function controls() {
    return deepQueryAll("button,[role='button'],[role='tab'],a,[tabindex]").filter(visible);
  }

  function findControl(words, {excludeDialogs = false} = {}) {
    const wanted = words.map(norm);
    const matches = controls()
      .filter(el => !excludeDialogs || !el.closest('[role=dialog],dialog'))
      .map(el => ({el, text: label(el)}))
      .filter(x => x.text && x.text.length <= 500 && wanted.some(w => x.text === w || x.text.includes(w)))
      .sort((a, b) => a.text.length - b.text.length);
    return matches[0]?.el || null;
  }

  async function waitFor(factory, timeoutMs = 30000, intervalMs = 350) {
    const started = Date.now();
    while (Date.now() - started < timeoutMs) {
      try {
        const value = factory();
        if (value) return value;
      } catch {}
      await sleep(intervalMs);
    }
    return null;
  }

  function loginRequired() {
    if (location.href.includes('accounts.google.com')) return true;
    const body = norm(document.body?.innerText || '');
    return /sign in to|sign in with google|google 계정으로|로그인/.test(body) || Boolean(findControl(['sign in', '로그인']));
  }

  function notebookIdFromUrl(url = location.href) {
    const match = String(url || '').match(/\/notebook\/([a-z0-9-]+)/i);
    return match ? match[1] : '';
  }

  function dialogs() {
    return deepQueryAll('[role=dialog],dialog').filter(visible);
  }

  function findIn(root, words) {
    const wanted = words.map(norm);
    return [...root.querySelectorAll("button,[role='button'],a,[tabindex],div,span")]
      .filter(visible)
      .map(el => ({el, text: label(el)}))
      .filter(x => x.text && x.text.length <= 500 && wanted.some(w => x.text === w || x.text.includes(w)))
      .sort((a, b) => a.text.length - b.text.length)[0]?.el || null;
  }

  function fillEditor(el, text) {
    el.focus();
    if (el instanceof HTMLTextAreaElement || el instanceof HTMLInputElement) {
      const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
      if (setter) setter.call(el, text); else el.value = text;
      el.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText', data: text}));
      el.dispatchEvent(new Event('change', {bubbles: true}));
      return;
    }
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(el);
    selection?.removeAllRanges();
    selection?.addRange(range);
    document.execCommand('insertText', false, text);
    el.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText', data: text}));
    selection?.removeAllRanges();
  }

  function chatEditor() {
    const selectors = [
      'textarea', "input[type='text']", 'input:not([type])', "[role='textbox']",
      "[contenteditable='true']", "[contenteditable='plaintext-only']", "[aria-multiline='true']"
    ];
    const candidates = [];
    const seen = new Set();
    for (const selector of selectors) {
      for (const el of deepQueryAll(selector)) {
        if (seen.has(el) || !visible(el) || el.closest('[role=dialog],dialog')) continue;
        const meta = label(el);
        if (/search|검색/.test(meta)) continue;
        seen.add(el);
        candidates.push(el);
      }
    }
    return candidates.find(el => /질문|메시지|ask|chat|message|prompt|query|anything|type/.test(label(el))) || candidates.at(-1) || null;
  }

  function sendButtonNear(editor) {
    const direct = deepQueryAll([
      "button[type='submit']", "button[aria-label*='send' i]", "button[aria-label*='보내기']",
      "button[title*='send' i]", "button[title*='보내기']", "button[data-testid*='send' i]",
      "[role='button'][aria-label*='send' i]", "[role='button'][aria-label*='보내기']"
    ].join(',')).filter(visible);
    if (direct.length) return direct.at(-1);
    const named = findControl(['보내기', '전송', '제출', 'send', 'submit']);
    if (named) return named;
    let root = editor?.parentElement;
    for (let depth = 0; depth < 5 && root; depth++, root = root.parentElement) {
      const likely = [...root.querySelectorAll("button,[role='button']")].filter(visible).find(el => /send|submit|보내기|전송/.test(label(el)));
      if (likely) return likely;
    }
    return null;
  }

  async function submitEditor(editor) {
    const button = sendButtonNear(editor);
    if (button && !button.disabled && button.getAttribute('aria-disabled') !== 'true') {
      button.click();
      await sleep(800);
      return 'BUTTON';
    }
    editor.focus();
    const opts = {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true, shiftKey: false};
    editor.dispatchEvent(new KeyboardEvent('keydown', opts));
    editor.dispatchEvent(new KeyboardEvent('keypress', opts));
    editor.dispatchEvent(new KeyboardEvent('keyup', opts));
    await sleep(1000);
    return 'ENTER_FALLBACK';
  }

  function explicitGenerationApproval(task) {
    const approval = norm(task?.approval || task?.approvalStatus || '');
    return task?.allowGenerate === true || task?.generationApproved === true || task?.creditApproved === true || approval === 'approved';
  }

  function taskType(task) {
    return String(task?.taskType || task?.action || 'PROBE').trim().toUpperCase();
  }

  async function probe(task) {
    const notebookId = notebookIdFromUrl();
    const create = findControl(['노트북 만들기', '새 노트북', '새 노트북 만들기', 'create notebook', 'new notebook', 'create new']);
    const editor = chatEditor();
    return {
      status: 'CONNECTED',
      ok: true,
      capability: 'NOTEBOOKLM_NO_CREDIT_PREFLIGHT',
      taskId: task?.taskId || '',
      notebookId,
      notebookUrl: notebookId ? location.href : '',
      landingReady: Boolean(create) || Boolean(notebookId),
      createControlFound: Boolean(create),
      chatEditorFound: Boolean(editor),
      loginRequired: false,
      build: BUILD,
      version: VERSION,
      generateClicked: false,
      creditSpend: false
    };
  }

  async function addFreshSource(sourceText) {
    const text = String(sourceText || '').trim();
    if (!text) return {ok: true, skipped: true, reason: 'NO_SOURCE_TEXT'};
    let choice = null;
    for (const dialog of dialogs()) {
      choice = findIn(dialog, ['복사된 텍스트', '복사한 텍스트', '붙여넣은 텍스트', 'copied text', 'paste text']);
      if (choice) break;
    }
    if (!choice) {
      const add = findControl(['소스 추가', '자료 추가', '출처 추가', 'add source', 'add sources']);
      if (!add) return {ok: false, reason: 'ADD_SOURCE_CONTROL_NOT_FOUND'};
      add.click();
      choice = await waitFor(() => {
        for (const dialog of dialogs()) {
          const found = findIn(dialog, ['복사된 텍스트', '복사한 텍스트', '붙여넣은 텍스트', 'copied text', 'paste text']);
          if (found) return found;
        }
        return null;
      }, 20000);
    }
    if (!choice) return {ok: false, reason: 'PASTED_TEXT_SOURCE_TYPE_NOT_FOUND'};
    choice.click();
    const editor = await waitFor(() => {
      for (const dialog of dialogs()) {
        const list = [...dialog.querySelectorAll("textarea,[contenteditable='true'][role='textbox'],[contenteditable='true']")].filter(visible);
        if (list.length) return list.at(-1);
      }
      return null;
    }, 20000);
    if (!editor) return {ok: false, reason: 'SOURCE_EDITOR_NOT_FOUND'};
    fillEditor(editor, text);
    const save = await waitFor(() => {
      for (const dialog of dialogs()) {
        const found = findIn(dialog, ['삽입', '추가', '저장', '완료', 'insert', 'add', 'save', 'submit']);
        if (found) return found;
      }
      return null;
    }, 15000);
    if (!save) return {ok: false, reason: 'SOURCE_SAVE_CONTROL_NOT_FOUND'};
    save.click();
    await sleep(2500);
    return {ok: true};
  }

  async function renameNotebook(title) {
    const wanted = String(title || '').trim();
    if (!wanted) return {ok: true, skipped: true};
    const candidates = deepQueryAll("editable-project-title,input[aria-label*='title' i],input[aria-label*='제목'],[contenteditable='true']").filter(visible);
    const target = candidates.find(el => /title|제목|editable-project-title/.test(label(el))) || deepQueryAll('editable-project-title').find(visible);
    if (!target) return {ok: false, reason: 'TITLE_EDITOR_NOT_FOUND'};
    try {
      target.click();
      await sleep(300);
      const input = deepQueryAll("input,textarea,[contenteditable='true']").filter(visible).at(-1) || target;
      fillEditor(input, wanted);
      input.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true}));
      input.dispatchEvent(new KeyboardEvent('keyup', {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true}));
      await sleep(700);
      return {ok: true, title: wanted};
    } catch (error) {
      return {ok: false, reason: String(error?.message || error)};
    }
  }

  async function createFreshNotebook(task) {
    if (notebookIdFromUrl()) {
      return {status: 'NEEDS_USER', error: 'FALLBACK_CREATE_REQUIRES_NOTEBOOKLM_LANDING_PAGE', build: BUILD, generateClicked: false, creditSpend: false};
    }
    const create = await waitFor(() => findControl(['노트북 만들기', '새 노트북', '새 노트북 만들기', 'create notebook', 'new notebook', 'create new']), 30000, 500);
    if (!create) return {status: 'NEEDS_USER', error: `FRESH_NOTEBOOK_CREATE_CONTROL_NOT_FOUND:${location.href}`, build: BUILD, generateClicked: false, creditSpend: false};
    const clickedAt = new Date().toISOString();
    create.click();
    const newId = await waitFor(() => notebookIdFromUrl(), Math.max(45000, Number(task?.timeoutSeconds || 90) * 1000), 500);
    if (!newId) return {status: 'FAILED', error: `FRESH_NOTEBOOK_URL_NOT_CREATED:${location.href}`, build: BUILD, generateClicked: false, creditSpend: false};
    await sleep(1500);
    const titleResult = await renameNotebook(task?.title || task?.contentId || task?.taskId || '');
    const source = await addFreshSource(task?.sourceText || '');
    if (!source.ok) return {status: 'FAILED', error: `FRESH_NOTEBOOK_SOURCE_ADD_FAILED:${source.reason || 'UNKNOWN'}`, notebookId: newId, notebookUrl: location.href, build: BUILD, generateClicked: false, creditSpend: false};
    return {
      status: 'DONE',
      resultText: 'FRESH_NOTEBOOK_CREATED',
      captureMode: 'FRESH_NOTEBOOK_ID_CREATED_AND_SOURCE_ADDED',
      notebookUrl: location.href,
      notebookId: newId,
      freshNotebook: true,
      createdAt: clickedAt,
      capturedAt: new Date().toISOString(),
      pageTitle: document.title,
      titleResult,
      source,
      taskId: task?.taskId || '',
      contentId: task?.contentId || '',
      taskType: taskType(task),
      build: BUILD,
      generateClicked: false,
      creditSpend: false
    };
  }

  function buildChatPrompt(task) {
    return [
      `[TASK_ID] ${task?.taskId || ''}`,
      `[CONTENT_ID] ${task?.contentId || ''}`,
      `[작업 유형] ${taskType(task)}`,
      `[언어] ${task?.language || 'ko-KR'}`,
      '',
      '[NotebookLM 작업 지시서]',
      task?.instruction || '요청된 결과를 만들어 주세요.',
      '',
      '[CURRENT_TASK_SOURCE]',
      task?.sourceText || ''
    ].join('\n').trim();
  }

  async function submitChat(task) {
    if (!notebookIdFromUrl()) return {status: 'NEEDS_USER', error: 'NOTEBOOK_URL_REQUIRED_FOR_CHAT_FALLBACK', build: BUILD, generateClicked: false, creditSpend: false};
    if (!explicitGenerationApproval(task)) return {status: 'BLOCKED_APPROVAL_GATE', error: 'CHAT_GENERATION_REQUIRES_EXPLICIT_APPROVAL', build: BUILD, generateClicked: false, creditSpend: false};
    let editor = await waitFor(() => chatEditor(), 12000, 500);
    if (!editor) {
      const chat = findControl(['채팅', 'chat']);
      if (chat) { try { chat.click(); } catch {}; await sleep(1800); }
      editor = await waitFor(() => chatEditor(), 45000, 600);
    }
    if (!editor) return {status: 'NEEDS_USER', error: `CHAT_EDITOR_NOT_FOUND:${location.href}`, build: BUILD, generateClicked: false, creditSpend: false};
    const prompt = buildChatPrompt(task);
    fillEditor(editor, prompt);
    const method = await submitEditor(editor);
    return {
      status: 'SUBMITTED',
      resultText: 'NOTEBOOKLM_CHAT_SUBMITTED_AWAIT_PRIMARY_READBACK',
      captureMode: 'CHAT_SUBMITTED_NO_FALSE_DONE',
      taskId: task?.taskId || '',
      notebookId: notebookIdFromUrl(),
      notebookUrl: location.href,
      submitMethod: method,
      build: BUILD,
      generateClicked: true,
      creditSpend: false
    };
  }

  async function run(task) {
    if (!HOSTS.has(location.hostname)) return {status: 'FAILED', error: `NOTEBOOKLM_HOST_MISMATCH:${location.hostname}`, build: BUILD, generateClicked: false, creditSpend: false};
    if (loginRequired()) return {status: 'NEEDS_USER', error: 'Google login required', build: BUILD, generateClicked: false, creditSpend: false};
    const type = taskType(task);
    if (['PROBE', 'CONNECT', 'CONNECTED', 'HEALTH', 'PING', 'NOTEBOOKLM_PROBE'].includes(type)) return probe(task);
    if (['FRESH_NOTEBOOK_CREATE', 'NOTEBOOK_CREATE', 'NEW_NOTEBOOK'].includes(type)) return createFreshNotebook(task);
    if (['CHAT', 'NOTEBOOKLM_CHAT'].includes(type)) return submitChat(task);
    return {
      status: 'NEEDS_USER',
      error: `ALWAYS_ON_NOTEBOOKLM_UNSUPPORTED_USE_PRIMARY_0.2.71:${type}`,
      primaryBridgeRequired: true,
      supportedFallbackTaskTypes: ['PROBE', 'FRESH_NOTEBOOK_CREATE', 'NOTEBOOK_CREATE', 'NEW_NOTEBOOK', 'CHAT'],
      build: BUILD,
      generateClicked: false,
      creditSpend: false
    };
  }

  chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    if (!msg || msg.type !== 'RUN_BRIDGE_TASK') return false;
    run(msg.task || {})
      .then(sendResponse)
      .catch(error => sendResponse({status: 'FAILED', error: String(error?.message || error), build: BUILD, generateClicked: false, creditSpend: false}));
    return true;
  });
})();
