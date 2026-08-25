(() => {
  if (globalThis.__NLM_WEBAPP_BRIDGE_LOADED__) return;
  globalThis.__NLM_WEBAPP_BRIDGE_LOADED__ = true;

  const SOURCE = "notebooklm-webapp-bridge";
  const HOSTS = new Set(["notebook.google.com", "notebooklm.google.com"]);
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const norm = (v) => String(v || "").replace(/\s+/g, " ").trim().toLowerCase();

  function visible(el) {
    if (!(el instanceof HTMLElement)) return false;
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return s.display !== "none" && s.visibility !== "hidden" && r.width > 2 && r.height > 2;
  }

  async function waitFor(factory, timeout = 25000, interval = 350) {
    const start = Date.now();
    while (Date.now() - start < timeout) {
      try {
        const v = factory();
        if (v) return v;
      } catch {}
      await sleep(interval);
    }
    return null;
  }

  function findButton(words, root = document, excludeDialogs = false) {
    return [...root.querySelectorAll("button,[role='button']")]
      .filter(el => visible(el) && (!excludeDialogs || !el.closest("[role='dialog'],dialog")))
      .find(el => {
        const t = norm([
          el.innerText,
          el.textContent,
          el.getAttribute("aria-label"),
          el.getAttribute("title"),
          el.getAttribute("data-testid")
        ].join(" "));
        return words.some(w => t.includes(norm(w)));
      }) || null;
  }

  function nativeValue(el, value) {
    const proto = el instanceof HTMLTextAreaElement
      ? HTMLTextAreaElement.prototype
      : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, "value")?.set;
    setter?.call(el, value);
  }

  function fill(el, text) {
    el.focus();
    if (el instanceof HTMLTextAreaElement || el instanceof HTMLInputElement) {
      nativeValue(el, text);
      el.dispatchEvent(new InputEvent("input", {bubbles:true, inputType:"insertText", data:text}));
      el.dispatchEvent(new Event("change", {bubbles:true}));
      return;
    }

    const sel = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(el);
    sel?.removeAllRanges();
    sel?.addRange(range);
    document.execCommand("insertText", false, text);
    el.dispatchEvent(new InputEvent("input", {bubbles:true, inputType:"insertText", data:text}));
    sel?.removeAllRanges();
  }

  function dialogs() {
    return [...document.querySelectorAll("[role='dialog'],dialog")].filter(visible);
  }

  function dialogEditor() {
    for (const d of dialogs()) {
      const list = [...d.querySelectorAll("textarea,[contenteditable='true'][role='textbox'],[contenteditable='true']")].filter(visible);
      if (list.length) return list.at(-1);
    }
    return null;
  }

  async function addSource(task) {
    if (!task.sourceText) return {ok:false, skipped:true};

    let choice = null;
    for (const d of dialogs()) {
      choice = findButton(["복사된 텍스트","복사한 텍스트","붙여넣은 텍스트","copied text","paste text"], d);
      if (choice) break;
    }

    if (!choice) {
      const add = findButton(["소스 추가","자료 추가","출처 추가","add source","add sources"]);
      if (!add) return {ok:false, skipped:true, reason:"add source control not found"};
      add.click();

      choice = await waitFor(() => {
        for (const d of dialogs()) {
          const b = findButton(["복사된 텍스트","복사한 텍스트","붙여넣은 텍스트","copied text","paste text"], d);
          if (b) return b;
        }
        return null;
      }, 20000);
    }

    if (!choice) return {ok:false, skipped:true, reason:"pasted text source type not found"};
    choice.click();

    const editor = await waitFor(() => dialogEditor(), 20000);
    if (!editor) return {ok:false, skipped:true, reason:"source editor not found"};
    fill(editor, task.sourceText);

    const confirm = await waitFor(() => {
      for (const d of dialogs()) {
        const b = findButton(["삽입","추가","저장","완료","insert","add","save","submit"], d);
        if (b) return b;
      }
      return null;
    }, 15000);

    if (!confirm) return {ok:false, skipped:true, reason:"source save control not found"};
    confirm.click();
    await waitFor(() => dialogs().length === 0 ? document.body : null, 35000, 500);
    await sleep(2500);
    return {ok:true};
  }

  function chatEditor() {
    const list = [];
    for (const sel of ["textarea","[contenteditable='true'][role='textbox']","[contenteditable='true']"]) {
      for (const el of document.querySelectorAll(sel)) {
        if (!visible(el) || el.closest("[role='dialog'],dialog")) continue;
        list.push(el);
      }
    }
    if (!list.length) return null;

    return list.find(el => {
      const h = norm([
        el.getAttribute("placeholder"),
        el.getAttribute("aria-label"),
        el.getAttribute("data-placeholder")
      ].join(" "));
      return ["질문","메시지","ask","chat","message","prompt"].some(w => h.includes(w));
    }) || list.at(-1);
  }

  function buildPrompt(task, sourceAdded) {
    return [
      `[TASK_ID] ${task.taskId}`,
      `[CONTENT_ID] ${task.contentId || ""}`,
      `[작업 유형] ${task.taskType || "CHAT"}`,
      `[언어] ${task.language || "ko-KR"}`,
      "",
      "[NotebookLM 작업 지시서]",
      task.instruction || "요청된 결과를 만들어 주세요.",
      ...(sourceAdded ? [] : ["", "[원문]", task.sourceText || ""])
    ].join("\n").trim();
  }

  function marker(task) {
    const m = String(task?.instruction || "").match(/\bNLM_E2E_PASS_[A-Z0-9_-]+\b/i);
    return m ? m[0] : "";
  }

  function markerCount(value) {
    if (!value) return 0;
    const text = document.body?.innerText || "";
    return text.split(value).length - 1;
  }

  function resultCandidates() {
    const out = [];
    const seen = new Set();

    for (const sel of ["article","[role='article']","[class*='answer']","[class*='response']","[class*='message']","[class*='chat']"]) {
      for (const el of document.querySelectorAll(sel)) {
        if (!visible(el) || el.closest("nav,[role='dialog'],dialog")) continue;
        const t = (el.innerText || el.textContent || "").trim();
        if (t.length < 2 || t.length > 30000 || seen.has(t)) continue;
        seen.add(t);
        out.push(t);
      }
    }
    return out;
  }

  function generationInProgress() {
    return Boolean(findButton(["stop","중지","생성 중지","stop generating"], document, true));
  }

  function uiOnlyResult(text) {
    const t = norm(text);
    return /^(?:소스\s*\d+개|sources?\s*\d+)(?:\s+(?:stop|중지))?$/.test(t)
      || /^(?:stop|중지|생성 중지|stop generating)$/.test(t);
  }

  function sendButtonNear(editor) {
    const selectors = [
      "button[type='submit']",
      "button[aria-label*='send' i]",
      "button[aria-label*='보내기']",
      "button[title*='send' i]",
      "button[title*='보내기']",
      "button[data-testid*='send' i]",
      "[role='button'][aria-label*='send' i]",
      "[role='button'][aria-label*='보내기']"
    ];

    for (const sel of selectors) {
      const all = [...document.querySelectorAll(sel)].filter(visible);
      if (all.length) return all.at(-1);
    }

    const direct = findButton(["보내기","전송","제출","send","submit"], document, true);
    if (direct) return direct;

    let root = editor?.parentElement;
    for (let depth = 0; depth < 5 && root; depth++, root = root.parentElement) {
      const buttons = [...root.querySelectorAll("button,[role='button']")].filter(visible);
      const likely = buttons.find(b => {
        const label = norm([
          b.getAttribute("aria-label"),
          b.getAttribute("title"),
          b.getAttribute("data-testid")
        ].join(" "));
        return /send|submit|보내기|전송/.test(label);
      });
      if (likely) return likely;
    }

    return null;
  }

  async function submitEditor(editor) {
    const button = sendButtonNear(editor);

    if (button && !button.disabled && button.getAttribute("aria-disabled") !== "true") {
      button.click();
      await sleep(800);
      return {method:"BUTTON"};
    }

    // V7.3 fallback for current Gemini Notebook UI:
    // the prompt is already inserted, so submit with the same Enter gesture a user would use.
    editor.focus();

    const opts = {
      key:"Enter",
      code:"Enter",
      keyCode:13,
      which:13,
      bubbles:true,
      cancelable:true,
      shiftKey:false,
      ctrlKey:false,
      altKey:false,
      metaKey:false
    };

    editor.dispatchEvent(new KeyboardEvent("keydown", opts));
    editor.dispatchEvent(new KeyboardEvent("keypress", opts));
    editor.dispatchEvent(new KeyboardEvent("keyup", opts));
    await sleep(1000);

    return {method:"ENTER_FALLBACK"};
  }


  function exactAssistantMarker(markerText) {
    if (!markerText) return null;

    const selectors = [
      "p","span","div","article","[role='article']","[class*='answer']","[class*='response']","[class*='message']"
    ];
    const candidates = [];

    for (const sel of selectors) {
      for (const el of document.querySelectorAll(sel)) {
        if (!visible(el)) continue;
        if (el.closest("textarea,[contenteditable='true'],[role='textbox'],[role='dialog'],dialog")) continue;

        const t = (el.innerText || el.textContent || "").trim();
        if (!t.includes(markerText) || t.length > markerText.length + 400) continue;

        // NotebookLM can wrap the answer marker with citations/action labels.
        // Reject prompt copies, then prefer assistant-like and smallest matching nodes.
        let parent = el;
        let looksLikePrompt = false;
        let looksLikeAnswer = false;
        for (let depth = 0; depth < 6 && parent; depth++, parent = parent.parentElement) {
          const pt = (parent.innerText || parent.textContent || "").trim();
          if (pt.includes("[TASK_ID]") || pt.includes("[NotebookLM 작업 지시서]") || pt.includes("[원문]")) {
            looksLikePrompt = true;
            break;
          }
          if (/메모에 저장|keep_pin|copy_all|thumb_up|thumb_down|copy|복사/i.test(pt)) {
            looksLikeAnswer = true;
          }
        }

        if (!looksLikePrompt) candidates.push({el, looksLikeAnswer, exact:t === markerText, length:t.length});
      }
    }

    if (!candidates.length) return null;
    return [...candidates]
      .sort((a,b) => Number(b.exact) - Number(a.exact) || Number(b.looksLikeAnswer) - Number(a.looksLikeAnswer) || a.length - b.length)[0].el;
  }

  async function waitResult(task, baselineMarker, baselineCandidates, timeoutMs) {
    const mk = marker(task);
    const start = Date.now();

    while (Date.now() - start < timeoutMs) {
      await sleep(1400);

      if (mk) {
        // V7.5: do NOT use raw marker-count growth. The submitted user prompt itself
        // contains the marker and can briefly create duplicate DOM copies while NotebookLM
        // is generating. Accept the smallest visible non-prompt assistant node containing
        // the requested marker because current NotebookLM may wrap it with UI/citation text.
        const answerNode = exactAssistantMarker(mk);
        if (answerNode) {
          return {
            resultText: mk,
            resultUrls: [],
            verificationMarker: mk,
            captureMode: "ASSISTANT_MARKER_NODE",
            notebookUrl: location.href,
            pageTitle: document.title,
            capturedAt: new Date().toISOString()
          };
        }
      } else {
        if (generationInProgress()) continue;

        const current = resultCandidates();
        const fresh = current
          .filter(t => !baselineCandidates.includes(t) && t.length >= 3)
          .filter(t => !t.includes("[TASK_ID]") && !t.includes("[NotebookLM 작업 지시서]") && !t.includes("[원문]"))
          .filter(t => !/페이지 읽는 중|소스 참조 중/i.test(t))
          .filter(t => !uiOnlyResult(t));

        if (fresh.length) {
          // Prefer the smallest meaningful newly-created result instead of a page-wide container.
          const chosen = [...fresh].sort((a,b) => a.length - b.length)[0];
          return {
            resultText: chosen,
            resultUrls: [],
            captureMode: "SMALLEST_NEW_RESULT",
            notebookUrl: location.href,
            pageTitle: document.title,
            capturedAt: new Date().toISOString()
          };
        }
      }
    }

    if (mk) throw new Error(`실제 NotebookLM 답변 마커를 찾지 못했습니다: ${mk}`);
    throw new Error("실제 NotebookLM 답변 텍스트가 생성되지 않았습니다.");
  }

  async function runTask(task) {
    if (!HOSTS.has(location.hostname)) throw new Error("NotebookLM 페이지가 아닙니다.");
    if (!task?.taskId) throw new Error("TASK_ID가 없습니다.");

    const source = await addSource(task);
    const editor = await waitFor(() => chatEditor(), 70000, 600);
    if (!editor) throw new Error("NotebookLM 채팅 입력창을 찾지 못했습니다.");

    fill(editor, buildPrompt(task, source.ok));

    const mk = marker(task);
    const baselineMarker = markerCount(mk);
    const baselineCandidates = resultCandidates();

    let submit = {method:"PREPARED"};
    if (task.autoSubmit !== false) submit = await submitEditor(editor);

    const result = task.autoSubmit === false
      ? {
          resultText:"",
          resultUrls:[],
          notebookUrl:location.href,
          pageTitle:document.title,
          status:"PREPARED"
        }
      : await waitResult(task, baselineMarker, baselineCandidates, Number(task.timeoutSeconds || 180) * 1000);

    if (task.autoSubmit !== false && !String(result.resultText || "").trim()) {
      throw new Error("NotebookLM 실제 답변 텍스트가 비어 있습니다.");
    }

    return {
      ...result,
      status:"DONE",
      taskId:task.taskId,
      contentId:task.contentId || "",
      taskType:task.taskType || "CHAT",
      source,
      submit
    };
  }

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || message.source !== SOURCE || message.type !== "RUN_NOTEBOOK_TASK") return false;

    runTask(message.task)
      .then(result => sendResponse({ok:true, result}))
      .catch(error => sendResponse({
        ok:false,
        error:error instanceof Error ? error.message : String(error)
      }));

    return true;
  });
})();
