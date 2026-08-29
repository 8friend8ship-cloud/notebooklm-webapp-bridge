import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const ps = fs.readFileSync('local-agent/governor/MirrorNotebookLMArtifactQueensFirst.ps1', 'utf8');
const js = fs.readFileSync('notebooklm-webapp-bridge-source-v0.2.0/extension/artifact-drive-mirror.js', 'utf8');

test('Queens-first gate preserves native source and requires nonzero original', () => {
  assert.match(ps, /SOURCE_IMMUTABLE_VIOLATION/);
  assert.match(ps, /QUEENS_NATIVE_ORIGINAL_ZERO_BYTES/);
  assert.match(ps, /nativeOriginalVerified = \$true/);
  assert.match(ps, /sourceImmutable = \$true/);
});

test('Queens-first gate hashes native original and writes QUEENS_INBOX sidecar', () => {
  assert.match(ps, /Get-FileHash/);
  assert.match(ps, /SHA256/);
  assert.match(ps, /QUEENS_INBOX/);
  assert.match(ps, /\.capture\.json/);
  assert.match(ps, /assetId = \$assetId/);
});

test('Seed stays ineligible until Queens URL readback is verified', () => {
  assert.match(ps, /queensUrlVerified = \$false/);
  assert.match(ps, /seedDerivativeAllowed = \$false/);
  assert.match(ps, /seedDerivativeVerified = \$false/);
  assert.match(ps, /seedEligible = \$false/);
  assert.match(ps, /johnsonDeliveryAllowed = \$false/);
  assert.match(ps, /nextGate = 'QUEENS_URL_VERIFIED'/);
  assert.doesNotMatch(ps, /seedDerivativeAllowed = \$true/);
});

test('PowerShell script chaining does not trust LASTEXITCODE for the base mirror', () => {
  assert.doesNotMatch(ps, /\$exitCode\s*=\s*\$LASTEXITCODE/);
  assert.match(ps, /NOTEBOOKLM_BASE_MIRROR_NO_JSON/);
  assert.match(ps, /NOTEBOOKLM_BASE_MIRROR_NOT_OK/);
});

test('extension routes all mirrored artifacts through Queens-first registration', () => {
  assert.match(js, /MirrorNotebookLMArtifactQueensFirst\.ps1/);
  assert.match(js, /ARTIFACT_QUEENS_GATE_NOT_VERIFIED/);
  assert.match(js, /sourceImmutable/);
  assert.match(js, /nativeOriginalVerified/);
});

test('generic extension repair is limited to infographic downloads', () => {
  assert.match(js, /nlmArtifactAllowsGenericRepair/);
  assert.match(js, /toUpperCase\(\) === "INFOGRAPHIC"/);
  assert.match(js, /expected\.has\(ext\) \|\| \(allowGenericRepair && nlmArtifactIsGenericExtension\(ext\)\)/);
  assert.doesNotMatch(js, /return expected\.has\(ext\) \|\| nlmArtifactIsGenericExtension\(ext\)/);
});
