(() => {
  if (globalThis.__HOMEDESIGN_FRONT_AUTO_RUN__) return;
  globalThis.__HOMEDESIGN_FRONT_AUTO_RUN__ = true;

  const startedAt = Date.now();
  const maxWaitMs = 90_000;
  const retryMs = 2_000;
  const maxTasks = 2;
  let running = false;
  let finished = false;

  const runnable = (task) => {
    const status = String(task?.status || "READY").toUpperCase();
    return ["READY", "RETRY"].includes(status) && task?.autoSubmit !== false;
  };

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

  window.addEventListener("load", tryAutoRun);
  const timer = setInterval(() => {
    if (finished || Date.now() - startedAt > maxWaitMs) {
      clearInterval(timer);
      return;
    }
    tryAutoRun();
  }, retryMs);
})();
