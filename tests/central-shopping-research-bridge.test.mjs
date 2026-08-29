import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const extDir = path.join(root, 'extensions', 'central-shopping-research-bridge');

const read = (name) => fs.readFileSync(path.join(extDir, name), 'utf8');

test('shopping bridge manifest uses bounded provider hosts and no identity/cookies permission', () => {
  const manifest = JSON.parse(read('manifest.json'));
  assert.equal(manifest.manifest_version, 3);
  assert.deepEqual(manifest.permissions.sort(), ['downloads', 'storage']);
  assert.ok(manifest.host_permissions.some((v) => v.includes('coupang.com')));
  assert.ok(manifest.host_permissions.some((v) => v.includes('aliexpress.com')));
  assert.ok(manifest.host_permissions.some((v) => v.includes('amazon.com')));
  assert.equal(manifest.permissions.includes('cookies'), false);
  assert.equal(manifest.permissions.includes('identity'), false);
  assert.equal(manifest.permissions.includes('webRequest'), false);
});

test('shopping review collector remains bounded and fail-closed', () => {
  const content = read('content.js');
  assert.match(content, /MAX_SCROLLS\s*=\s*16/);
  assert.match(content, /MAX_REVIEWS\s*=\s*100/);
  assert.match(content, /noLoginAutomation:\s*true/);
  assert.match(content, /noCaptchaBypass:\s*true/);
  assert.match(content, /noReviewerIdentity:\s*true/);
  assert.match(content, /singleReviewNeverFact:\s*true/);
  assert.match(content, /verifiedDeliverable:\s*null/);
});

test('central contract requires verified availability before recommendation', () => {
  const contract = JSON.parse(fs.readFileSync(path.join(root, 'central-agent', 'shopping-bridge.contract.json'), 'utf8'));
  assert.equal(contract.bridgeId, 'BRG_032');
  assert.equal(contract.recommendationGate.livePriceRequired, true);
  assert.equal(contract.recommendationGate.deliveryOrBookingAvailabilityRequired, true);
  assert.equal(contract.recommendationGate.unknownAvailabilityCannotWin, true);
  assert.equal(contract.recommendationGate.showReason, true);
  assert.equal(contract.runtimeGate.localExtensionX2, true);
  assert.equal(contract.runtimeGate.driveReadbackX2, true);
  assert.ok(contract.eligibleApps.APP_KFOOD);
  assert.ok(contract.eligibleApps.APP_INTERIOR);
  assert.ok(contract.eligibleApps.APP_TRAVEL);
});
