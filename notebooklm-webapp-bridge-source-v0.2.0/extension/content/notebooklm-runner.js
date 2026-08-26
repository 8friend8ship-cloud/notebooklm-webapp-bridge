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

  function openRoots() {
    const roots = [document];
    const seen = new Set(roots);
    for (let i = 0; i < roots.length; i++) {
      const root = roots[i];
      for (const el of root.querySelectorAll?.("*") || []) {
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

  function findDeepControl(words) {
    return deepQueryAll("button,[role='button'],[role='tab'],a")
      .filter(el => visible(el) && !el.closest("[role='dialog'],dialog"))
      .find(el => {
        const t = norm([
          el.innerText,
          el.textContent,
          el.getAttribute("aria-label"),
          el.getAttribute("title"),
          el.getAttribute("data-testid")
        ].join(" "));
        return words.some(w => t === norm(w) || t.includes(norm(w)));
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

  function loginRequired() {
    const body = norm(document.body?.innerText || "");
    if (/sign in to|sign in with google|로그인|google 계정으로/.test(body)) return true;
    return Boolean(findDeepControl(["sign in","로그인"]));
  }

  function chatEditor() {
    const list = [];
    const seen = new Set();
    const selectors = [
      "textarea",
      "input[type='text']",
      "input:not([type])",
      "[role='textbox']",
      "[contenteditable='true']",
      "[contenteditable='plaintext-only']",
      "[aria-multiline='true']"
    ];
    for (const sel of selectors) {
      for (const el of deepQueryAll(sel)) {
        if (seen.has(el) || !visible(el) || el.closest("[role='dialog'],dialog")) continue;
        const meta = norm([
          el.getAttribute("type"),
          el.getAttribute("placeholder"),
          el.getAttribute("aria-label"),
          el.getAttribute("data-placeholder"),
          el.getAttribute("data-testid")
        ].join(" "));
        if (/search|검색/.test(meta)) continue;
        seen.add(el);
        list.push(el);
      }
    }
    if (!list.length) return null;

    return list.find(el => {
      const h = norm([
        el.getAttribute("placeholder"),
        el.getAttribute("aria-label"),
        el.getAttribute("data-placeholder"),
        el.getAttribute("data-testid")
      ].join(" "));
      return ["질문","메시지","ask","chat","message","prompt","query","anything","type"].some(w => h.includes(w));
    }) || list.at(-1);
  }

  async function ensureChatSurface() {
    let editor = await waitFor(() => chatEditor(), 12000, 500);
    if (editor) return editor;
    if (loginRequired()) throw new Error(`NOTEBOOK_LOGIN_REQUIRED: ${location.href}`);

    const chat = findDeepControl(["채팅","chat"]);
    if (chat) {
      try { chat.click(); } catch {}
      await sleep(1800);
    }

    editor = await waitFor(() => chatEditor(), 58000, 600);
    if (editor) return editor;
    if (loginRequired()) throw new Error(`NOTEBOOK_LOGIN_REQUIRED: ${location.href}`);
    return null;
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
    const m = String(task?.instruction || "").match(/\bNLM_[A-Z0-9_-]*PASS[A-Z0-9_-]*\b/i);
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
      for (const el of deepQueryAll(sel)) {
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
      const all = deepQueryAll(sel).filter(visible);
      if (all.length) return all.at(-1);
    }

    const direct = findDeepControl(["보내기","전송","제출","send","submit"]);
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
      for (const el of deepQueryAll(sel)) {
        if (!visible(el)) continue;
        if (el.closest("textarea,[contenteditable='true'],[role='textbox'],[role='dialog'],dialog")) continue;

        const t = (el.innerText || el.textContent || "").trim();
        if (!t.includes(markerText) || t.length > markerText.length + 400) continue;

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

  function audioOverviewContainer() {
    const nodes = deepQueryAll("section,article,div,[role=group],[role=region]").filter(visible);
    return nodes.find(el => {
      const t = norm(el.innerText || el.textContent || "");
      return t.includes("audio overview") || t.includes("ai 오디오 오버뷰") || t.includes("오디오 오버뷰") || t.includes("오디오 개요") || t.includes("음성 개요");
    }) || null;
  }

  function audioOverviewReady() {
    for (const el of deepQueryAll("audio")) {
      try {
        if (el.currentSrc || el.src || Number.isFinite(el.duration)) return el;
      } catch {}
    }
    const c = audioOverviewContainer();
    if (!c) return null;
    const t = norm(c.innerText || c.textContent || "");
    const labels = [...c.querySelectorAll("button,[role=button]")].filter(visible).map(b => norm([b.innerText,b.textContent,b.getAttribute("aria-label"),b.getAttribute("title")].join(" "))).join(" ");
    if (/play|재생|download|다운로드|share|공유/.test(labels) && !/generating|생성 중|creating|만드는 중/.test(t)) return c;
    return null;
  }

  
  function actionLabel(el) {
    return norm([el?.innerText,el?.textContent,el?.getAttribute?.("aria-label"),el?.getAttribute?.("title"),el?.getAttribute?.("data-testid")].join(" "));
  }

  function artifactMenuButtonWithin(root) {
    if (!root?.querySelectorAll) return null;
    return [...root.querySelectorAll("button,[role='button'],a")]
      .filter(visible)
      .find(el => /more_vert|more options|more actions|더보기|옵션|메뉴/.test(actionLabel(el))) || null;
  }

  function audioArtifactCardRoot(readyNode) {
    let cur = readyNode instanceof HTMLElement ? readyNode : null;
    for (let i=0; i<10 && cur; i++, cur=cur.parentElement) {
      const t = norm(cur.innerText || cur.textContent || "");
      const studioMenuHits = ["ai 오디오 오버뷰","슬라이드 자료","동영상 개요","마인드맵","보고서","플래시카드","퀴즈","인포그래픽","데이터 표"].filter(w => t.includes(w)).length;
      if (studioMenuHits < 5 && /\b\d{1,2}:\d{2}\b/.test(t) && /소스\s*\d+개|sources?\s*\d+|딥 다이브|deep dive/.test(t) && artifactMenuButtonWithin(cur)) return cur;
    }
    const candidates = deepQueryAll("section,article,div,[role='group'],[role='region']")
      .filter(visible)
      .map(el => ({el,text:(el.innerText || el.textContent || "").trim()}))
      .filter(x => x.text.length >= 10 && x.text.length <= 2500)
      .filter(x => /\b\d{1,2}:\d{2}\b/.test(norm(x.text)))
      .filter(x => /소스\s*\d+개|sources?\s*\d+|딥 다이브|deep dive/.test(norm(x.text)))
      .filter(x => ["ai 오디오 오버뷰","슬라이드 자료","동영상 개요","마인드맵","보고서","플래시카드","퀴즈","인포그래픽","데이터 표"].filter(w => norm(x.text).includes(w)).length < 5)
      .filter(x => artifactMenuButtonWithin(x.el))
      .sort((a,b) => a.text.length - b.text.length);
    return candidates[0]?.el || null;
  }

  async function requestNotebookArtifactDownload(readyNode) {
    const startedAtEpochMs = Date.now();
    const root = audioArtifactCardRoot(readyNode);
    if (!root) return {requested:false, reason:"real audio artifact card not found", startedAtEpochMs};
    const localButtons = [...root.querySelectorAll("button,[role='button'],a")].filter(visible);
    const direct = localButtons.find(el => /(^|\s)(download|다운로드)(\s|$)/.test(actionLabel(el)));
    if (direct) {
      try { direct.click(); } catch {}
      await sleep(1200);
      return {requested:true, method:"DIRECT", startedAtEpochMs, cardText:(root.innerText || root.textContent || "").trim().slice(0,500)};
    }
    const menu = artifactMenuButtonWithin(root);
    if (!menu) return {requested:false, reason:"real audio card menu not found", startedAtEpochMs};
    try { menu.click(); } catch {}
    await sleep(700);
    const download = await waitFor(() => findDeepControl(["다운로드","download"]), 8000, 250);
    if (!download) return {requested:false, reason:"download action not found after real audio card menu", startedAtEpochMs};
    try { download.click(); } catch {}
    await sleep(1200);
    return {requested:true, method:"MENU_DOWNLOAD", startedAtEpochMs, cardText:(root.innerText || root.textContent || "").trim().slice(0,500)};
  }

  async function mirrorNotebookArtifactToDrive(task, artifactType, startedAtEpochMs) {
    try {
      return await chrome.runtime.sendMessage({source:SOURCE,type:"MIRROR_ARTIFACT_TO_DRIVE",taskId:task.taskId,artifactType,startedAtEpochMs});
    } catch (error) {
      return {ok:false,error:String(error?.message || error)};
    }
  }
  
    async function runAudioOverview(task) {
    const source = await addSource(task);
    const sourceFallback = !source.ok && Boolean(task.sourceText);

    const studio = findDeepControl(["studio","스튜디오"]);
    if (studio) { try { studio.click(); } catch {} await sleep(1200); }

    const audioControl = await waitFor(() => findDeepControl(["audio overview","ai 오디오 오버뷰","오디오 오버뷰","오디오 개요","음성 개요"]), 30000, 500);
    if (!audioControl) throw new Error(`AUDIO_OVERVIEW_CONTROL_NOT_FOUND: ${location.href}`);

    const before = audioOverviewReady();
    if (!before) {
      try { audioControl.click(); } catch {}
      await sleep(1200);

      const generate = await waitFor(() => {
        for (const d of dialogs()) {
          const b = findButton(["생성","만들기","generate","create"], d);
          if (b) return b;
        }
        const c = audioOverviewContainer();
        if (!c) return null;
        return [...c.querySelectorAll("button,[role=button]")].filter(visible).find(el => {
          const t = norm([el.innerText,el.textContent,el.getAttribute("aria-label"),el.getAttribute("title")].join(" "));
          return /generate|create|생성|만들기/.test(t);
        }) || null;
      }, 12000, 400);
      if (generate) { try { generate.click(); } catch {} await sleep(1000); }
    }

    const timeoutMs = Math.max(180000, Number(task.timeoutSeconds || 600) * 1000);
    const ready = await waitFor(() => audioOverviewReady(), timeoutMs, 2500);
    if (!ready) throw new Error("AUDIO_OVERVIEW_GENERATION_TIMEOUT_OR_PLAYER_NOT_FOUND");

    const download = await requestNotebookArtifactDownload(ready);
    if (!download?.requested) throw new Error(`AUDIO_ARTIFACT_DOWNLOAD_NOT_TRIGGERED: ${download?.reason || "unknown"}`);
    const mirror = await mirrorNotebookArtifactToDrive(task, "AUDIO_OVERVIEW", download.startedAtEpochMs);
    if (!mirror?.ok || !mirror?.mirror?.ok) throw new Error(`AUDIO_DRIVE_MIRROR_FAILED: ${mirror?.error || mirror?.raw?.stderr || "unknown"}`);

    return {
      resultText:"AUDIO_OVERVIEW_READY",
      resultUrls:[location.href],
      captureMode:"AUDIO_PLAYER_READY",
      notebookUrl:location.href,
      pageTitle:document.title,
      capturedAt:new Date().toISOString(),
      status:"DONE",
      taskId:task.taskId,
      contentId:task.contentId || "",
      taskType:task.taskType || "AUDIO_OVERVIEW",
      actualArtifact:{download,mirror:mirror.mirror,localTaskId:mirror.localTaskId},
      source: {...source, existingNotebookFallback: sourceFallback}
    };
  }

  function videoOverviewContainer() {
    const nodes = deepQueryAll("section,article,div,[role=group],[role=region]").filter(visible);
    return nodes.find(el => {
      const t = norm(el.innerText || el.textContent || "");
      return t.includes("video overview") || t.includes("동영상 개요") || t.includes("비디오 개요");
    }) || null;
  }

  function videoOverviewReady() {
    for (const el of deepQueryAll("video")) {
      try { if (el.currentSrc || el.src || Number.isFinite(el.duration)) return el; } catch {}
    }
    const c = videoOverviewContainer();
    if (!c) return null;
    const t = norm(c.innerText || c.textContent || "");
    const labels = [...c.querySelectorAll("button,[role=button]")].filter(visible).map(b => norm([b.innerText,b.textContent,b.getAttribute("aria-label"),b.getAttribute("title")].join(" "))).join(" ");
    if (/play|재생|download|다운로드|share|공유/.test(labels) && !/generating|생성 중|creating|만드는 중/.test(t)) return c;
    return null;
  }

  async function runVideoOverview(task) {
    const source = await addSource(task);
    const sourceFallback = !source.ok && Boolean(task.sourceText);

    const studio = findDeepControl(["studio","스튜디오"]);
    if (studio) { try { studio.click(); } catch {} await sleep(1200); }

    const videoControl = await waitFor(() => findDeepControl(["video overview","동영상 개요","비디오 개요"]), 30000, 500);
    if (!videoControl) throw new Error(`VIDEO_OVERVIEW_CONTROL_NOT_FOUND: ${location.href}`);

    const before = videoOverviewReady();
    if (!before) {
      try { videoControl.click(); } catch {}
      await sleep(1200);

      const generate = await waitFor(() => {
        for (const d of dialogs()) {
          const b = findButton(["생성","만들기","generate","create"], d);
          if (b) return b;
        }
        const c = videoOverviewContainer();
        if (!c) return null;
        return [...c.querySelectorAll("button,[role=button]")].filter(visible).find(el => {
          const t = norm([el.innerText,el.textContent,el.getAttribute("aria-label"),el.getAttribute("title")].join(" "));
          return /generate|create|생성|만들기/.test(t);
        }) || null;
      }, 15000, 400);
      if (generate) { try { generate.click(); } catch {} await sleep(1000); }
    }

    const timeoutMs = Math.max(300000, Number(task.timeoutSeconds || 900) * 1000);
    const ready = await waitFor(() => videoOverviewReady(), timeoutMs, 3000);
    if (!ready) throw new Error("VIDEO_OVERVIEW_GENERATION_TIMEOUT_OR_PLAYER_NOT_FOUND");

    return {
      resultText:"VIDEO_OVERVIEW_READY",
      resultUrls:[location.href],
      captureMode:"VIDEO_PLAYER_READY",
      notebookUrl:location.href,
      pageTitle:document.title,
      capturedAt:new Date().toISOString(),
      status:"DONE",
      taskId:task.taskId,
      contentId:task.contentId || "",
      taskType:task.taskType || "VIDEO_OVERVIEW",
      source:{...source, existingNotebookFallback: sourceFallback}
    };
  }

  function reportCandidates() {
    const out = [];
    const seen = new Set();
    for (const el of deepQueryAll("section,article,div,[role=group],[role=region],button,[role=button]").filter(visible)) {
      const t = (el.innerText || el.textContent || "").trim();
      const n = norm(t);
      if (!t || t.length > 12000 || seen.has(t)) continue;
      const reportLabel = /보고서|report|브리핑 문서|briefing document|briefing doc|학습 가이드|study guide|faq|자주 묻는 질문/.test(n);
      const reportArtifactSignal = /소스\s*\d+개|sources?\s*\d+|읽지 않음|unread|more_vert|다운로드|download|briefing doc/.test(n);
      const studioMenuHits = ["ai 오디오 오버뷰","슬라이드 자료","동영상 개요","마인드맵","보고서","플래시카드","퀴즈","인포그래픽","데이터 표"].filter(w => n.includes(w)).length;
      if (reportLabel && reportArtifactSignal && studioMenuHits < 5) {
        seen.add(t); out.push(t);
      }
    }
    return out;
  }

  function reportReady(baseline) {
    const current = reportCandidates();
    const fresh = current.filter(t => !baseline.has(t));
    return fresh.find(t => {
      const n = norm(t);
      return t.length > 20 && !/생성 중|generating|만드는 중|create|생성하기/.test(n);
    }) || null;
  }

  async function runReport(task) {
    const source = await addSource(task);
    const sourceFallback = !source.ok && Boolean(task.sourceText);

    const studio = findDeepControl(["studio","스튜디오"]);
    if (studio) { try { studio.click(); } catch {} await sleep(1200); }

    const baseline = new Set(reportCandidates());
    const reportControl = await waitFor(() => findDeepControl(["보고서","reports","report"]), 30000, 500);
    if (!reportControl) throw new Error(`REPORT_CONTROL_NOT_FOUND: ${location.href}`);
    try { reportControl.click(); } catch {}
    await sleep(1000);

    let typeControl = null;
    for (const d of dialogs()) {
      typeControl = findButton(["브리핑 문서","briefing document","브리핑","briefing"], d);
      if (typeControl) break;
    }
    if (!typeControl) typeControl = findDeepControl(["브리핑 문서","briefing document","브리핑","briefing"]);
    if (typeControl) { try { typeControl.click(); } catch {} await sleep(900); }

    let generate = null;
    for (const d of dialogs()) {
      generate = findButton(["생성","만들기","generate","create"], d);
      if (generate) break;
    }
    if (!generate) generate = findDeepControl(["생성","만들기","generate","create"]);
    if (generate) { try { generate.click(); } catch {} await sleep(1000); }

    const timeoutMs = Math.max(120000, Number(task.timeoutSeconds || 300) * 1000);
    const ready = await waitFor(() => reportReady(baseline), timeoutMs, 1800);
    if (!ready) throw new Error("REPORT_GENERATION_TIMEOUT_OR_RESULT_NOT_FOUND");

    return {
      resultText:ready,
      resultUrls:[location.href],
      captureMode:"REPORT_RESULT_READY",
      reportType:"BRIEFING_DOCUMENT",
      notebookUrl:location.href,
      pageTitle:document.title,
      capturedAt:new Date().toISOString(),
      status:"DONE",
      taskId:task.taskId,
      contentId:task.contentId || "",
      taskType:task.taskType || "REPORT",
      source:{...source, existingNotebookFallback: sourceFallback}
    };
  }

  function dataTableEvidence() {
    for (const el of deepQueryAll("table,[role=table],[role=grid]").filter(visible)) {
      const t = (el.innerText || el.textContent || "").trim();
      if (t.length > 20) return t;
    }
    const nodes = deepQueryAll("section,article,div,[role=group],[role=region]").filter(visible);
    for (const el of nodes) {
      const t = (el.innerText || el.textContent || "").trim();
      const n = norm(t);
      if ((n.includes("데이터 표") || n.includes("data table")) && t.length > 60 && !/생성 중|generating|만드는 중/.test(n)) return t;
    }
    return null;
  }

  async function runDataTable(task) {
    const source = await addSource(task);
    const sourceFallback = !source.ok && Boolean(task.sourceText);
    const studio = findDeepControl(["studio","스튜디오"]);
    if (studio) { try { studio.click(); } catch {} await sleep(1200); }
    const before = dataTableEvidence();
    const control = await waitFor(() => findDeepControl(["데이터 표","data table","데이터 테이블"]), 30000, 500);
    if (!control) throw new Error(`DATA_TABLE_CONTROL_NOT_FOUND: ${location.href}`);
    try { control.click(); } catch {}
    await sleep(1000);
    let generate = null;
    for (const d of dialogs()) { generate = findButton(["생성","만들기","generate","create"], d); if (generate) break; }
    if (generate) { try { generate.click(); } catch {} }
    const timeoutMs = Math.max(90000, Number(task.timeoutSeconds || 180) * 1000);
    const ready = await waitFor(() => { const x = dataTableEvidence(); return x && x !== before ? x : null; }, timeoutMs, 1500);
    if (!ready) throw new Error("DATA_TABLE_GENERATION_TIMEOUT_OR_RESULT_NOT_FOUND");
    return { resultText:ready, resultUrls:[location.href], captureMode:"DATA_TABLE_READY", notebookUrl:location.href, pageTitle:document.title, capturedAt:new Date().toISOString(), status:"DONE", taskId:task.taskId, contentId:task.contentId || "", taskType:task.taskType || "DATA_TABLE", source:{...source, existingNotebookFallback:sourceFallback} };
  }

  function studioArtifactCandidates(words) {
    const out = []; const seen = new Set();
    for (const el of deepQueryAll("section,article,div,[role=group],[role=region],button,[role=button]").filter(visible)) {
      const t = (el.innerText || el.textContent || "").trim();
      if (!t || t.length < 8 || t.length > 12000 || seen.has(t)) continue;
      const n = norm(t);
      if (!words.some(w => n.includes(norm(w)))) continue;
      if (/생성 중|generating|creating|만드는 중|준비 중|preparing/.test(n)) continue;
      const studioMenuHits = ["ai 오디오 오버뷰","슬라이드 자료","동영상 개요","마인드맵","보고서","플래시카드","퀴즈","인포그래픽","데이터 표"].filter(x => n.includes(x)).length;
      if (studioMenuHits >= 4) continue;
      const artifactSignal = /소스\s*\d+개|sources?\s*\d+|읽지 않음|unread|다운로드|download|more_vert|재생|play|\b\d{1,2}:\d{2}\b/.test(n);
      if (artifactSignal) { seen.add(t); out.push(t); }
    }
    return out;
  }

  async function runStudioArtifact(task, spec) {
    const source = await addSource(task);
    const sourceFallback = !source.ok && Boolean(task.sourceText);
    const studio = findDeepControl(["studio","스튜디오"]);
    if (studio) { try { studio.click(); } catch {} await sleep(1000); }
    const baseline = new Set(studioArtifactCandidates(spec.evidenceWords));
    const control = await waitFor(() => findDeepControl(spec.controlWords), 30000, 500);
    if (!control) throw new Error(`${spec.code}_CONTROL_NOT_FOUND: ${location.href}`);
    try { control.click(); } catch {} await sleep(1000);
    let generate = null;
    for (const d of dialogs()) { generate = findButton(["생성","만들기","generate","create"], d); if (generate) break; }
    if (!generate) generate = findDeepControl(["생성","만들기","generate","create"]);
    if (generate) { try { generate.click(); } catch {} await sleep(900); }
    const timeoutMs = Math.max(spec.minTimeoutMs, Number(task.timeoutSeconds || spec.defaultTimeoutSec) * 1000);
    const ready = await waitFor(() => studioArtifactCandidates(spec.evidenceWords).find(t => !baseline.has(t)) || null, timeoutMs, spec.pollMs);
    if (!ready) throw new Error(`${spec.code}_GENERATION_TIMEOUT_OR_RESULT_NOT_FOUND`);
    return {resultText:ready,resultUrls:[location.href],captureMode:`${spec.code}_READY`,artifactType:spec.code,notebookUrl:location.href,pageTitle:document.title,capturedAt:new Date().toISOString(),status:"DONE",taskId:task.taskId,contentId:task.contentId||"",taskType:task.taskType||spec.code,source:{...source,existingNotebookFallback:sourceFallback}};
  }

  const STUDIO_ARTIFACT_SPECS = Object.freeze({
    SLIDES:{code:"SLIDES",controlWords:["슬라이드 자료","slide deck","slides"],evidenceWords:["슬라이드 자료","slide deck","slides"],defaultTimeoutSec:300,minTimeoutMs:120000,pollMs:1800},
    MIND_MAP:{code:"MIND_MAP",controlWords:["마인드맵","mind map"],evidenceWords:["마인드맵","mind map"],defaultTimeoutSec:180,minTimeoutMs:60000,pollMs:1200},
    FLASHCARDS:{code:"FLASHCARDS",controlWords:["플래시카드","flashcards","flash cards"],evidenceWords:["플래시카드","flashcards","flash cards"],defaultTimeoutSec:180,minTimeoutMs:60000,pollMs:1200},
    QUIZ:{code:"QUIZ",controlWords:["퀴즈","quiz"],evidenceWords:["퀴즈","quiz"],defaultTimeoutSec:180,minTimeoutMs:60000,pollMs:1200},
    INFOGRAPHIC:{code:"INFOGRAPHIC",controlWords:["인포그래픽","infographic"],evidenceWords:["인포그래픽","infographic"],defaultTimeoutSec:300,minTimeoutMs:120000,pollMs:1800}
  });

  async function runTask(task) {
    if (!HOSTS.has(location.hostname)) throw new Error("NotebookLM 페이지가 아닙니다.");
    if (!task?.taskId) throw new Error("TASK_ID가 없습니다.");

    const normalizedTaskType = String(task.taskType || "CHAT").toUpperCase();
    if (["AUDIO","AUDIO_OVERVIEW","NOTEBOOKLM_AUDIO"].includes(normalizedTaskType)) return runAudioOverview(task);

    if (["VIDEO","VIDEO_OVERVIEW","NOTEBOOKLM_VIDEO"].includes(normalizedTaskType)) return runVideoOverview(task);

    if (["REPORT","NOTEBOOKLM_REPORT","NOTEBOOKLM_REPORT_PDF"].includes(normalizedTaskType)) return runReport(task);

    if (["DATA_TABLE","NOTEBOOKLM_DATA_TABLE"].includes(normalizedTaskType)) return runDataTable(task);

    if (["SLIDES","SLIDE_DECK","NOTEBOOKLM_SLIDES"].includes(normalizedTaskType)) return runStudioArtifact(task, STUDIO_ARTIFACT_SPECS.SLIDES);

    if (["MIND_MAP","MINDMAP","NOTEBOOKLM_MIND_MAP"].includes(normalizedTaskType)) return runStudioArtifact(task, STUDIO_ARTIFACT_SPECS.MIND_MAP);

    if (["FLASHCARDS","FLASHCARD","NOTEBOOKLM_FLASHCARDS"].includes(normalizedTaskType)) return runStudioArtifact(task, STUDIO_ARTIFACT_SPECS.FLASHCARDS);

    if (["QUIZ","NOTEBOOKLM_QUIZ"].includes(normalizedTaskType)) return runStudioArtifact(task, STUDIO_ARTIFACT_SPECS.QUIZ);

    if (["INFOGRAPHIC","NOTEBOOKLM_INFOGRAPHIC"].includes(normalizedTaskType)) return runStudioArtifact(task, STUDIO_ARTIFACT_SPECS.INFOGRAPHIC);

    const source = await addSource(task);
    const editor = await ensureChatSurface();
    if (!editor) throw new Error(`NotebookLM 채팅 입력창을 찾지 못했습니다: ${location.href} | ${document.title}`);

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
