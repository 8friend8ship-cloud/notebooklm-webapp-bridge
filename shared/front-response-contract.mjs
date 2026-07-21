export const FRONT_RESPONSE_ACTION = 'front_answer';

export function createFrontAnswerQuery(input = {}) {
  if (!input.appId || !input.query) throw new Error('appId and query are required');
  return {
    action: FRONT_RESPONSE_ACTION,
    appId: String(input.appId),
    query: String(input.query),
    intent: String(input.intent || ''),
    locale: String(input.locale || 'ko-KR'),
    market: String(input.market || 'KR'),
    sessionId: String(input.sessionId || ''),
  };
}

export function isFrontAnswerResult(value) {
  return Boolean(value && typeof value === 'object' && value.ok === true && typeof value.status === 'string');
}
