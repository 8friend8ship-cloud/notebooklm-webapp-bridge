export async function getNotebookPmfContext() {
  const response = await fetch('/api/pmf-context', { headers: { Accept: 'application/json' }, cache: 'no-store' });
  const payload = await response.json();
  if (!response.ok || !payload.ok) throw new Error(payload.error || 'PMF context request failed');
  return payload;
}
