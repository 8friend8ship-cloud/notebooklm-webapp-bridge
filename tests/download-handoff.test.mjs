import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const mirrorJs = fs.readFileSync('notebooklm-webapp-bridge-source-v0.2.0/extension/artifact-drive-mirror.js', 'utf8');
const backgroundJs = fs.readFileSync('notebooklm-webapp-bridge-source-v0.2.0/extension/background.js', 'utf8');
const mirrorPs = fs.readFileSync('local-agent/governor/MirrorNotebookLMArtifactToDrive.ps1', 'utf8');
const watcherPs = fs.readFileSync('local-agent/governor/WatchNotebookLMDownloadsToCaptureBridge.ps1', 'utf8');
const agent30Path = 'local-agent/releases/1.1.30/HomeDesignLocalAgent.ps1';
const agent30Ps = fs.readFileSync(agent30Path, 'utf8');
const host125Path = 'local-agent/releases/1.2.5/HomeDesignLocalCommandHost.ps1';
const agent31Path = 'local-agent/releases/1.1.31/HomeDesignLocalAgent.ps1';
const agent31Ps = fs.readFileSync(agent31Path, 'utf8');
const agent32Path = 'local-agent/releases/1.1.32/HomeDesignLocalAgent.ps1';
const agent32Ps = fs.readFileSync(agent32Path, 'utf8');
const agent33Path = 'local-agent/releases/1.1.33/HomeDesignLocalAgent.ps1';
const agent33Ps = fs.readFileSync(agent33Path, 'utf8');
const agent34Path = 'local-agent/releases/1.1.34/HomeDesignLocalAgent.ps1';
const agent34Ps = fs.readFileSync(agent34Path, 'utf8');
const agent35Path = 'local-agent/releases/1.1.35/HomeDesignLocalAgent.ps1';
const agent35Ps = fs.readFileSync(agent35Path, 'utf8');
const host126Path = 'local-agent/releases/1.2.6/HomeDesignLocalCommandHost.ps1';
const host127Path = 'local-agent/releases/1.2.7/HomeDesignLocalCommandHost.ps1';
const stableAgent = JSON.parse(fs.readFileSync('local-agent/stable/agent.json', 'utf8'));
const stableBridge = JSON.parse(fs.readFileSync('runtime/stable/release.json', 'utf8'));

function repositoryBlobSha1(path) {
  return execFileSync('git', ['rev-parse', `HEAD:${path}`], { encoding: 'utf8' }).trim().toLowerCase();
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

test('Local Agent 1.1.30 restores Host 1.2.5 before AutoResume and stable Bridge and records failures', () => {
  assert.match(agent30Ps, /\$AgentVersion='1\.1\.30'/);
  assert.match(agent30Ps, /\$HostVersion='1\.2\.5'/);
  assert.match(agent30Ps, /function EnsureHost125/);
  assert.match(agent30Ps, /RefreshVerified \$HostUrl \$HostFile \$HostExpected/);
  assert.match(agent30Ps, /StartHost125/);
  assert.match(agent30Ps, /EnsureHost125.*EnsureAutoResume.*GetRelease/s);
  assert.match(agent30Ps, /PersistState \$failure/);
  assert.match(agent30Ps, /WriteCentral 'AGENT_1\.1\.30_RECOVERY\.json'/);
  assert.doesNotMatch(agent30Ps, /EXISTING_HOST_NOT_HEALTHY/);
});

test('Local Agent 1.1.31 targets Host 1.2.6 managed CaptureBridge allowlist', () => {
  assert.match(agent31Ps, /1\.1\.31/);
  assert.match(agent31Ps, /1\.2\.6/);
  assert.match(agent31Ps, /5d17bb233706897cd1706930cea9af3796f29488/);
  const host126Ps = fs.readFileSync(host126Path, 'utf8');
  assert.match(host126Ps, /1\.2\.6/);
  assert.match(host126Ps, /local-agent\/capture\/ManageChromeExtensionArtifacts\.ps1/);
  assert.match(host126Ps, /local-agent\/capture\/Setup-ChromeExtensionCaptureBridge\.ps1/);
});

test('Local Agent 1.1.32 adds a guarded dedicated control-center wake over Host 1.2.6 lineage', () => {
  assert.match(agent32Ps, /1\.1\.32/);
  assert.match(agent32Ps, /1\.2\.6/);
  assert.match(agent32Ps, /AGENT_1\.1\.32_CONTROL_CENTER_WAKE\.attempted/);
  assert.match(agent32Ps, /normalChromeUntouched=\$true/);
  assert.match(agent32Ps, /newOAuth=\$false/);
  assert.match(agent32Ps, /newScope=\$false/);
  assert.doesNotMatch(agent32Ps, /Stop-Process.+chrome/i);
  assert.doesNotMatch(agent32Ps, /taskkill.+chrome/i);
});

test('Local Agent 1.1.33 diagnoses prior 1.1.32 wake before performing any changed-condition wake', () => {
  assert.match(agent33Ps, /1\.1\.33/);
  assert.match(agent33Ps, /1\.2\.6/);
  assert.match(agent33Ps, /AGENT_1\.1\.32_CONTROL_CENTER_WAKE\.attempted/);
  assert.match(agent33Ps, /prior132MarkerPresent/);
  assert.match(agent33Ps, /prior132LocalEvidencePresent/);
  assert.match(agent33Ps, /PRIOR_1\.1\.32_WAKE_MARKER_PRESENT_NO_REPEAT/);
  assert.match(agent33Ps, /AGENT_1\.1\.33_EXTENSION_WAKE_DIAGNOSTIC\.attempted/);
  assert.match(agent33Ps, /AGENT_1\.1\.33_EXTENSION_WAKE_DIAGNOSTIC\.json/);
  assert.match(agent33Ps, /normalChromeUntouched=\$true/);
  assert.match(agent33Ps, /tokenContentsRead=\$false/);
  assert.match(agent33Ps, /newOAuth=\$false/);
  assert.match(agent33Ps, /newScope=\$false/);
  assert.doesNotMatch(agent33Ps, /Stop-Process.+chrome/i);
  assert.doesNotMatch(agent33Ps, /taskkill.+chrome/i);
});

test('Local Agent 1.1.34 pins Host 1.2.7 with exact ContentOS repair allowlist', () => {
  assert.match(agent34Ps, /1\.1\.34/);
  assert.match(agent34Ps, /1\.2\.7/);
  assert.match(agent34Ps, /ac4aae953fae2219d393de2307ef655b0988c9f4/);
  assert.match(agent34Ps, /CONTENTOS_REPAIR_ALLOWLIST_READY/);
  assert.match(agent34Ps, /tools\/Repair-ContentOS-DriveCacheAppsScript\.ps1/);
  assert.match(agent34Ps, /newOAuth=\$false/);
  assert.match(agent34Ps, /newScope=\$false/);
  const host127Ps = fs.readFileSync(host127Path, 'utf8');
  assert.equal(repositoryBlobSha1(host127Path), 'ac4aae953fae2219d393de2307ef655b0988c9f4');
  assert.match(host127Ps, /tools\/Switch-ContentOS-VercelGit\.ps1/);
  assert.match(host127Ps, /tools\/Repair-ContentOS-DriveCacheAppsScript\.ps1/);
  assert.doesNotMatch(host127Ps, /contents-os-git[^\n]+scripts=@\([^\)]*\*/);
});

test('Local Agent 1.1.35 uses official Host async API for one fixed idempotent ContentOS task203', () => {
  assert.match(agent35Ps, /1\.1\.35/);
  assert.match(agent35Ps, /1\.2\.7/);
  assert.match(agent35Ps, /CONTENTOS_RUNTIME_TASK203_HOST_DIRECT_D115_20260828_01/);
  assert.match(agent35Ps, /http:\/\/127\.0\.0\.1:8765/);
  assert.match(agent35Ps, /\/health/);
  assert.match(agent35Ps, /\/run/);
  assert.match(agent35Ps, /\/result\?taskId=/);
  assert.match(agent35Ps, /taskType='LOCAL_POWERSHELL'/);
  assert.match(agent35Ps, /tools\/Repair-ContentOS-DriveCacheAppsScript\.ps1/);
  assert.match(agent35Ps, /timeoutSeconds=600/);
  assert.match(agent35Ps, /idempotent=\$true/);
  assert.match(agent35Ps, /AGENT_1\.1\.35_CONTENTOS_TASK203_DIRECT\.json/);
  assert.match(agent35Ps, /AGENT_1\.1\.35_CONTENTOS_TASK203_SUBMITTED\.json/);
  assert.match(agent35Ps, /newOAuth=\$false/);
  assert.match(agent35Ps, /newScope=\$false/);
  assert.match(agent35Ps, /newProject=\$false/);
  assert.match(agent35Ps, /newDeployment=\$false/);
  assert.match(agent35Ps, /newTrigger=\$false/);
  assert.match(agent35Ps, /vercelAction=\$false/);
  assert.doesNotMatch(agent35Ps, /LOCAL_POWERSHELL_ASYNC/);
  assert.doesNotMatch(agent35Ps, /Stop-Process.+chrome/i);
  assert.doesNotMatch(agent35Ps, /taskkill.+chrome/i);
  assert.equal((agent35Ps.match(/CONTENTOS_RUNTIME_TASK203_HOST_DIRECT_D115_20260828_01/g) || []).length, 1);
});

test('Stable Agent manifest points to its exact release blob and pinned Host/direct route', () => {
  assert.ok(['1.1.30', '1.1.31', '1.1.32', '1.1.33', '1.1.34', '1.1.35'].includes(stableAgent.version), `unexpected stable agent ${stableAgent.version}`);
  const stableAgentPath = `local-agent/releases/${stableAgent.version}/HomeDesignLocalAgent.ps1`;
  assert.equal(stableAgent.gitBlobSha1.toLowerCase(), repositoryBlobSha1(stableAgentPath));
  const stableAgentPs = fs.readFileSync(stableAgentPath, 'utf8');
  if (stableAgent.version === '1.1.35') {
    assert.equal(repositoryBlobSha1(agent35Path), 'e27b760b67933be05a5d6f1ac0af1afd6158b32b');
    assert.match(stableAgentPs, /CONTENTOS_RUNTIME_TASK203_HOST_DIRECT_D115_20260828_01/);
    assert.match(stableAgentPs, /taskType='LOCAL_POWERSHELL'/);
    assert.match(stableAgentPs, /\/run/);
    assert.match(stableAgentPs, /\/result\?taskId=/);
  } else if (stableAgent.version === '1.1.34') {
    assert.equal(repositoryBlobSha1(host127Path), 'ac4aae953fae2219d393de2307ef655b0988c9f4');
    assert.match(stableAgentPs, /local-agent\/releases\/1\.2\.7\/HomeDesignLocalCommandHost\.ps1/);
    assert.match(stableAgentPs, /ac4aae953fae2219d393de2307ef655b0988c9f4/);
    assert.match(stableAgentPs, /CONTENTOS_REPAIR_ALLOWLIST_READY/);
  } else if (stableAgent.version === '1.1.33') {
    assert.equal(repositoryBlobSha1(host126Path), '5d17bb233706897cd1706930cea9af3796f29488');
    assert.match(stableAgentPs, /local-agent\/releases\/1\.2\.6\/HomeDesignLocalCommandHost\.ps1/);
    assert.match(stableAgentPs, /5d17bb233706897cd1706930cea9af3796f29488/);
    assert.match(stableAgentPs, /PRIOR_1\.1\.32_WAKE_MARKER_PRESENT_NO_REPEAT/);
    assert.match(stableAgentPs, /AGENT_1\.1\.33_EXTENSION_WAKE_DIAGNOSTIC\.json/);
  } else if (stableAgent.version === '1.1.32') {
    assert.equal(repositoryBlobSha1(host126Path), '5d17bb233706897cd1706930cea9af3796f29488');
    assert.match(stableAgentPs, /local-agent\/releases\/1\.2\.6\/HomeDesignLocalCommandHost\.ps1/);
    assert.match(stableAgentPs, /5d17bb233706897cd1706930cea9af3796f29488/);
    assert.match(stableAgentPs, /AGENT_1\.1\.32_CONTROL_CENTER_WAKE\.attempted/);
    assert.match(stableAgentPs, /normalChromeUntouched=\$true/);
  } else if (stableAgent.version === '1.1.31') {
    assert.equal(repositoryBlobSha1(host126Path), '5d17bb233706897cd1706930cea9af3796f29488');
    assert.match(stableAgentPs, /local-agent\/releases\/1\.2\.6\/HomeDesignLocalCommandHost\.ps1/);
    assert.match(stableAgentPs, /5d17bb233706897cd1706930cea9af3796f29488/);
    assert.ok(stableAgentPs.includes('e6a79fbb113a79e19650b2864072f6abde5bcffb'), 'Agent 1.1.31 wrapper must identify the prior Host 1.2.5 pin');
    assert.ok(stableAgentPs.includes('HostExpected'), 'Agent 1.1.31 wrapper must patch HostExpected');
  } else {
    const hostExpected = stableAgentPs.match(/\$HostExpected='([0-9a-f]{40})'/i)?.[1];
    assert.ok(hostExpected, 'Agent 1.1.30 must pin HostExpected');
    assert.equal(hostExpected.toLowerCase(), repositoryBlobSha1(host125Path));
    assert.match(stableAgentPs, /local-agent\/releases\/1\.2\.5\/HomeDesignLocalCommandHost\.ps1/);
  }
});

test('Stable Bridge 0.2.71 release hashes match every declared repository blob', () => {
  assert.equal(stableBridge.version, '0.2.71');
  assert.equal(stableBridge.requiresUserApproval, false);
  assert.ok(Array.isArray(stableBridge.files) && stableBridge.files.length > 0);
  for (const file of stableBridge.files) {
    const path = `notebooklm-webapp-bridge-source-v0.2.0/extension/${file.path}`;
    assert.ok(fs.existsSync(path), `stable release file missing: ${file.path}`);
    assert.equal(repositoryBlobSha1(path), file.gitBlobSha1.toLowerCase(), `stable release SHA mismatch: ${file.path}`);
  }
});
