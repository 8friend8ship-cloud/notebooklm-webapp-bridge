import { createFrontAnswerQuery, isFrontAnswerResult } from '../shared/front-response-contract.mjs';

export async function getFrontAnswer(endpoint, input, token) {
  const payload = createFrontAnswerQuery(input);
  const url = new URL(endpoint);
  Object.entries(payload).forEach(([key, value]) => url.searchParams.set(key, String(value)));
  if (token) url.searchParams.set('token', token);

  const response = await fetch(url, { cache: 'no-store' });
  const result = await response.json();
  if (!response.ok || !isFrontAnswerResult(result)) {
    throw new Error(result?.error || 'Front answer request failed');
  }
  return result;
}
