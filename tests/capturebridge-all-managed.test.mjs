import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const managerPath = 'local-agent/capture/ManageChromeExtensionArtifacts.ps1';
const setupPath = 'local-agent/capture/Setup-ChromeExtensionCaptureBridge.ps1';
const manager = fs.readFileSync(managerPath, 'utf8');
const setup = fs.readFileSync(setupPath, 'utf8');

function blobSha(path) {
  return execFileSync('git', ['rev-parse', `HEAD:${path}`], { encoding: 'utf8' }).trim().toLowerCase();
}

test('managed Chrome capture accepts current and future explicit service adapters without generic Downloads scanning', () => {
  assert.match(manager, /ValidatePattern\('\^\[A-Za-z0-9_\.\-\]\{1,64\}\$'\)/);
  assert.match(manager, /'NotebookLM'/);
  assert.match(manager, /'Flow'/);
  assert.match(manager, /'AIStudio'/);
  assert.match(manager, /'GoogleAI'/);
  assert.match(manager, /'FrontQA'/);
  assert.match(manager, /'SketchUp'/);
  assert.match(manager, /knownProfile = \$false/);
  assert.match(manager, /EXPLICIT_SOURCE_PATH_OR_EXPLICIT_SERVICE_INBOX_ONLY/);
  assert.match(manager, /genericDownloadsScan = \$false/);
  assert.match(manager, /Copy-Item/);
  assert.doesNotMatch(manager, /Move-Item/);
});

test('setup installs a five-minute dynamic reconciler and smokes every registered lane plus a future adapter', () => {
  assert.match(setup, /\[string\]\$ManagerRef = 'main'/);
  assert.match(setup, /NotebookLM','Flow','AIStudio','GoogleAI','FrontQA','SketchUp/);
  assert.match(setup, /Get-ChildItem -LiteralPath `\$LocalInboxRoot -Directory/);
  assert.match(setup, /Sort-Object -Unique/);
  assert.match(setup, /\/SC MINUTE \/MO 5/);
  assert.match(setup, /FutureManagedExtension/);
  assert.match(setup, /dynamicInboxDiscovery = \$true/);
  assert.match(setup, /genericDownloadsSync = \$false/);
  assert.match(setup, /copyOnly = \$true/);
});

test('setup pins the exact manager repository blob', () => {
  const expected = setup.match(/\$ManagerExpected = '([0-9a-f]{40})'/i)?.[1];
  assert.ok(expected, 'ManagerExpected missing');
  assert.equal(expected.toLowerCase(), blobSha(managerPath));
});
