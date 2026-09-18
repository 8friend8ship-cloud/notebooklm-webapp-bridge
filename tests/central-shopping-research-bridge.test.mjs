import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const extDir = path.join(root, 'extensions', 'central-shopping-research-bridge');

const readExt = (name) => fs.readFileSync(path.join(extDir, name), 'utf8');
const readJson = (rel) => JSON.parse(fs.readFileSync(path.join(root, rel), 'utf8'));

test('shopping bridge manifest uses bounded provider hosts and no identity/cookies permission', () => {
  const manifest = JSON.parse(readExt('manifest.json'));
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
  const content = readExt('content.js');
  assert.match(content, /MAX_SCROLLS\s*=\s*16/);
  assert.match(content, /MAX_REVIEWS\s*=\s*100/);
  assert.match(content, /noLoginAutomation:\s*true/);
  assert.match(content, /noCaptchaBypass:\s*true/);
  assert.match(content, /noReviewerIdentity:\s*true/);
  assert.match(content, /singleReviewNeverFact:\s*true/);
  assert.match(content, /verifiedDeliverable:\s*null/);
});

test('central contract requires verified availability and covers ContentOS/VTube', () => {
  const contract = readJson('central-agent/shopping-bridge.contract.json');
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
  assert.ok(contract.eligibleApps.APP_CONTENT_OS);
  assert.ok(contract.eligibleApps.APP_VTUBE_1011B);
  assert.equal(contract.contentIntegration.publicPublish.includes('human-gated'), true);
});

test('front shopping template checks all-front content augmentation without forcing commerce', () => {
  const template = readJson('central-agent/front-shopping-needs.template.json');
  assert.equal(template.queensPlan.searchSeedFirst, true);
  assert.ok(template.appProfiles.APP_CONTENT_OS.includes('AFFILIATE_LINK_OPPORTUNITY'));
  assert.ok(template.appProfiles.APP_VTUBE_1011B.includes('VIDEO_PPL_OPPORTUNITY'));
  assert.equal(template.learningRules.doNotLearnFromAffiliateClickAlone, true);
  assert.equal(template.output.contentSlotOptional, true);
});

test('platform PPL policy requires disclosure and keeps public publish gated', () => {
  const policy = readJson('central-agent/platform-shopping-ppl.policy.json');
  assert.equal(policy.globalRules.noHiddenAdvertising, true);
  assert.equal(policy.globalRules.commercialRelationshipDisclosureRequired, true);
  assert.equal(policy.globalRules.publicPublishHumanGate, true);
  assert.equal(policy.globalRules.noMassSpamPosting, true);
  assert.match(policy.platformMatrix.YOUTUBE.ppl, /Paid product placements/);
  assert.match(policy.platformMatrix.TIKTOK.ppl, /commercial-content disclosure/);
  assert.match(policy.platformMatrix.PINTEREST.shopping, /Affiliate links/);
});

test('Apps Script orchestrator is logical, Seed-first and does not start public publishing', () => {
  const source = fs.readFileSync(path.join(root, 'apps-script', 'CentralShoppingContentOrchestrator.gs'), 'utf8');
  assert.match(source, /function evaluateFrontShoppingNeedV1/);
  assert.match(source, /function buildShoppingContentPackageV1/);
  assert.match(source, /function runCentralShoppingContentOrchestratorHourly/);
  assert.match(source, /function runCentralShoppingContentDailyLearningV1/);
  assert.match(source, /publicPublishHumanGate:true/);
  assert.match(source, /externalCrawlStarted:false/);
  assert.match(source, /publicPublishStarted:false/);
});
