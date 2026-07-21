export default async function handler(req, res) {
  if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'GET only' });
  const endpoint = process.env.AGENT_CORE_ENDPOINT || process.env.AGENT_MAIL_ENDPOINT;
  const token = process.env.AGENT_CORE_TOKEN || process.env.AGENT_MAIL_TOKEN;
  if (!endpoint || !token) return res.status(500).json({ ok: false, error: 'Server endpoint is not configured' });

  const target = new URL(endpoint);
  target.searchParams.set('action', 'pmf_context');
  target.searchParams.set('appId', 'APP_NOTEBOOK_BRIDGE');
  target.searchParams.set('token', token);

  const response = await fetch(target, { cache: 'no-store' });
  res.setHeader('Cache-Control', 'private, max-age=60');
  return res.status(response.status).send(await response.text());
}
