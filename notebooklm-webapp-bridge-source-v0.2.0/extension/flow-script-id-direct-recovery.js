const FLOW_RECOVERY_HOST = "http://127.0.0.1:8765";
const FLOW_RECOVERY_ALARM = "flow-script-id-direct-recovery";
const FLOW_RECOVERY_KEY = "flowScriptIdDirectRecoveryV1";
const FLOW_RECOVERY_TASK_ID = "FLOW_SCRIPT_ID_DIRECT_RECOVERY_20260825_01";
const FLOW_RECOVERY_READBACK = "FLOW_SCRIPT_ID_RECOVERY_RESULT_20260825.json";

async function flowRecoveryFetchJson(url, options = {}, timeoutMs = 10000) {
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

async function flowRecoveryReadState() {
  try { return (await chrome.storage.local.get(FLOW_RECOVERY_KEY))[FLOW_RECOVERY_KEY] || {}; }
  catch { return {}; }
}

async function flowRecoveryWriteState(patch) {
  const current = await flowRecoveryReadState();
  const next = { ...current, ...patch, updatedAt: new Date().toISOString() };
  try { await chrome.storage.local.set({ [FLOW_RECOVERY_KEY]: next }); } catch {}
  return next;
}

function flowRecoveryTask() {
  return {
    taskId: FLOW_RECOVERY_TASK_ID,
    TASK_ID: FLOW_RECOVERY_TASK_ID,
    taskType: "LOCAL_POWERSHELL",
    TASK_TYPE: "LOCAL_POWERSHELL",
    timeoutSeconds: 300,
    TIMEOUT_SECONDS: 300,
    sourceText: JSON.stringify({
      repo: "8friend8ship-cloud/animation",
      branch: "codex/video-promo-agent-workflow-20260823",
      script: "tools/Recover-AnimationRuntime-Lineage.ps1",
      args: {
        TargetSpreadsheetId: "1TbQxEcCiiibu2-EmMGEdt79v4AUpE8JL2XrDEKeVRCk",
        TargetCodePattern: "setupNotebookLMBridge|bridgeSelfTest|WEBAPP_TEMPLATE_03",
        TargetNamePattern: "WEBAPP_TEMPLATE_03",
        TargetLabel: "FlowWebApp",
        CentralReadbackName: FLOW_RECOVERY_READBACK
      }
    })
  };
}

async function flowRecoveryTick(reason = "alarm") {
  const state = await flowRecoveryReadState();
  if (state.done === true) return { ok: true, skipped: "done", reason };
  try {
    const health = await flowRecoveryFetchJson(`${FLOW_RECOVERY_HOST}/health`, {}, 5000);
    if (!health?.asyncJobs) throw new Error("LOCAL_HOST_ASYNC_NOT_READY");
    let existing = null;
    try { existing = await flowRecoveryFetchJson(`${FLOW_RECOVERY_HOST}/result?taskId=${encodeURIComponent(FLOW_RECOVERY_TASK_ID)}`, {}, 8000); } catch {}
    const existingState = String(existing?.state || "").toUpperCase();
    if (existingState === "DONE") {
      await flowRecoveryWriteState({ done: true, taskId: FLOW_RECOVERY_TASK_ID, hostState: "DONE", reason, resultOk: Boolean(existing?.result?.ok) });
      await chrome.alarms.clear(FLOW_RECOVERY_ALARM).catch(() => {});
      return { ok: true, state: "DONE", taskId: FLOW_RECOVERY_TASK_ID };
    }
    if (["RUNNING", "STARTED"].includes(existingState)) {
      await flowRecoveryWriteState({ started: true, taskId: FLOW_RECOVERY_TASK_ID, hostState: existingState, reason });
      return { ok: true, state: existingState, taskId: FLOW_RECOVERY_TASK_ID };
    }
    const started = await flowRecoveryFetchJson(`${FLOW_RECOVERY_HOST}/run`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ source: "notebooklm-webapp-bridge", task: flowRecoveryTask() })
    }, 12000);
    await flowRecoveryWriteState({ started: true, taskId: FLOW_RECOVERY_TASK_ID, hostState: started.state || "STARTED", reason, lastError: "" });
    return { ok: true, state: started.state || "STARTED", taskId: FLOW_RECOVERY_TASK_ID };
  } catch (error) {
    await flowRecoveryWriteState({ lastAttemptAt: new Date().toISOString(), reason, lastError: String(error?.message || error) });
    return { ok: false, error: String(error?.message || error), reason };
  }
}

async function flowRecoveryEnsureAlarm() {
  try {
    await chrome.alarms.clear(FLOW_RECOVERY_ALARM);
    await chrome.alarms.create(FLOW_RECOVERY_ALARM, { delayInMinutes: 0.05, periodInMinutes: 1 });
  } catch {}
}

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === FLOW_RECOVERY_ALARM) flowRecoveryTick("alarm").catch(() => {});
});
chrome.runtime.onInstalled.addListener(() => flowRecoveryEnsureAlarm().then(() => flowRecoveryTick("installed")).catch(() => {}));
chrome.runtime.onStartup.addListener(() => flowRecoveryEnsureAlarm().then(() => flowRecoveryTick("startup")).catch(() => {}));
flowRecoveryEnsureAlarm().then(() => flowRecoveryTick("worker-load")).catch(() => {});
