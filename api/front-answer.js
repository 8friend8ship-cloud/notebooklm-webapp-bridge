export default async function handler(req, res) {
  if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'GET only' });
  const endpoint = process.env.AGENT_CORE_ENDPOINT || process.env.AGENT_MAIL_ENDPOINT;
  const token = process.env.AGENT_CORE_TOKEN || process.env.AGENT_MAIL_TOKEN;
  if (!endpoint || !token) return res.status(500).json({ ok: false, error: 'Server endpoint is not configured' });

  const query = String(req.query?.query || '').trim();
  if (!query) return res.status(400).json({ ok: false, error: 'query is required' });

  const target = new URL(endpoint);
  target.searchParams.set('action', 'front_answer');
  target.searchParams.set('appId', 'APP_NOTEBOOK_BRIDGE');
  target.searchParams.set('query', query);
  target.searchParams.set('intent', String(req.query?.intent || 'INT_NOTEBOOK_STATUS'));
  target.searchParams.set('locale', String(req.query?.locale || 'ko-KR'));
  target.searchParams.set('market', 'GLOBAL');
  target.searchParams.set('token', token);

  const response = await fetch(target, { cache: 'no-store' });
  res.setHeader('Cache-Control', 'private, max-age=30');
  return res.status(response.status).send(await response.text());
}
