(() => {
  if (globalThis.__NLM_FRESH_NOTEBOOK_CREATE_LOADED__) return;
  globalThis.__NLM_FRESH_NOTEBOOK_CREATE_LOADED__ = true;

  const SOURCE = "notebooklm-webapp-bridge";
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const norm = (v) => String(v || "").replace(/\s+/g, " ").trim().toLowerCase();

  function visible(el) {
    if (!(el instanceof HTMLElement)) return false;
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return s.display !== "none" && s.visibility !== "hidden" && r.width > 2 && r.height > 2;
  }

  function controls() {
    return [...document.querySelectorAll("button,[role='button'],a,[tabindex]")].filter(visible);
  }

  function label(el) {
    return norm([
      el?.innerText,
      el?.textContent,
      el?.getAttribute?.("aria-label"),
      el?.getAttribute?.("title"),
      el?.getAttribute?.("data-testid")
    ].join(" "));
  }

  function findControl(words) {
    const wanted = words.map(norm);
    return controls().find((el) => {
      const t = label(el);
      return wanted.some((w) => t === w || t.includes(w));
    }) || null;
  }

  async function waitFor(factory, timeoutMs = 30000, intervalMs = 350) {
    const started = Date.now();
    while (Date.now() - started < timeoutMs) {
      try {
        const found = factory();
        if (found) return found;
      } catch {}
      await sleep(intervalMs);
    }
    return null;
  }

  function notebookIdFromUrl(url = location.href) {
    const m = String(url || "").match(/\/notebook\/([a-z0-9-]+)/i);
    return m ? m[1] : "";
  }

  function sourceDialogs() {
    return [...document.querySelectorAll("[role='dialog'],dialog")].filter(visible);
  }

  function findIn(root, words) {
    const wanted = words.map(norm);
    return [...root.querySelectorAll("button,[role='button'],a,[tabindex],div,span")]
      .filter(visible)
      .map((el) => ({ el, text: label(el) }))
      .filter((x) => x.text && x.text.length < 500 && wanted.some((w) => x.text === w || x.text.includes(w)))
      .sort((a, b) => a.text.length - b.text.length)[0]?.el || null;
  }

  function fillEditor(el, text) {
    el.focus();
    if (el instanceof HTMLTextAreaElement || el instanceof HTMLInputElement) {
      const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const setter = Object.getOwnPropertyDescriptor(proto, "value")?.set;
      setter?.call(el, text);
      el.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
      return;
    }
    const sel = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(el);
    sel?.removeAllRanges();
    sel?.addRange(range);
    document.execCommand("insertText", false, text);
    el.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text }));
    sel?.removeAllRanges();
  }

  async function addFreshSource(sourceText) {
    if (!String(sourceText || "").trim()) return { ok: true, skipped: true, reason: "NO_SOURCE_TEXT" };

    let choice = null;
    for (const d of sourceDialogs()) {
      choice = findIn(d, ["복사된 텍스트", "복사한 텍스트", "붙여넣은 텍스트", "copied text", "paste text"]);
      if (choice) break;
    }

    if (!choice) {
      const add = findControl(["소스 추가", "자료 추가", "출처 추가", "add source", "add sources"]);
      if (!add) return { ok: false, reason: "ADD_SOURCE_CONTROL_NOT_FOUND" };
      add.click();
      choice = await waitFor(() => {
        for (const d of sourceDialogs()) {
          const x = findIn(d, ["복사된 텍스트", "복사한 텍스트", "붙여넣은 텍스트", "copied text", "paste text"]);
          if (x) return x;
        }
        return null;
      }, 20000);
    }

    if (!choice) return { ok: false, reason: "PASTED_TEXT_SOURCE_TYPE_NOT_FOUND" };
    choice.click();

    const editor = await waitFor(() => {
      for (const d of sourceDialogs()) {
        const list = [...d.querySelectorAll("textarea,[contenteditable='true'][role='textbox'],[contenteditable='true']")].filter(visible);
        if (list.length) return list.at(-1);
      }
      return null;
    }, 20000);
    if (!editor) return { ok: false, reason: "SOURCE_EDITOR_NOT_FOUND" };

    fillEditor(editor, sourceText);
    const save = await waitFor(() => {
      for (const d of sourceDialogs()) {
        const x = findIn(d, ["삽입", "추가", "저장", "완료", "insert", "add", "save", "submit"]);
        if (x) return x;
      }
      return null;
    }, 15000);
    if (!save) return { ok: false, reason: "SOURCE_SAVE_CONTROL_NOT_FOUND" };
    save.click();
    await sleep(2500);
    return { ok: true };
  }

  async function renameNotebook(title) {
    const wanted = String(title || "").trim();
    if (!wanted) return { ok: true, skipped: true };
    const candidates = [
      ...document.querySelectorAll("editable-project-title,input[aria-label*='title' i],input[aria-label*='제목'],[contenteditable='true']")
    ].filter(visible);
    const el = candidates.find((x) => {
      const t = norm([x.getAttribute?.("aria-label"), x.getAttribute?.("title"), x.tagName].join(" "));
      return /title|제목|editable-project-title/.test(t);
    }) || document.querySelector("editable-project-title");
    if (!el || !visible(el)) return { ok: false, reason: "TITLE_EDITOR_NOT_FOUND" };
    try {
      el.click();
      await sleep(300);
      const input = [...document.querySelectorAll("input,textarea,[contenteditable='true']")].filter(visible).at(-1) || el;
      fillEditor(input, wanted);
      input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true }));
      input.dispatchEvent(new KeyboardEvent("keyup", { key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true }));
      await sleep(700);
      return { ok: true, title: wanted };
    } catch (error) {
      return { ok: false, reason: String(error) };
    }
  }

  async function createFreshNotebook(task) {
    const type = String(task?.taskType || "").toUpperCase();
    if (!["FRESH_NOTEBOOK_CREATE", "NOTEBOOK_CREATE", "NEW_NOTEBOOK"].includes(type)) {
      throw new Error("FRESH_NOTEBOOK_HANDLER_WRONG_TASK_TYPE");
    }

    const oldId = notebookIdFromUrl();
    if (oldId) {
      location.href = "https://notebook.google.com/";
      await waitFor(() => !notebookIdFromUrl() && document.readyState === "complete" ? document.body : null, 30000, 500);
    }

    const create = await waitFor(() => findControl([
      "노트북 만들기", "새 노트북", "새 노트북 만들기", "create notebook", "new notebook", "create new"
    ]), 30000, 500);
    if (!create) throw new Error(`FRESH_NOTEBOOK_CREATE_CONTROL_NOT_FOUND:${location.href}`);

    const clickedAt = new Date().toISOString();
    create.click();

    const newId = await waitFor(() => notebookIdFromUrl(), Math.max(45000, Number(task.timeoutSeconds || 90) * 1000), 500);
    if (!newId) throw new Error(`FRESH_NOTEBOOK_URL_NOT_CREATED:${location.href}`);
    const newUrl = location.href;
    if (oldId && oldId === newId) throw new Error(`FRESH_NOTEBOOK_REUSED_OLD_ID:${newId}`);

    await sleep(1500);
    const titleResult = await renameNotebook(task.title || task.contentId || task.taskId);
    const source = await addFreshSource(task.sourceText || "");
    if (!source.ok) throw new Error(`FRESH_NOTEBOOK_SOURCE_ADD_FAILED:${source.reason || "UNKNOWN"}`);

    return {
      status: "DONE",
      resultText: "FRESH_NOTEBOOK_CREATED",
      captureMode: "FRESH_NOTEBOOK_ID_CREATED_AND_SOURCE_ADDED",
      notebookUrl: newUrl,
      notebookId: newId,
      previousNotebookId: oldId || "",
      freshNotebook: true,
      createdAt: clickedAt,
      capturedAt: new Date().toISOString(),
      pageTitle: document.title,
      titleResult,
      source,
      taskId: task.taskId,
      contentId: task.contentId || "",
      taskType: type
    };
  }

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || message.source !== SOURCE || message.type !== "RUN_NOTEBOOK_TASK") return false;
    const type = String(message.task?.taskType || "").toUpperCase();
    if (!["FRESH_NOTEBOOK_CREATE", "NOTEBOOK_CREATE", "NEW_NOTEBOOK"].includes(type)) return false;

    createFreshNotebook(message.task)
      .then((result) => sendResponse({ ok: true, result }))
      .catch((error) => sendResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }));
    return true;
  });
})();
