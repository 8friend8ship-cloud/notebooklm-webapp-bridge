import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

const bootstrapDir = join(process.cwd(), 'local-agent', 'bootstrap');

test('PowerShell bootstrap scripts separate throw keyword from string literals', async () => {
  const files = (await readdir(bootstrapDir)).filter((name) => name.endsWith('.ps1'));
  const bad = [];
  for (const name of files) {
    const text = await readFile(join(bootstrapDir, name), 'utf8');
    const lines = text.split(/\r?\n/);
    lines.forEach((line, index) => {
      if (/\bthrow'/.test(line)) bad.push(`${name}:${index + 1}:${line.trim()}`);
    });
  }
  assert.deepEqual(bad, [], `Invalid PowerShell throw tokenization:\n${bad.join('\n')}`);
});
