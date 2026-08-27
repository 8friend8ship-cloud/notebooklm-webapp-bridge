import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const mirrorJs = fs.readFileSync('notebooklm-webapp-bridge-source-v0.2.0/extension/artifact-drive-mirror.js', 'utf8');
const mirrorPs = fs.readFileSync('local-agent/governor/MirrorNotebookLMArtifactToDrive.ps1', 'utf8');
const watcherPs = fs.readFileSync('local-agent/governor/WatchNotebookLMDownloadsToCaptureBridge.ps1', 'utf8');

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

test('FileSystemWatcher route is fallback-only and waits for a stable complete file', () => {
  assert.match(watcherPs, /FALLBACK_ONLY/);
  assert.match(watcherPs, /Register-ObjectEvent/);
  assert.match(watcherPs, /Wait-StableFile/);
  assert.match(watcherPs, /\$Event\.SourceEventArgs\.FullPath/);
  assert.match(watcherPs, /\.crdownload/);
  assert.match(watcherPs, /Copy-Item/);
  assert.doesNotMatch(watcherPs, /Move-Item/);
});
