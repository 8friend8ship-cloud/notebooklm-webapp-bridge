import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const schemaPath = new URL('../shared/agent-operations.schema.json', import.meta.url);
const contractPath = new URL('../docs/agent-operations-platform-contract.md', import.meta.url);

const requiredIds = [
  'REQUEST_ID',
  'TASK_ID',
  'PROJECT_ID',
  'CONTENT_ID',
  'MASTER_CONTENT_ID',
  'SCHEMA_VERSION'
];

const requiredQueues = [
  'MASTER_CONTENT_QUEUE',
  'PLATFORM_EDIT_QUEUE',
  'PUBLISH_QUEUE',
  'COMMENT_DM_QUEUE',
  'BRIDGE_QUEUE',
  'RESULT_CALLBACK_QUEUE',
  'RETRY_QUEUE',
  'AUDIT_QUEUE'
];

test('schema is machine-readable and pins the approved config version', async () => {
  const schema = JSON.parse(await readFile(schemaPath, 'utf8'));
  assert.equal(schema.type, 'object');
  assert.equal(schema.properties.SCHEMA_VERSION.const, '1.0.0');
  for (const id of requiredIds) assert.ok(schema.required.includes(id), `${id} must be required`);
});

test('retryable jobs require an idempotency key', async () => {
  const schema = JSON.parse(await readFile(schemaPath, 'utf8'));
  const retryRule = schema.allOf.find(
    (rule) => rule?.if?.properties?.STATUS?.const === 'RETRYABLE_ERROR'
  );
  assert.ok(retryRule, 'RETRYABLE_ERROR conditional rule is missing');
  assert.ok(retryRule.then.required.includes('IDEMPOTENCY_KEY'));
});

test('contract keeps queues separated and health checks non-destructive', async () => {
  const contract = await readFile(contractPath, 'utf8');
  for (const queue of requiredQueues) assert.match(contract, new RegExp(`\\b${queue}\\b`));
  assert.match(contract, /Health checks must not claim live jobs, send messages, publish content, or write customer data\./);
  assert.match(contract, /merge to `main`/);
  assert.match(contract, /production Apps Script or Vercel deployment/);
});
