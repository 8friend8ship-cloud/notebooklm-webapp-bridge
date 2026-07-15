const SOURCE = "notebooklm-webapp-bridge";
const CONFIG_KEY = "nlmBridgeConfig";
const LOG_KEY = "nlmBridgeLogs";
const MAX_LOGS = 100;

const DEFAULT_CONFIG = Object.freeze({
  appsScriptUrl: "",
  frontendOrigin: "",
  notebookHomeUrl: "https://notebooklm.google.com/"
});

async function configureSidePanel() {
  await chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true });
}

async function getConfig() {
  const stored = await chrome.storage.local.get(CONFIG_KEY);
  return { ...DEFAULT_CONFIG, ...(stored[CONFIG_KEY] || {}) };
}

async function saveConfig(patch) {
  const current = await getConfig();
  const next = { ...current, ...patch };
  await chrome.storage.local.set({ [CONFIG_KEY]: next });
  return next;
}

async function addLog(level, message, details = {}) {
  const stored = await chrome.storage.local.get(LOG_KEY);
  const logs = Array.isArray(stored[LOG_KEY]) ? stored[LOG_KEY] : [];
  logs.unshift({ level, message, details, createdAt: new Date().toISOString() });
  await chrome.storage.local.set({ [LOG_KEY]: logs.slice(0, MAX_LOGS) });
}

function senderOrigin(sender) {
  try { return new URL(sender.url || sender.origin || "").origin; }
  catch { return ""; }
}

function isManifestAllowedOrigin(origin) {
  return origin === "http://localhost" ||
    origin === "http://127.0.0.1" ||
    /^https:\/\/[a-z0-9-]+\.vercel\.app$/i.test(origin);
}

async function assertTrustedSender(sender) {
  const origin = senderOrigin(sender);
  if (!origin || !isManifestAllowedOrigin(origin)) {
    throw new Error(`허용되지 않은 프런트앱입니다: ${origin || "unknown"}`);
  }
  const config = await getConfig();
  if (config.frontendOrigin && origin !== config.frontendOrigin) {
    throw new Error(`등록된 프런트앱 주소와 다릅니다: ${origin}`);
  }
  return origin;
}

async function apiPost(url, payload) {
  if (!/^https:\/\/script\.google\.com\/macros\/s\//.test(url || "")) {
    throw new Error("올바른 Apps Script 배포 URL이 설정되지 않았습니다.");
  }
  const response = await fetch(url, {
    method: "POST",
    redirect: "follow",
    headers: { "Content-Type": "text/plain;charset=utf-8" },
    body: JSON.stringify(payload)
  });
  if (!response.ok) throw new Error(`Apps Script 요청 실패: HTTP ${response.status}`);
  const data = await response.json();
  if (!data.ok) throw new Error(data.error || "Apps Script 작업 실패");
  return data;
}

async function getChromeProfile() {
  try {
    const info = await chrome.identity.getProfileUserInfo({ accountStatus: "ANY" });
    return { email: info.email || "", id: info.id || "" };
  } catch (error) {
    return { email: "", id: "", error: String(error) };
  }
}

async function findOrOpenNotebookTab(url) {
  const targetUrl = /^https:\/\/notebooklm\.google\.com\//.test(url || "")
    ? url : "https://notebooklm.google.com/";
  const tabs = await chrome.tabs.query({ url: "https://notebooklm.google.com/*" });
  let tab = tabs.find((item) => item.active) || tabs[0];
  if (!tab) tab = await chrome.tabs.create({ url: targetUrl, active: true });
  else {
    if (targetUrl !== "https://notebooklm.google.com/" && tab.url !== targetUrl) {
      tab = await chrome.tabs.update(tab.id, { url: targetUrl, active: true });
    } else {
      tab = await chrome.tabs.update(tab.id, { active: true });
    }
  }
  if (!tab?.id) throw new Error("NotebookLM 탭을 열지 못했습니다.");
  return tab;
}

async function waitForTab(tabId, timeoutMs = 45000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const tab = await chrome.tabs.get(tabId);
    if (tab.status === "complete") return tab;
    await new Promise((resolve) => setTimeout(resolve, 600));
  }
  throw new Error("NotebookLM 페이지 로딩 시간이 초과되었습니다.");
}

async function sendToNotebook(tabId, message) {
  try {
    return await chrome.tabs.sendMessage(tabId, message);
  } catch {
    await chrome.scripting.executeScript({ target: { tabId }, files: ["content/notebooklm-runner.js"] });
    return chrome.tabs.sendMessage(tabId, message);
  }
}

async function updateTask(apiUrl, sessionToken, taskId, status, patch = {}) {
  return apiPost(apiUrl, { action: "updateTask", sessionToken, taskId, status, patch });
}

async function runTask({ apiUrl, sessionToken, taskId, frontendOrigin }) {
  if (!sessionToken || !taskId) throw new Error("sessionToken과 taskId가 필요합니다.");
  const profile = await getChromeProfile();
  const claimed = await apiPost(apiUrl, {
    action: "claimTask",
    sessionToken,
    taskId,
    chromeProfileEmail: profile.email
  });
  const task = claimed.task;
  await saveConfig(frontendOrigin ? { appsScriptUrl: apiUrl, frontendOrigin } : { appsScriptUrl: apiUrl });
  await addLog("info", "작업을 수령했습니다.", { taskId, taskType: task.taskType });

  try {
    const tab = await findOrOpenNotebookTab(task.notebookUrl);
    await updateTask(apiUrl, sessionToken, taskId, "NOTEBOOK_OPENED", { notebookTabId: tab.id });
    await waitForTab(tab.id);

    const response = await sendToNotebook(tab.id, {
      source: SOURCE,
      type: "RUN_NOTEBOOK_TASK",
      task
    });
    if (!response?.ok) throw new Error(response?.error || "NotebookLM 실행에 실패했습니다.");

    const completed = await apiPost(apiUrl, {
      action: "completeTask",
      sessionToken,
      taskId,
      result: response.result || {}
    });
    await addLog("info", "작업이 완료되었습니다.", { taskId, result: completed.result });
    return { taskId, profile, result: completed.result };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    try { await updateTask(apiUrl, sessionToken, taskId, "ERROR", { error: message }); } catch {}
    await addLog("error", "작업 실행 실패", { taskId, error: message });
    throw error;
  }
}

async function handleExternal(message, sender) {
  const origin = await assertTrustedSender(sender);
  if (!message || message.source !== SOURCE) throw new Error("잘못된 메시지 출처입니다.");

  if (message.type === "PING") {
    return { ok: true, version: chrome.runtime.getManifest().version, origin, profile: await getChromeProfile() };
  }
  if (message.type === "RUN_TASK") {
    const result = await runTask({ ...message, frontendOrigin: origin });
    return { ok: true, ...result };
  }
  if (message.type === "GET_PROFILE") return { ok: true, profile: await getChromeProfile() };
  throw new Error("지원되지 않는 외부 요청입니다.");
}

chrome.runtime.onMessageExternal.addListener((message, sender, sendResponse) => {
  handleExternal(message, sender)
    .then(sendResponse)
    .catch(async (error) => {
      await addLog("error", error instanceof Error ? error.message : String(error));
      sendResponse({ ok: false, error: error instanceof Error ? error.message : String(error) });
    });
  return true;
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  (async () => {
    if (message?.source !== SOURCE) return { ok: false, error: "잘못된 메시지입니다." };
    if (message.type === "GET_CONFIG") return { ok: true, config: await getConfig(), profile: await getChromeProfile() };
    if (message.type === "SAVE_CONFIG") return { ok: true, config: await saveConfig(message.config || {}) };
    if (message.type === "GET_LOGS") {
      const stored = await chrome.storage.local.get(LOG_KEY);
      return { ok: true, logs: stored[LOG_KEY] || [] };
    }
    if (message.type === "TEST_API") {
      const config = await getConfig();
      return { ok: true, response: await apiPost(config.appsScriptUrl, { action: "health" }) };
    }
    return { ok: false, error: "지원되지 않는 내부 요청입니다." };
  })().then(sendResponse).catch((error) => sendResponse({ ok: false, error: String(error) }));
  return true;
});

chrome.runtime.onInstalled.addListener(() => configureSidePanel().catch(console.error));
chrome.runtime.onStartup.addListener(() => configureSidePanel().catch(console.error));
