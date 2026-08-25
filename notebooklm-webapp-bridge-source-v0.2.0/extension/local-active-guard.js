const GUARD_SOURCE = "notebooklm-webapp-bridge";
const GUARD_ACTIVE_KEY = "nlmLocalPowerShellAsyncActiveV2";
const GUARD_SESSION_KEYS = ["homeDesignBridgeSessionV7", "nlmPersistentSessionV5"];
const GUARD_ALARM = "nlm-local-active-stale-guard";
const GUARD_HOST = "http://127.0.0.1:8765";
const GUARD_API = "https://script.google.com/macros/s/AKfycbynWKaVwG1SRE6uWJ6d4r0Q5wEvKbB5foIuphQBGDwi8P2r2qaP6K0FRAV8krr9R70P/exec";
const GUARD_DEFAULT_TIMEOUT = 600;

async function guardReadActive() {
  try { return (await chrome.storage.local.get(GUARD_ACTIVE_KEY))[GUARD_ACTIVE_KEY] || null; }
  catch { return null; }
}

async function guardWriteActive(value) {
  try {
    if (value) await chrome.storage.local.set({ [GUARD_ACTIVE_KEY]: value });
    else await chrome.storage.local.remove(GUARD_ACTIVE_KEY);
  } catch {}
}

async function guardSessionToken() {
  try {
    const stored = await chrome.storage.local.get(GUARD_SESSION_KEYS);
    for (const key of GUARD_SESSION_KEYS) {
      const value = stored[key];
      const token = typeof value === "string" ? value : value?.token;
      if (token) return String(token);
    }
  } catch {}
  return "";
}

async function guardFetchJson(url, options = {}, timeoutMs = 10000) {
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

async function guardHoldQueue(taskId, reason) {
  const sessionToken = await guardSessionToken();
  if (!sessionToken || !taskId) return false;
  try {
    await guardFetchJson(GUARD_API, {
      method: "POST",
      redirect: "follow",
      headers: { "Content-Type": "text/plain;charset=utf-8" },
      body: JSON.stringify({
        action: "updateTask",
        sessionToken,
        taskId,
        status: "HOLD_RECOVERY",
        patch: { error: reason, clearClaim: true, claimedAt: "", startedAt: "" }
      })
    });
    return true;
  } catch {
    return false;
  }
}

async function guardCancelHost(taskId) {
  try {
    await guardFetchJson(`${GUARD_HOST}/cancel`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ taskId })
    }, 8000);
  } catch {}
}

function guardParseTime(value) {
  const parsed = Date.parse(String(value || ""));
  return Number.isFinite(parsed) ? parsed : 0;
}

async function guardStaleActive(reason = "alarm") {
  const active = await guardReadActive();
  const taskId = String(active?.taskId || "");
  if (!taskId) return { ok: true, skipped: "no_active", reason };

  const timeoutSeconds = Math.max(30, Math.min(1800, Number(active?.timeoutSeconds || GUARD_DEFAULT_TIMEOUT)));
  const hardMs = (timeoutSeconds + 120) * 1000;
  let startedAtMs = Number(active?.startedAtMs || 0);
  let host = null;
  let hostError = "";

  try {
    host = await guardFetchJson(`${GUARD_HOST}/result?taskId=${encodeURIComponent(taskId)}`, {}, 8000);
  } catch (error) {
    hostError = String(error?.message || error);
  }

  if (!startedAtMs && host?.startedAt) {
    startedAtMs = guardParseTime(host.startedAt);
    if (startedAtMs) await guardWriteActive({ ...active, startedAtMs, guardRecoveredStartedAt: true });
  }

  const ageMs = startedAtMs ? Date.now() - startedAtMs : 0;
  const state = String(host?.state || "").toUpperCase();

  if (state === "DONE") return { ok: true, skipped: "done_pending_normal_finalize", taskId, reason };

  if (["ERROR", "NOT_FOUND"].includes(state)) {
    const detail = `D18_LOCAL_ACTIVE_${state}_HOLD:${taskId}`;
    await guardHoldQueue(taskId, detail);
    await guardWriteActive(null);
    return { ok: true, action: "held_and_cleared", state, taskId, reason };
  }

  if (startedAtMs && ageMs > hardMs) {
    const detail = `D18_LOCAL_ACTIVE_HARD_TIMEOUT_HOLD:${taskId}:ageMs=${ageMs}:timeoutSeconds=${timeoutSeconds}`;
    await guardCancelHost(taskId);
    await guardHoldQueue(taskId, detail);
    await guardWriteActive(null);
    return { ok: true, action: "canceled_held_and_cleared", taskId, ageMs, timeoutSeconds, reason };
  }

  if (!startedAtMs && hostError) {
    return { ok: true, skipped: "missing_start_time_and_host_unreachable", taskId, hostError, reason };
  }

  return { ok: true, skipped: "active_within_budget", taskId, state, ageMs, timeoutSeconds, reason };
}

async function guardEnsureAlarm() {
  try {
    await chrome.alarms.clear(GUARD_ALARM);
    await chrome.alarms.create(GUARD_ALARM, { delayInMinutes: 0.05, periodInMinutes: 1 });
  } catch {}
}

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === GUARD_ALARM) guardStaleActive("alarm").catch(() => {});
});
chrome.runtime.onInstalled.addListener(() => guardEnsureAlarm().then(() => guardStaleActive("installed")).catch(() => {}));
chrome.runtime.onStartup.addListener(() => guardEnsureAlarm().then(() => guardStaleActive("startup")).catch(() => {}));
guardEnsureAlarm().then(() => guardStaleActive("worker-load")).catch(() => {});
