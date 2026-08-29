import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const ps = fs.readFileSync('local-agent/governor/MirrorNotebookLMArtifactToDrive.ps1', 'utf8');
const js = fs.readFileSync('notebooklm-webapp-bridge-source-v0.2.0/extension/artifact-drive-mirror.js', 'utf8');

test('PowerShell mirror detects native image signatures and repairs generic extensions', () => {
  assert.match(ps, /Get-DetectedExtension/);
  assert.match(ps, /0x89[\s\S]*0x50[\s\S]*0x4E[\s\S]*0x47/);
  assert.match(ps, /0xFF[\s\S]*0xD8[\s\S]*0xFF/);
  assert.match(ps, /RIFF/);
  assert.match(ps, /WEBP/);
  assert.match(ps, /extensionRepaired/);
  assert.match(ps, /resolvedExtension/);
});

test('generic .dat/.bin downloads are handed to binary validation instead of being discarded', () => {
  assert.match(js, /\.dat/);
  assert.match(js, /\.bin/);
  assert.match(js, /nlmArtifactIsGenericExtension/);
  assert.match(js, /ARTIFACT_NATIVE_FILE_NOT_VERIFIED/);
});

test('native artifact destination keeps binary bytes and corrected extension', () => {
  assert.match(ps, /Copy-Item -LiteralPath \$localCaptured\.FullName -Destination \$destPath -Force/);
  assert.match(ps, /destinationBytes/);
  assert.match(ps, /destinationName/);
});
