const sanitize = (value) => String(value || 'unknown').replace(/[^0-9A-Za-z._-]/g, '_').slice(0, 120);

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || message.type !== 'CENTRAL_SHOPPING_RESEARCH_RESULT') return;

  const payload = message.payload || {};
  const platform = sanitize(payload.platform || 'shopping');
  const appId = sanitize(payload.appId || 'ALL_APPS');
  const productId = sanitize(payload.productId || payload.query || 'unknown');
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filename = `CentralAgent_ShoppingBridge/${appId}/${platform}/${stamp}_${productId}.json`;
  const json = JSON.stringify(payload, null, 2);
  const url = `data:application/json;charset=utf-8,${encodeURIComponent(json)}`;

  chrome.downloads.download({ url, filename, saveAs: false }, (downloadId) => {
    if (chrome.runtime.lastError) {
      sendResponse({ ok: false, error: chrome.runtime.lastError.message });
      return;
    }
    sendResponse({ ok: true, downloadId, filename });
  });

  return true;
});
