const SOURCE = "notebooklm-webapp-bridge";
const CONFIG_KEY = "nlmBridgeConfig";
const LOG_KEY = "nlmBridgeLogs";
const AUTO_STATE_KEY = "nlmAutoRunnerStateV025";
const SESSION_STORE_KEYS = ["homeDesignBridgeSessionV7", "nlmPersistentSessionV5"];
const MAX_LOGS = 200;
const NOTEBOOK_HOSTS = ["notebook.google.com", "notebooklm.google.com"];
const NOTEBOOK_HOME = "https://notebook.google.com/";
const POLL_ALARM = "nlm-auto-ready-poll";
const DEFAULT_POLL_MINUTES = 1;
const MAX_TASKS_PER_POLL = 2;
const CANONICAL_API = "https://script.google.com/macros/s/AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P/exec";

const DEFAULT_CONFIG = Object.freeze({
  appsScriptUrl: CANONICAL_API,
  frontendOrigin: "https://notebooklm-webapp-bridge.vercel.app",
  notebookHomeUrl: NOTEBOOK_HOME,
  autoRunEnabled: true,
  pollMinutes: DEFAULT_POLL_MINUTES
});

async function configureSidePanel() {
  if (!chrome.sidePanel) return;
  await chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true });
}

async function getConfig() {
  const stored = await chrome.storage.local.get(CONFIG_KEY);
  const saved = stored[CONFIG_KEY] || {};
  return { ...DEFAULT_CONFIG, ...saved, appsScriptUrl: saved.appsScriptUrl || CANONICAL_API };
}

async function saveConfig(patch) {
  const current = await getConfig();
  const next = { ...current, ...patch };
  await chrome.storage.local.set({ [CONFIG_KEY]: next });
  await ensureAutoAlarm(next);
  return next;
}

async function addLog(level, message, details = {}) {
  const stored = await chrome.storage.local.get(LOG_KEY);
  const logs = Array.isArray(stored[LOG_KEY]) ? stored[LOG_KEY] : [];
  logs.unshift({ level, message, details, createdAt: new Date().toISOString() });
  await chrome.storage.local.set({ [LOG_KEY]: logs.slice(0, MAX_LOGS) });
}

async function getAutoState() {
  const stored = await chrome.storage.local.get(AUTO_STATE_KEY);
  return {
    runningTaskId: "",
    busyUntil: 0,
    lastPollAt: "",
    lastSuccessAt: "",
    lastError: "",
    requiresLogin: false,
    ...(stored[AUTO_STATE_KEY] || {})
  };
}

async function saveAutoState(patch) {
  const current = await getAutoState();
  const next = { ...current, ...patch };
  await chrome.storage.local.set({ [AUTO_STATE_KEY]: next });
  return next;
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

function isNotebookUrl(url) {
  try {
    const parsed = new URL(String(url || ""));
    return parsed.protocol === "https:" && NOTEBOOK_HOSTS.includes(parsed.hostname);
  } catch {
    return false;
  }
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

async function getPersistedSessionToken() {
  const stored = await chrome.storage.local.get(SESSION_STORE_KEYS);
  for (const key of SESSION_STORE_KEYS) {
    const value = stored[key];
    const token = typeof value === "string" ? value : value?.token;
    if (token) return String(token);
  }
  return "";
}

async function findOrOpenNotebookTab(url) {
  const targetUrl = isNotebookUrl(url) ? url : NOTEBOOK_HOME;
  const tabs = await chrome.tabs.query({
    url: ["https://notebook.google.com/*", "https://notebooklm.google.com/*"]
  });
  let tab = tabs.find((item) => item.active) || tabs[0];
  if (!tab) {
    tab = await chrome.tabs.create({ url: targetUrl, active: true });
  } else if (tab.url !== targetUrl) {
    tab = await chrome.tabs.update(tab.id, { url: targetUrl, active: true });
  } else {
    tab = await chrome.tabs.update(tab.id, { active: true });
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

function isSessionError(message) {
  return /로그인 세션|세션.*만료|session/i.test(String(message || ""));
}

async function openControlCenter(config) {
  const base = String(config.frontendOrigin || DEFAULT_CONFIG.frontendOrigin || "").replace(/\/$/, "");
  if (!/^https:\/\//.test(base)) return;
  const tabs = await chrome.tabs.query({ url: `${base}/*` });
  if (tabs[0]?.id) {
    await chrome.tabs.update(tabs[0].id, { active: true, url: `${base}/` });
  } else {
    await chrome.tabs.create({ url: `${base}/`, active: true });
  }
}

async function pollReadyTasks(reason = "alarm") {
  const config = await getConfig();
  if (!config.autoRunEnabled) return { ok: true, skipped: "disabled" };
  if (!config.appsScriptUrl) return { ok: true, skipped: "api_not_configured" };

  const state = await getAutoState();
  if (Number(state.busyUntil || 0) > Date.now() && state.runningTaskId) {
    return { ok: true, skipped: "busy", runningTaskId: state.runningTaskId || "" };
  }
  if (Number(state.busyUntil || 0) > Date.now() && !state.runningTaskId) {
    await saveAutoState({ busyUntil: 0, lastError: "STALE_BUSY_CLEARED_D45" });
  }

  const sessionToken = await getPersistedSessionToken();
  if (!sessionToken) {
    await saveAutoState({ lastPollAt: new Date().toISOString(), requiresLogin: true, lastError: "NO_SESSION" });
    return { ok: true, skipped: "no_session" };
  }

  await saveAutoState({
    lastPollAt: new Date().toISOString(),
    requiresLogin: false,
    busyUntil: Date.now() + 10 * 60 * 1000
  });

  let processed = 0;
  try {
    const listed = await apiPost(config.appsScriptUrl, {
      action: "listTasks",
      sessionToken
    });
    const tasks = Array.isArray(listed.tasks) ? listed.tasks : [];
    const runnable = tasks.filter((task) =>
      ["READY", "RETRY"].includes(String(task.status || "READY").toUpperCase()) &&
      task.autoSubmit !== false &&
      !String(task.taskType || "").toUpperCase().startsWith("LOCAL_")
    );

    for (const task of runnable.slice(0, MAX_TASKS_PER_POLL)) {
      await saveAutoState({ runningTaskId: task.taskId, busyUntil: Date.now() + 10 * 60 * 1000 });
      await addLog("info", "자동 작업 시작", { reason, taskId: task.taskId });
      await runTask({
        apiUrl: config.appsScriptUrl,
        sessionToken,
        taskId: task.taskId,
        frontendOrigin: config.frontendOrigin
      });
      processed += 1;
      await saveAutoState({
        runningTaskId: "",
        lastSuccessAt: new Date().toISOString(),
        lastError: ""
      });
    }

    await saveAutoState({ runningTaskId: "", busyUntil: 0, requiresLogin: false });
    return { ok: true, processed, available: runnable.length };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await saveAutoState({ runningTaskId: "", busyUntil: 0, lastError: message, requiresLogin: isSessionError(message) });
    await addLog("error", "자동 폴링 실패", { reason, error: message });
    if (isSessionError(message)) await openControlCenter(config).catch(() => {});
    throw error;
  }
}

async function ensureAutoAlarm(config = null) {
  const current = config || await getConfig();
  await chrome.alarms.clear(POLL_ALARM);
  if (!current.autoRunEnabled) return;
  const minutes = Math.max(1, Number(current.pollMinutes || DEFAULT_POLL_MINUTES));
  await chrome.alarms.create(POLL_ALARM, { delayInMinutes: 0.25, periodInMinutes: minutes });
}

async function handleExternal(message, sender) {
  const origin = await assertTrustedSender(sender);
  if (!message || message.source !== SOURCE) throw new Error("잘못된 메시지 출처입니다.");

  if (message.type === "PING") {
    return {
      ok: true,
      version: chrome.runtime.getManifest().version,
      origin,
      profile: await getChromeProfile(),
      autoState: await getAutoState()
    };
  }
  if (message.type === "RUN_TASK") {
    const result = await runTask({ ...message, frontendOrigin: origin });
    return { ok: true, ...result };
  }
  if (message.type === "GET_PROFILE") return { ok: true, profile: await getChromeProfile() };
  if (message.type === "GET_AUTO_STATUS") return { ok: true, state: await getAutoState(), config: await getConfig() };
  if (message.type === "RUN_AUTO_POLL") return { ok: true, result: await pollReadyTasks("external") };
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
  if (message?.source === SOURCE && message?.type === "MIRROR_ARTIFACT_TO_DRIVE") return false;
  (async () => {
    if (message?.source !== SOURCE) return { ok: false, error: "잘못된 메시지입니다." };
    if (message.type === "GET_CONFIG") return { ok: true, config: await getConfig(), profile: await getChromeProfile(), autoState: await getAutoState() };
    if (message.type === "SAVE_CONFIG") return { ok: true, config: await saveConfig(message.config || {}) };
    if (message.type === "GET_LOGS") {
      const stored = await chrome.storage.local.get(LOG_KEY);
      return { ok: true, logs: stored[LOG_KEY] || [] };
    }
    if (message.type === "TEST_API") {
      const config = await getConfig();
      return { ok: true, response: await apiPost(config.appsScriptUrl, { action: "health" }) };
    }
    if (message.type === "RUN_AUTO_POLL") return { ok: true, result: await pollReadyTasks("internal") };
    if (message.type === "GET_AUTO_STATUS") return { ok: true, state: await getAutoState(), config: await getConfig() };
    return { ok: false, error: "지원되지 않는 내부 요청입니다." };
  })().then(sendResponse).catch((error) => sendResponse({ ok: false, error: String(error) }));
  return true;
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === POLL_ALARM) pollReadyTasks("alarm").catch(() => {});
});

chrome.runtime.onInstalled.addListener(() => {
  Promise.all([configureSidePanel(), ensureAutoAlarm()])
    .then(() => pollReadyTasks("installed"))
    .catch(console.error);
});

chrome.runtime.onStartup.addListener(() => {
  Promise.all([configureSidePanel(), ensureAutoAlarm()])
    .then(() => pollReadyTasks("startup"))
    .catch(console.error);
});

Promise.all([configureSidePanel(), ensureAutoAlarm()])
  .then(() => pollReadyTasks("worker-load"))
  .catch(() => {});
