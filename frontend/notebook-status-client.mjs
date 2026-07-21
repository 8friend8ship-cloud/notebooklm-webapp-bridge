export async function askNotebookStatus(query, options = {}) {
  const params = new URLSearchParams({
    query,
    intent: options.intent || 'INT_NOTEBOOK_STATUS',
    locale: options.locale || 'ko-KR',
  });
  const response = await fetch(`/api/front-answer?${params.toString()}`, {
    headers: { Accept: 'application/json' },
    cache: 'no-store',
  });
  const result = await response.json();
  if (!response.ok || !result.ok) throw new Error(result.error || '답변 자료를 불러오지 못했습니다.');
  return result;
}
