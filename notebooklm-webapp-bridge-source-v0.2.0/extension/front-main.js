(() => {
  if (globalThis.__HOMEDESIGN_V025_MAIN__) return;
  globalThis.__HOMEDESIGN_V025_MAIN__ = true;

  const CONFIG_KEY = "nlmBridgeFrontendConfig";
  const SESSION_KEY = "nlmSessionToken";
  const MAIN = "HOMEDESIGN_V025_MAIN";
  const EXT = "HOMEDESIGN_V025_EXT";
  let lastToken = "";

  function send(type, payload = {}) {
    window.postMessage({ source: MAIN, type, ...payload }, location.origin);
  }

  function setConfig(extensionId) {
    if (!extensionId) return false;
    const current = (() => { try { return JSON.parse(localStorage.getItem(CONFIG_KEY) || "{}"); } catch { return {}; } })();
    const next = { ...current, EXTENSION_ID: extensionId };
    const changed = current.EXTENSION_ID !== extensionId;
    if (changed) localStorage.setItem(CONFIG_KEY, JSON.stringify(next));
    return changed;
  }

  function publishSession() {
    const token = sessionStorage.getItem(SESSION_KEY) || "";
    if (token && token !== lastToken) {
      lastToken = token;
      send("SAVE_SESSION", { token });
    }
  }

  window.addEventListener("message", (event) => {
    if (event.source !== window || event.origin !== location.origin) return;
    const data = event.data || {};
    if (data.source !== EXT) return;

    if (data.type === "BOOTSTRAP") {
      const configChanged = setConfig(String(data.extensionId || ""));
      const restored = String(data.sessionToken || "");
      let sessionChanged = false;
      if (restored && sessionStorage.getItem(SESSION_KEY) !== restored) {
        sessionStorage.setItem(SESSION_KEY, restored);
        lastToken = restored;
        sessionChanged = true;
      }
      if ((configChanged || sessionChanged) && sessionStorage.getItem("__homedesign_v025_reload") !== "1") {
        sessionStorage.setItem("__homedesign_v025_reload", "1");
        setTimeout(() => location.reload(), 80);
      }
    }

    if (data.type === "CLEAR_SESSION") {
      sessionStorage.removeItem(SESSION_KEY);
      lastToken = "";
    }
  });

  send("REQUEST_BOOTSTRAP");
  publishSession();
  setInterval(publishSession, 750);
})();
