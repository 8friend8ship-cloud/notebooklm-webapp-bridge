import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';

const mirrorJs = fs.readFileSync('notebooklm-webapp-bridge-source-v0.2.0/extension/artifact-drive-mirror.js', 'utf8');
const backgroundJs = fs.readFileSync('notebooklm-webapp-bridge-source-v0.2.0/extension/background.js', 'utf8');
const mirrorPs = fs.readFileSync('local-agent/governor/MirrorNotebookLMArtifactToDrive.ps1', 'utf8');
const watcherPs = fs.readFileSync('local-agent/governor/WatchNotebookLMDownloadsToCaptureBridge.ps1', 'utf8');
const agent29Path = 'local-agent/releases/1.1.29/HomeDesignLocalAgent.ps1';
const agent29Ps = fs.readFileSync(agent29Path, 'utf8');
const host124Path = 'local-agent/releases/1.2.4/HomeDesignLocalCommandHost.ps1';
const stableAgent = JSON.parse(fs.readFileSync('local-agent/stable/agent.json', 'utf8'));
const stableBridge = JSON.parse(fs.readFileSync('runtime/stable/release.json', 'utf8'));

function gitBlobSha1(path) {
  const body = fs.readFileSync(path);
  return crypto.createHash('sha1').update(Buffer.from(`blob ${body.length}\0`)).update(body).digest('hex');
}

test('Chrome mirror resolves a completed download and forwards exact SourcePath', () => {
  assert.match(mirrorJs, /chrome\.downloads\.search/);
  assert.match(mirrorJs, /nlmFindCompletedDownload/);
  assert.match(mirrorJs, /SourcePath:\s*String\(sourcePath/);
  assert.match(mirrorJs, /\.crdownload/);
  assert.match(mirrorJs, /state !== "complete"/);
});

test('PowerShell mirror prefers exact SourcePath but retains legacy scan fallback', () => {
  assert.match(mirrorPs, /\[string\]\$SourcePath\s*=\s*''/);
  assert.match(mirrorPs, /EXACT_SOURCE_PATH/);
  assert.match(mirrorPs, /LEGACY_SCAN_FALLBACK/);
  assert.match(mirrorPs, /NOTEBOOKLM_EXACT_SOURCE_ZERO_BYTES/);
  assert.match(mirrorPs, /Copy-Item/);
  assert.doesNotMatch(mirrorPs, /Move-Item/);
});

test('FileSystemWatcher route is fallback-only and waits synchronously for a stable complete file', () => {
  assert.match(watcherPs, /FALLBACK_ONLY/);
  assert.match(watcherPs, /WaitForChanged/);
  assert.match(watcherPs, /SYNCHRONOUS_WAIT_FOR_CHANGED/);
  assert.match(watcherPs, /Wait-StableFile/);
  assert.match(watcherPs, /\.crdownload/);
  assert.match(watcherPs, /Copy-Item/);
  assert.doesNotMatch(watcherPs, /Register-ObjectEvent/);
  assert.doesNotMatch(watcherPs, /Move-Item/);
});

test('Existing verified download synthesizes exact SourcePath mirror request', () => {
  assert.match(backgroundJs, /actualArtifact\?\.downloadEvidence\?\.download/);
  assert.match(backgroundJs, /verifiedDownload\?\.filename/);
  assert.match(backgroundJs, /sourcePath:\s*verifiedDownload\.filename/);
  assert.match(backgroundJs, /sourcePath:\s*String\(mirrorReq\.sourcePath/);
});

test('Local Agent 1.1.29 restores Host before applying stable Bridge and records failures', () => {
  assert.match(agent29Ps, /\$AgentVersion='1\.1\.29'/);
  assert.match(agent29Ps, /function EnsureHost124/);
  assert.match(agent29Ps, /RefreshVerified \$HostUrl \$HostFile \$HostExpected/);
  assert.match(agent29Ps, /StartHost124/);
  assert.match(agent29Ps, /EnsureAutoResume.*EnsureHost124.*GetRelease/s);
  assert.match(agent29Ps, /PersistState \$failure/);
  assert.match(agent29Ps, /WriteCentral 'AGENT_1\.1\.29_RECOVERY\.json'/);
  assert.doesNotMatch(agent29Ps, /EXISTING_HOST_NOT_HEALTHY/);
});

test('Stable Agent manifest points to the exact 1.1.29 blob and verified Host 1.2.4 blob', () => {
  assert.equal(stableAgent.version, '1.1.29');
  assert.equal(stableAgent.gitBlobSha1, gitBlobSha1(agent29Path));
  const hostExpected = agent29Ps.match(/\$HostExpected='([0-9a-f]{40})'/i)?.[1];
  assert.ok(hostExpected, 'Agent must pin HostExpected');
  assert.equal(hostExpected.toLowerCase(), gitBlobSha1(host124Path));
  assert.match(agent29Ps, /local-agent\/releases\/1\.2\.4\/HomeDesignLocalCommandHost\.ps1/);
});

test('Stable Bridge 0.2.71 release hashes match every declared extension file', () => {
  assert.equal(stableBridge.version, '0.2.71');
  assert.equal(stableBridge.requiresUserApproval, false);
  assert.ok(Array.isArray(stableBridge.files) && stableBridge.files.length > 0);
  for (const file of stableBridge.files) {
    const path = `notebooklm-webapp-bridge-source-v0.2.0/extension/${file.path}`;
    assert.ok(fs.existsSync(path), `stable release file missing: ${file.path}`);
    assert.equal(gitBlobSha1(path), file.gitBlobSha1, `stable release SHA mismatch: ${file.path}`);
  }
});
