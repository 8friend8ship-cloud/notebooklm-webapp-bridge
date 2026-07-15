(() => {
  if (globalThis.__NLM_WEBAPP_BRIDGE_LOADED__) return;
  globalThis.__NLM_WEBAPP_BRIDGE_LOADED__ = true;

  const SOURCE = "notebooklm-webapp-bridge";
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const normalize = (value) => String(value || "").replace(/\s+/g, " ").trim().toLowerCase();

  function visible(element) {
    if (!(element instanceof HTMLElement)) return false;
    const style = getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return style.display !== "none" && style.visibility !== "hidden" && rect.width > 2 && rect.height > 2;
  }

  function findEditor() {
    const selectors = [
      "textarea",
      "[contenteditable='true'][role='textbox']",
      "[contenteditable='true']"
    ];
    for (const selector of selectors) {
      const items = [...document.querySelectorAll(selector)].filter(visible);
      if (items.length) return items.at(-1);
    }
    return null;
  }

  function setNativeValue(element, value) {
    const proto = element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, "value")?.set;
    setter?.call(element, value);
  }

  function fillEditor(element, text) {
    element.focus();
    if (element instanceof HTMLTextAreaElement || element instanceof HTMLInputElement) {
      setNativeValue(element, text);
      element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text }));
      element.dispatchEvent(new Event("change", { bubbles: true }));
      return;
    }
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(element);
    selection?.removeAllRanges();
    selection?.addRange(range);
    document.execCommand("insertText", false, text);
    element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text }));
    selection?.removeAllRanges();
  }

  async function waitForEditor(timeoutMs = 30000) {
    const started = Date.now();
    while (Date.now() - started < timeoutMs) {
      const editor = findEditor();
      if (editor) return editor;
      await sleep(500);
    }
    throw new Error("NotebookLM 입력창을 찾지 못했습니다. 노트북이 열린 상태인지 확인해 주세요.");
  }

  function findButton(words) {
    const candidates = [...document.querySelectorAll("button,[role='button']")].filter(visible);
    return candidates.find((element) => {
      const haystack = normalize([
        element.innerText,
        element.textContent,
        element.getAttribute("aria-label"),
        element.getAttribute("title")
      ].join(" "));
      return words.some((word) => haystack.includes(normalize(word)));
    }) || null;
  }


  async function waitForElement(factory, timeoutMs = 12000) {
    const started = Date.now();
    while (Date.now() - started < timeoutMs) {
      const element = factory();
      if (element) return element;
      await sleep(350);
    }
    return null;
  }

  function editorsInDialog() {
    const dialogs = [...document.querySelectorAll("[role='dialog'],dialog")].filter(visible);
    const roots = dialogs.length ? dialogs : [document];
    const found = [];
    for (const root of roots) {
      for (const element of root.querySelectorAll("textarea,[contenteditable='true'][role='textbox'],[contenteditable='true']")) {
        if (visible(element)) found.push(element);
      }
    }
    return found;
  }

  async function addPastedTextSource(task) {
    if (!task.sourceText) return { ok: false, skipped: true, reason: "sourceText 없음" };
    const addButton = findButton(["소스 추가", "자료 추가", "add source", "add sources", "source"]);
    if (!addButton) return { ok: false, reason: "소스 추가 버튼을 찾지 못했습니다." };
    addButton.click();

    const textChoice = await waitForElement(() => findButton([
      "복사한 텍스트", "붙여넣은 텍스트", "copied text", "paste text", "text"
    ]));
    if (textChoice) textChoice.click();

    const editor = await waitForElement(() => editorsInDialog().at(-1));
    if (!editor) return { ok: false, reason: "소스 텍스트 입력창을 찾지 못했습니다." };
    fillEditor(editor, task.sourceText);

    const titleInput = [...document.querySelectorAll("[role='dialog'] input,dialog input")]
      .filter(visible)
      .find((element) => normalize(element.placeholder).includes("title") || normalize(element.getAttribute("aria-label")).includes("제목"));
    if (titleInput && task.title) {
      setNativeValue(titleInput, task.title);
      titleInput.dispatchEvent(new InputEvent("input", { bubbles: true, data: task.title }));
    }

    const confirm = await waitForElement(() => findButton([
      "삽입", "추가", "저장", "완료", "insert", "add", "save", "submit"
    ]));
    if (!confirm) return { ok: false, reason: "소스 저장 버튼을 찾지 못했습니다." };
    confirm.click();
    await sleep(1200);
    return { ok: true };
  }

  function buildPrompt(task, sourceAdded) {
    const sections = [
      `[TASK_ID] ${task.taskId}`,
      `[CONTENT_ID] ${task.contentId || ""}`,
      `[작업 유형] ${task.taskType || "CHAT"}`,
      `[언어] ${task.language || "ko-KR"}`,
      "",
      "[NotebookLM 작업 지시서]",
      task.instruction || "원문의 사실과 흐름을 유지해서 요청된 결과물을 만들어 주세요.",
      ...(sourceAdded ? [] : ["", "[작가 웹앱 마스터 원문]", task.sourceText || ""])
    ];
    return sections.join("\n").trim();
  }

  async function submitEditor() {
    const button = findButton(["보내기", "제출", "send", "submit", "질문"]);
    if (!button) throw new Error("NotebookLM 전송 버튼을 찾지 못했습니다.");
    button.click();
  }

  const studioWords = {
    AUDIO_OVERVIEW: ["오디오 개요", "audio overview", "오디오"],
    VIDEO_OVERVIEW: ["동영상 개요", "video overview", "동영상", "video"],
    SLIDE_DECK: ["슬라이드 자료", "slide deck", "슬라이드"],
    QUIZ: ["퀴즈", "quiz"],
    MIND_MAP: ["마인드맵", "mind map"]
  };

  async function tryStudioAction(taskType) {
    const words = studioWords[taskType];
    if (!words) return { attempted: false };
    const button = findButton(words);
    if (!button) return { attempted: true, clicked: false, warning: `${taskType} 생성 버튼을 찾지 못했습니다.` };
    button.click();
    return { attempted: true, clicked: true };
  }

  function captureResult() {
    const selected = window.getSelection()?.toString().trim() || "";
    const candidates = [...document.querySelectorAll("article,[role='article'],[class*='answer'],[class*='response']")]
      .filter(visible)
      .map((element) => (element.innerText || element.textContent || "").trim())
      .filter((text) => text.length >= 30 && text.length <= 50000);
    const urls = [...document.querySelectorAll("a[href]")]
      .filter(visible)
      .map((a) => a.href)
      .filter((url) => /^https?:\/\//.test(url))
      .slice(-30);
    return {
      resultText: selected || candidates.at(-1) || "",
      resultUrls: [...new Set(urls)],
      notebookUrl: location.href,
      pageTitle: document.title,
      capturedAt: new Date().toISOString()
    };
  }

  async function waitForResult(initialText, timeoutMs) {
    const started = Date.now();
    let last = captureResult();
    while (Date.now() - started < timeoutMs) {
      await sleep(2000);
      last = captureResult();
      if (last.resultText && last.resultText !== initialText) return last;
      const body = normalize(document.body.innerText);
      if (!body.includes("생성 중") && !body.includes("generating") && last.resultUrls.length) return last;
    }
    return { ...last, warning: "완료 감지 시간이 초과되어 현재 화면 결과만 저장했습니다." };
  }

  async function runTask(task) {
    if (location.hostname !== "notebooklm.google.com") throw new Error("NotebookLM 페이지가 아닙니다.");
    if (!task?.taskId) throw new Error("TASK_ID가 없습니다.");

    const source = await addPastedTextSource(task);
    const editor = await waitForEditor();
    const initial = captureResult().resultText;
    fillEditor(editor, buildPrompt(task, source.ok));

    if (task.autoSubmit !== false) await submitEditor();
    const studio = await tryStudioAction(task.taskType);
    const result = task.autoSubmit === false
      ? { ...captureResult(), status: "PREPARED", warning: "자동 제출이 꺼져 있어 입력까지만 완료했습니다." }
      : await waitForResult(initial, Number(task.timeoutSeconds || 180) * 1000);

    return {
      ...result,
      status: "DONE",
      taskId: task.taskId,
      contentId: task.contentId || "",
      taskType: task.taskType || "CHAT",
      studio,
      source
    };
  }

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || message.source !== SOURCE || message.type !== "RUN_NOTEBOOK_TASK") return false;
    runTask(message.task)
      .then((result) => sendResponse({ ok: true, result }))
      .catch((error) => sendResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }));
    return true;
  });
})();
