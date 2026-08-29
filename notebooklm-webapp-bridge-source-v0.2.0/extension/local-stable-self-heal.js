const HD_SELF_HEAL_SOURCE = "notebooklm-webapp-bridge";
const HD_SELF_HEAL_HOST = "http://127.0.0.1:8765";
const HD_SELF_HEAL_KEY = "homeDesignLocalStableSelfHealV3";
const HD_SELF_HEAL_ALARM = "home-design-local-stable-self-heal";
const HD_SELF_HEAL_PERIOD_MINUTES = 5;

function hdSelfHealVersion() {
  try { return String(chrome.runtime.getManifest().version || "unknown"); }
  catch { return "unknown"; }
}
function hdBucket() { return Math.floor(Date.now() / (HD_SELF_HEAL_PERIOD_MINUTES * 60 * 1000)); }
function hdSafe(v) { return String(v || "").replace(/[^A-Za-z0-9_.-]/g, "_").replace(/\./g, "_"); }
function hdSelfHealTaskId(version, bucket, attempt = 1) {
  return `LOCAL_STABLE_SELF_HEAL_${hdSafe(version)}_${bucket}_A${attempt}`;
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
    const existing = await chrome.alarms.get(HD_SELF_HEAL_ALARM);
    if (!existing) {
      await chrome.alarms.create(HD_SELF_HEAL_ALARM, { delayInMinutes: 0.15, periodInMinutes: HD_SELF_HEAL_PERIOD_MINUTES });
    }
  } catch {}
}
function hdStableAgentTask(taskId) {
  return {
    taskId,
    TASK_ID: taskId,
    taskType: "LOCAL_POWERSHELL",
    TASK_TYPE: "LOCAL_POWERSHELL",
    timeoutSeconds: 180,
    TIMEOUT_SECONDS: 180,
    sourceText: JSON.stringify({
      repo: "8friend8ship-cloud/notebooklm-webapp-bridge",
      branch: "main",
      script: "local-agent/governor/RunChromeGovernorReadback.ps1",
      args: { KickStableAgent: true }
    })
  };
}
async function hdWaitForResult(taskId, maxWaitMs = 45000) {
  const deadline = Date.now() + maxWaitMs;
  while (Date.now() < deadline) {
    await new Promise(resolve => setTimeout(resolve, 2500));
    try {
      const result = await hdFetchJson(`${HD_SELF_HEAL_HOST}/result?taskId=${encodeURIComponent(taskId)}`, {}, 5000);
      if (result?.state === "DONE") return result;
      if (result?.state === "ERROR") throw new Error(result?.error || "HOST_ASYNC_ERROR");
    } catch (error) {
      if (Date.now() >= deadline) throw error;
    }
  }
  throw new Error("HOST_RESULT_TIMEOUT");
}
async function hdRunStableKick(version, bucket, attempt) {
  const taskId = hdSelfHealTaskId(version, bucket, attempt);
  const started = await hdFetchJson(`${HD_SELF_HEAL_HOST}/run`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ source: HD_SELF_HEAL_SOURCE, task: hdStableAgentTask(taskId) })
  }, 10000);
  const final = await hdWaitForResult(taskId, 45000);
  const inner = final?.result || {};
  const ok = final?.state === "DONE" && inner?.ok !== false && Number(inner?.exitCode ?? 0) === 0;
  if (!ok) throw new Error(inner?.stderr || inner?.error || `HOST_RESULT_${final?.state || "UNKNOWN"}`);
  return { taskId, started, final };
}
async function hdKickStableAgent(reason = "worker-load") {
  const version = hdSelfHealVersion();
  const bucket = hdBucket();
  const state = await hdReadSelfHealState();
  if (Number(state.lastSuccessBucket) === bucket) {
    return { ok: true, skipped: "already_succeeded_this_bucket", version, bucket };
  }
  let health;
  try {
    health = await hdFetchJson(`${HD_SELF_HEAL_HOST}/health`, {}, 4000);
    if (!health?.asyncJobs) throw new Error("LOCAL_HOST_ASYNC_NOT_READY");
    let run;
    let attempt = 1;
    let firstError = "";
    try {
      run = await hdRunStableKick(version, bucket, attempt);
    } catch (error) {
      firstError = String(error?.message || error);
      attempt = 2;
      run = await hdRunStableKick(version, bucket, attempt);
    }
    await hdWriteSelfHealState({
      version,
      lastAttemptBucket: bucket,
      lastSuccessBucket: bucket,
      lastKickAt: new Date().toISOString(),
      reason,
      taskId: run.taskId,
      attempt,
      hostVersion: health.version || "",
      hostState: run.final?.state || run.started?.state || "",
      firstError,
      lastError: ""
    });
    return { ok: true, version, bucket, taskId: run.taskId, attempt, state: run.final?.state || "DONE" };
  } catch (error) {
    await hdWriteSelfHealState({
      version,
      lastAttemptBucket: bucket,
      lastKickAt: new Date().toISOString(),
      reason,
      hostVersion: health?.version || "",
      lastError: String(error?.message || error)
    });
    return { ok: false, version, bucket, error: String(error?.message || error) };
  }
}

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === HD_SELF_HEAL_ALARM) hdKickStableAgent("alarm").catch(() => {});
});
chrome.runtime.onInstalled.addListener(() => hdEnsureSelfHealAlarm().then(() => hdKickStableAgent("installed")).catch(() => {}));
chrome.runtime.onStartup.addListener(() => hdEnsureSelfHealAlarm().then(() => hdKickStableAgent("startup")).catch(() => {}));
hdEnsureSelfHealAlarm().then(() => hdKickStableAgent("worker-load")).catch(() => {});
