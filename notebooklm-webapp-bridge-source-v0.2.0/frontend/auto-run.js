(() => {
  if (globalThis.__HOMEDESIGN_FRONT_AUTO_RUN__) return;
  globalThis.__HOMEDESIGN_FRONT_AUTO_RUN__ = true;

  const SOURCE = "notebooklm-webapp-bridge";
  const FRONT_CONFIG_KEY = "nlmBridgeFrontendConfig";
  const startedAt = Date.now();
  const maxWaitMs = 90_000;
  const retryMs = 2_000;
  const maxTasks = 2;
  const wakeIntervalMs = 60_000;
  let running = false;
  let finished = false;
  let lastWakeOkAt = 0;

  const runnable = (task) => {
    const status = String(task?.status || "READY").toUpperCase();
    return ["READY", "RETRY"].includes(status) && task?.autoSubmit !== false;
  };

  function readExtensionId() {
    try {
      const runtime = typeof loadRuntimeConfig === "function" ? loadRuntimeConfig() : null;
      const fromRuntime = String(runtime?.EXTENSION_ID || "");
      if (/^[a-p]{32}$/.test(fromRuntime)) return fromRuntime;
    } catch {}
    try {
      const stored = JSON.parse(localStorage.getItem(FRONT_CONFIG_KEY) || "{}");
      const id = String(stored?.EXTENSION_ID || "");
      return /^[a-p]{32}$/.test(id) ? id : "";
    } catch {
      return "";
    }
  }

  async function wakeBridge(reason = "heartbeat") {
    if (!globalThis.chrome?.runtime?.sendMessage) return { ok: false, skipped: "chrome_runtime_unavailable" };
    const extensionId = readExtensionId();
    if (!extensionId) return { ok: false, skipped: "extension_id_unavailable" };

    // Even an older worker that does not answer PING is started by the external
    // message dispatch. Its worker-load self-heal can then kick the existing
    // approved Local Agent path. No CMD/OAuth/re-approval is introduced here.
    try {
      const ping = await chrome.runtime.sendMessage(extensionId, {
        source: SOURCE,
        type: "PING",
        reason,
        sentAt: new Date().toISOString()
      });
      lastWakeOkAt = Date.now();

      // Newer bridge versions support a direct auto-poll wake. Keep this best-effort;
      // old versions are expected to reject it after their service worker has already
      // been woken, which is sufficient for stable self-heal.
      try {
        await chrome.runtime.sendMessage(extensionId, {
          source: SOURCE,
          type: "RUN_AUTO_POLL",
          reason,
          sentAt: new Date().toISOString()
        });
      } catch {}

      return { ok: true, ping };
    } catch (error) {
      return { ok: false, error: error instanceof Error ? error.message : String(error) };
    }
  }

  async function tryAutoRun() {
    if (running || finished) return;
    if (Date.now() - startedAt > maxWaitMs) {
      finished = true;
      return;
    }
    if (!globalThis.chrome?.runtime?.sendMessage) return;
    if (!state?.sessionToken) return;

    try {
      CONFIG = loadRuntimeConfig();
      if (!CONFIG.APPS_SCRIPT_URL?.startsWith("https://script.google.com/macros/s/")) return;
      if (!/^[a-p]{32}$/.test(CONFIG.EXTENSION_ID || "")) return;

      await wakeBridge("initial-auto-run").catch(() => {});

      const listed = await api("listTasks", { date: new Date().toISOString().slice(0, 10) });
      const tasks = (listed.tasks || []).filter(runnable).slice(0, maxTasks);
      if (!tasks.length) {
        finished = true;
        return;
      }

      running = true;
      if (!state.extension) await connectExtension();
      setMessage(`자동 READY 작업 ${tasks.length}건을 실행합니다.`);

      for (const task of tasks) {
        await extensionMessage("RUN_TASK", {
          apiUrl: CONFIG.APPS_SCRIPT_URL,
          sessionToken: state.sessionToken,
          taskId: task.taskId,
        });
      }

      finished = true;
      await loadTasks().catch(() => {});
      setMessage(`자동 작업 ${tasks.length}건 완료 · RESULT/ACK 확인 중`);
    } catch (error) {
      running = false;
      const message = error instanceof Error ? error.message : String(error);
      if (isSessionError(message)) return;
      setMessage(`자동 실행 재시도 중: ${message}`, true);
    } finally {
      if (!finished) running = false;
    }
  }

  function heartbeat(reason) {
    const age = Date.now() - lastWakeOkAt;
    if (age < 10_000 && reason !== "interval") return;
    wakeBridge(reason).catch(() => {});
  }

  window.addEventListener("load", () => {
    heartbeat("load");
    tryAutoRun();
  });
  window.addEventListener("focus", () => heartbeat("focus"));
  window.addEventListener("online", () => heartbeat("online"));
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") heartbeat("visible");
  });

  const timer = setInterval(() => {
    if (!finished && Date.now() - startedAt <= maxWaitMs) tryAutoRun();
  }, retryMs);

  // Persistent worker wake path. This intentionally continues after the 90-second
  // READY auto-run window so a long-open dedicated Chrome/front tab can recover
  // the extension/Local Agent chain without asking the user to run another CMD.
  const wakeTimer = setInterval(() => heartbeat("interval"), wakeIntervalMs);

  window.addEventListener("beforeunload", () => {
    clearInterval(timer);
    clearInterval(wakeTimer);
  }, { once: true });
})();
