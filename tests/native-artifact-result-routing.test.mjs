import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const code = fs.readFileSync('notebooklm-webapp-bridge-source-v0.2.0/apps-script/Code.gs','utf8');
const runner = fs.readFileSync('notebooklm-webapp-bridge-source-v0.2.0/extension/local-powershell-runner.js','utf8');
const capture = fs.readFileSync('local-agent/capture/ManageChromeExtensionArtifacts.ps1','utf8');

test('Apps Script keeps receipt files separate from native artifact pointer', () => {
  assert.match(code, /resultLooksLikeNativeArtifact_/);
  assert.match(code, /chooseArtifactPointer_/);
  assert.match(code, /receiptJsonFileId/);
  assert.match(code, /artifactResult\?resultUrl:\(textFile\|\|file\)\.getUrl\(\)/);
  assert.match(code, /resultFileId=pointer\.resultFileId/);
  assert.doesNotMatch(code, /RESULT_FILE_ID:\(textFile\|\|file\)\.getId\(\),RESULT_TEXT/);
});

test('local async runner posts execution output as resultText, not as a claimed native file id', () => {
  assert.match(runner, /resultText:JSON\.stringify\(result,null,2\)/);
  assert.match(runner, /resultUrls:\[\]/);
});

test('generic capture bridge supports text outputs, so artifact-specific callers must gate native type separately', () => {
  assert.match(capture, /'\.txt'/);
  assert.match(capture, /'\.json'/);
  assert.match(capture, /Assert-VerifiedArtifact/);
});
