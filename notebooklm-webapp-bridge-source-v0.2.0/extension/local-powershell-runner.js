import "./background.js";

const SOURCE = "notebooklm-webapp-bridge";
const CONFIG_KEY = "nlmBridgeConfig";
const SESSION_KEYS = ["homeDesignBridgeSessionV7", "nlmPersistentSessionV5"];
const ACTIVE_KEY = "nlmLocalPowerShellAsyncActiveV2";
const ALARM = "local-powershell-async-poll";
const HOST = "http://127.0.0.1:8765";
const ASYNC_TYPE = "LOCAL_POWERSHELL_ASYNC";
const DEFAULT_TIMEOUT = 600;
const STALE_GRACE = 60;
let busy = false;

async function config() {
  const stored = await chrome.storage.local.get(CONFIG_KEY);
  return stored[CONFIG_KEY] || {};
}
async function sessionToken() {
  const stored = await chrome.storage.local.get(SESSION_KEYS);
  for (const key of SESSION_KEYS) {
    const value = stored[key];
    const token = typeof value === "string" ? value : value?.token;
    if (token) return String(token);
  }
  return "";
}
async function getActive() {
  const stored = await chrome.storage.local.get(ACTIVE_KEY);
  return stored[ACTIVE_KEY] || null;
}
async function setActive(value) {
  if (value) await chrome.storage.local.set({ [ACTIVE_KEY]: value });
  else await chrome.storage.local.remove(ACTIVE_KEY);
}
function field(task, ...names) {
  for (const name of names) {
    const value = task?.[name];
    if (value !== undefined && value !== null && value !== "") return value;
  }
  return undefined;
}
function taskId(task) { return String(field(task, "taskId", "TASK_ID") || ""); }
function taskType(task) { return String(field(task, "taskType", "TASK_TYPE") || "").toUpperCase(); }
function taskStatus(task) { return String(field(task, "status", "STATUS") || "READY").toUpperCase(); }
function timeoutSeconds(task) {
  const n = Number(field(task, "timeoutSeconds", "TIMEOUT_SECONDS", "timeout_seconds") ?? DEFAULT_TIMEOUT);
  if (!Number.isFinite(n) || n <= 0) return DEFAULT_TIMEOUT;
  return Math.max(30, Math.min(1800, Math.round(n)));
}
function parseTime(value) {
  const n = Date.parse(String(value || ""));
  return Number.isFinite(n) ? n : 0;
}
function taskTime(task) {
  for (const key of ["claimedAt", "CLAIMED_AT", "startedAt", "STARTED_AT", "updatedAt", "UPDATED_AT", "createdAt", "CREATED_AT"]) {
    const n = parseTime(task?.[key]);
    if (n) return n;
  }
  return 0;
}
function staleClaim(task) {
  if (taskType(task) !== ASYNC_TYPE || taskStatus(task) !== "CLAIMED") return false;
  const started = taskTime(task);
  return !!started && Date.now() - started > (timeoutSeconds(task) + STALE_GRACE) * 1000;
}
async function api(url, payload) {
  if (!/^https:\/\/script\.google\.com\/macros\/s\//.test(url || "")) throw new Error("Apps Script URL missing");
  const response = await fetch(url, {
    method: "POST",
    redirect: "follow",
    headers: { "Content-Type": "text/plain;charset=utf-8" },
    body: JSON.stringify(payload)
  });
  const data = await response.json();
  if (!response.ok || !data.ok) throw new Error(data.error || `HTTP ${response.status}`);
  return data;
}
async function hostJson(url, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    const data = await response.json().catch(() => ({ ok: false, error: `HTTP ${response.status}` }));
    if (!response.ok || !data.ok) throw new Error(data.error || `Local host HTTP ${response.status}`);
    return data;
  } finally {
    clearTimeout(timer);
  }
}
function hostCompatibleTask(task) {
  return { ...task, taskType: "LOCAL_POWERSHELL", TASK_TYPE: "LOCAL_POWERSHELL" };
}
async function hostStart(task) {
  return hostJson(`${HOST}/run`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ source: SOURCE, task: hostCompatibleTask(task) })
  });
}
async function hostResult(id) {
  return hostJson(`${HOST}/result?taskId=${encodeURIComponent(id)}`);
}
async function hostCancel(id) {
  return hostJson(`${HOST}/cancel`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ taskId: id })
  });
}
async function recoverStale(configValue, token, tasks) {
  const recovered = [];
  for (const task of tasks) {
    if (!staleClaim(task)) continue;
    const id = taskId(task);
    try {
      await api(configValue.appsScriptUrl, {
        action: "updateTask", sessionToken: token, taskId: id, status: "RETRY",
        patch: { error: `ASYNC_STALE_CLAIM_RECOVERED_AFTER_${timeoutSeconds(task)}s`, clearClaim: true, claimedAt: "", startedAt: "" }
      });
      recovered.push({ ...task, status: "RETRY", STATUS: "RETRY", claimedAt: "", CLAIMED_AT: "", startedAt: "", STARTED_AT: "" });
    } catch {}
  }
  return recovered;
}
async function finalize(configValue, token, active) {
  const id = String(active?.taskId || "");
  if (!id) { await setActive(null); return { state: "EMPTY" }; }
  let host;
  try {
    host = await hostResult(id);
  } catch (error) {
    const age = Date.now() - Number(active.startedAtMs || Date.now());
    const hardLimit = (Number(active.timeoutSeconds || DEFAULT_TIMEOUT) + 120) * 1000;
    if (age <= hardLimit) return { state: "WAIT_HOST", error: String(error?.message || error) };
    try { await hostCancel(id); } catch {}
    try {
      await api(configValue.appsScriptUrl, { action: "updateTask", sessionToken: token, taskId: id, status: "ERROR", patch: { error: "LOCAL_ASYNC_HOST_RESULT_TIMEOUT" } });
    } catch {}
    await setActive(null);
    return { state: "TIMEOUT" };
  }

  if (["RUNNING", "STARTED"].includes(String(host.state || ""))) return { state: String(host.state), taskId: id };
  if (host.state === "DONE") {
    const result = host.result || {};
    try {
      if (result.ok) {
        await api(configValue.appsScriptUrl, {
          action: "completeTask", sessionToken: token, taskId: id,
          result: { resultText: JSON.stringify(result, null, 2), resultUrls: [], notebookUrl: "" }
        });
      } else {
        await api(configValue.appsScriptUrl, {
          action: "updateTask", sessionToken: token, taskId: id, status: "ERROR",
          patch: { error: String(result.stderr || result.error || `LOCAL_EXIT_${result.exitCode ?? "UNKNOWN"}`) }
        });
      }
    } finally {
      await setActive(null);
    }
    return { state: result.ok ? "COMPLETED" : "FAILED", taskId: id };
  }

  if (["ERROR", "NOT_FOUND"].includes(String(host.state || ""))) {
    try {
      await api(configValue.appsScriptUrl, { action: "updateTask", sessionToken: token, taskId: id, status: "ERROR", patch: { error: String(host.error || host.state) } });
    } catch {}
    await setActive(null);
    return { state: String(host.state), taskId: id };
  }
  return { state: String(host.state || "UNKNOWN"), taskId: id };
}
async function pollCore(reason = "alarm") {
  const cfg = await config();
  if (!cfg.appsScriptUrl) return { ok: true, skipped: "api_not_configured" };
  const token = await sessionToken();
  if (!token) return { ok: true, skipped: "no_session" };

  const active = await getActive();
  if (active) return { ok: true, reason, active: await finalize(cfg, token, active) };

  const listed = await api(cfg.appsScriptUrl, { action: "listTasks", sessionToken: token, includeClaimed: true });
  const listedTasks = Array.isArray(listed.tasks) ? listed.tasks : [];
  const recovered = await recoverStale(cfg, token, listedTasks);
  const map = new Map();
  for (const task of [...recovered, ...listedTasks]) {
    if (taskType(task) !== ASYNC_TYPE) continue;
    if (!["READY", "RETRY", "ERROR"].includes(taskStatus(task))) continue;
    if (taskId(task)) map.set(taskId(task), task);
  }
  const tasks = [...map.values()];
  if (!tasks.length) return { ok: true, reason, processed: 0, asyncAvailable: 0 };

  const task = tasks[0];
  const id = taskId(task);
  const profile = await chrome.identity.getProfileUserInfo({ accountStatus: "ANY" }).catch(() => ({ email: "" }));
  const claimed = await api(cfg.appsScriptUrl, { action: "claimTask", sessionToken: token, taskId: id, chromeProfileEmail: profile.email || "" });
  const claimedTask = claimed.task || task;
  const started = await hostStart(claimedTask);
  await setActive({ taskId: id, timeoutSeconds: timeoutSeconds(claimedTask), startedAtMs: Date.now(), hostState: started.state || "STARTED" });
  return { ok: true, reason, started: id, hostState: started.state || "STARTED", asyncAvailable: tasks.length };
}
async function poll(reason = "alarm") {
  if (busy) return { ok: true, skipped: "busy" };
  busy = true;
  try { return await pollCore(reason); }
  catch (error) { return { ok: false, reason, error: String(error?.message || error) }; }
  finally { busy = false; }
}
async function ensureAlarm() {
  await chrome.alarms.clear(ALARM);
  await chrome.alarms.create(ALARM, { delayInMinutes: 0.2, periodInMinutes: 1 });
}
chrome.alarms.onAlarm.addListener((alarm) => { if (alarm.name === ALARM) poll("alarm").catch(() => {}); });
chrome.runtime.onInstalled.addListener(() => ensureAlarm().then(() => poll("installed")).catch(() => {}));
chrome.runtime.onStartup.addListener(() => ensureAlarm().then(() => poll("startup")).catch(() => {}));
ensureAlarm().then(() => poll("worker-load")).catch(() => {});
