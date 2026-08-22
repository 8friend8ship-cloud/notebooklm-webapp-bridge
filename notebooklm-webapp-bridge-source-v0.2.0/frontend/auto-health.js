(() => {
  const config = window.NLM_BRIDGE_CONFIG || {};
  const url = String(config.APPS_SCRIPT_URL || '');
  if (!url.startsWith('https://script.google.com/macros/s/')) return;

  const setStatus = (text, error = false) => {
    const el = document.querySelector('#message');
    if (!el) return;
    el.textContent = text;
    el.className = `message ${error ? 'error' : ''}`;
  };

  window.addEventListener('load', async () => {
    try {
      const response = await fetch(url, {
        method: 'POST',
        redirect: 'follow',
        headers: { 'Content-Type': 'text/plain;charset=utf-8' },
        body: JSON.stringify({ action: 'health' }),
      });
      const data = await response.json();
      if (!response.ok || !data?.ok) throw new Error(data?.error || `HTTP ${response.status}`);
      setStatus('Apps Script 자동 점검 정상 · Chrome 확장 연결 후 작업을 실행하세요.');
    } catch (error) {
      setStatus(`Apps Script 자동 점검 실패 · 수동 진단 필요: ${error.message}`, true);
    }
  });
})();
