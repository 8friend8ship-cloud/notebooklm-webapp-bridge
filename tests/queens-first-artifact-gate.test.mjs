import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const ps = fs.readFileSync('local-agent/governor/MirrorNotebookLMArtifactQueensFirst.ps1', 'utf8');

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

test('Seed and Johnson are gated after native original preservation', () => {
  assert.match(ps, /seedDerivativeAllowed = \$true/);
  assert.match(ps, /seedDerivativeVerified = \$false/);
  assert.match(ps, /johnsonDeliveryAllowed = \$false/);
  assert.match(ps, /nextGate = 'QUEENS_URL_VERIFIED'/);
});
