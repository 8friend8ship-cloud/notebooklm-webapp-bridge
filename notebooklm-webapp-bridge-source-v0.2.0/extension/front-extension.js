(() => {
  if (globalThis.__HOMEDESIGN_V025_EXT__) return;
  globalThis.__HOMEDESIGN_V025_EXT__ = true;

  const STORE = "homeDesignBridgeSessionV7";
  const MAIN = "HOMEDESIGN_V025_MAIN";
  const EXT = "HOMEDESIGN_V025_EXT";

  async function bootstrap() {
    let token = "";
    try {
      const data = await chrome.storage.local.get(STORE);
      token = String(data?.[STORE]?.token || "");
    } catch {}
    window.postMessage({ source: EXT, type: "BOOTSTRAP", extensionId: chrome.runtime.id, sessionToken: token }, location.origin);
  }

  window.addEventListener("message", async (event) => {
    if (event.source !== window || event.origin !== location.origin) return;
    const data = event.data || {};
    if (data.source !== MAIN) return;

    if (data.type === "REQUEST_BOOTSTRAP") {
      await bootstrap();
      return;
    }
    if (data.type === "SAVE_SESSION" && data.token) {
      try {
        await chrome.storage.local.set({
          [STORE]: { token: String(data.token), savedAt: new Date().toISOString(), origin: location.origin }
        });
      } catch {}
    }
  });

  bootstrap();
})();
