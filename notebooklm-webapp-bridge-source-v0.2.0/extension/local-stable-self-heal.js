const HD_SELF_HEAL_SOURCE = "notebooklm-webapp-bridge";
const HD_SELF_HEAL_HOST = "http://127.0.0.1:8765";
const HD_SELF_HEAL_KEY = "homeDesignLocalStableSelfHealV1";
const HD_SELF_HEAL_ALARM = "home-design-local-stable-self-heal";

function hdSelfHealVersion() {
  try { return String(chrome.runtime.getManifest().version || "unknown"); }
  catch { return "unknown"; }
}
function hdSelfHealTaskId(version) {
  return `LOCAL_STABLE_SELF_HEAL_${String(version).replace(/[^A-Za-z0-9_.-]/g, "_").replace(/\./g, "_")}`;
}
async function hdFetchJson(url, options = {}, timeoutMs = 8000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    const data = await response.json().catch(() => ({ ok: false, error: `HTTP_${response.status}` }));
    if (!response.ok || !data?.ok) throw new Error(data?.error || `HTTP_${response.status}`);
    return data;
  } finally {
    clearTimeout(timer);
  }
}
async function hdReadSelfHealState() {
  try { return (await chrome.storage.local.get(HD_SELF_HEAL_KEY))[HD_SELF_HEAL_KEY] || {}; }
  catch { return {}; }
}
async function hdWriteSelfHealState(patch) {
  const current = await hdReadSelfHealState();
  const next = { ...current, ...patch, updatedAt: new Date().toISOString() };
  try { await chrome.storage.local.set({ [HD_SELF_HEAL_KEY]: next }); } catch {}
  return next;
}
async function hdEnsureSelfHealAlarm() {
  try {
    await chrome.alarms.clear(HD_SELF_HEAL_ALARM);
    await chrome.alarms.create(HD_SELF_HEAL_ALARM, { delayInMinutes: 0.15, periodInMinutes: 1 });
  } catch {}
}
async function hdKickStableAgent(reason = "worker-load") {
  const version = hdSelfHealVersion();
  const state = await hdReadSelfHealState();
  if (state.version === version && state.accepted === true) {
    try { await chrome.alarms.clear(HD_SELF_HEAL_ALARM); } catch {}
    return { ok: true, skipped: "already_accepted", version };
  }
  try {
    const health = await hdFetchJson(`${HD_SELF_HEAL_HOST}/health`, {}, 4000);
    if (!health?.asyncJobs) throw new Error("LOCAL_HOST_ASYNC_NOT_READY");
    const taskId = hdSelfHealTaskId(version);
    const task = {
      taskId,
      TASK_ID: taskId,
      taskType: "LOCAL_POWERSHELL",
      TASK_TYPE: "LOCAL_POWERSHELL",
      timeoutSeconds: 90,
      TIMEOUT_SECONDS: 90,
      sourceText: JSON.stringify({
        repo: "8friend8ship-cloud/notebooklm-webapp-bridge",
        branch: "main",
        script: "local-agent/governor/RunChromeGovernorReadback.ps1",
        args: { KickStableAgent: true }
      })
    };
    const started = await hdFetchJson(`${HD_SELF_HEAL_HOST}/run`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ source: HD_SELF_HEAL_SOURCE, task })
    }, 10000);
    await hdWriteSelfHealState({ version, accepted: true, reason, taskId, hostVersion: health.version || "", hostState: started.state || "", lastError: "" });
    try { await chrome.alarms.clear(HD_SELF_HEAL_ALARM); } catch {}
    return { ok: true, version, taskId, state: started.state || "STARTED" };
  } catch (error) {
    await hdWriteSelfHealState({ version, accepted: false, reason, lastError: String(error?.message || error) });
    return { ok: false, version, error: String(error?.message || error) };
  }
}

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === HD_SELF_HEAL_ALARM) hdKickStableAgent("alarm").catch(() => {});
});
chrome.runtime.onInstalled.addListener(() => hdEnsureSelfHealAlarm().then(() => hdKickStableAgent("installed")).catch(() => {}));
chrome.runtime.onStartup.addListener(() => hdEnsureSelfHealAlarm().then(() => hdKickStableAgent("startup")).catch(() => {}));
hdEnsureSelfHealAlarm().then(() => hdKickStableAgent("worker-load")).catch(() => {});
