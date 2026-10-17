import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const path = new URL('../apps-script/DriveAutoClassifySeedWriteback10m.gs', import.meta.url);
const source = fs.readFileSync(path, 'utf8');

function load() {
  const context = {};
  vm.createContext(context);
  vm.runInContext(source, context, {filename:'DriveAutoClassifySeedWriteback10m.gs'});
  return context;
}

test('handler is logical 10m and never creates a new physical trigger', () => {
  assert.match(source, /function runDriveAutoClassifySeedWriteback10m\(/);
  assert.match(source, /DRIVE_AUTO_CLASSIFY_BUCKET_MS\s*=\s*10\s*\*\s*60\s*\*\s*1000/);
  assert.match(source, /IDEMPOTENT_10M_BUCKET/);
  assert.doesNotMatch(source, /ScriptApp\s*\.\s*newTrigger/);
  assert.doesNotMatch(source, /ScriptApp\s*\.\s*deleteTrigger/);
});

test('10m bucket is stable within a bucket and advances at 600000ms', () => {
  const ctx = load();
  assert.equal(ctx.driveAutoClassifyBucket10mV1_(0), 0);
  assert.equal(ctx.driveAutoClassifyBucket10mV1_(599999), 0);
  assert.equal(ctx.driveAutoClassifyBucket10mV1_(600000), 1);
  assert.equal(ctx.driveAutoClassifyBucket10mV1_(1199999), 1);
});

test('classifier preserves original artifact family without text conversion', () => {
  const ctx = load();
  assert.equal(ctx.driveAutoClassifyTypeV1_({mimeType:'image/png',name:'x.png'}), 'IMAGE');
  assert.equal(ctx.driveAutoClassifyTypeV1_({mimeType:'audio/mp4',name:'x.m4a'}), 'AUDIO');
  assert.equal(ctx.driveAutoClassifyTypeV1_({mimeType:'application/pdf',name:'x.pdf'}), 'PDF');
  assert.equal(ctx.driveAutoClassifyTypeV1_({mimeType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',name:'x.xlsx'}), 'SHEET');
  assert.equal(ctx.driveAutoClassifyTypeV1_({mimeType:'application/zip',name:'x.zip'}), 'ARCHIVE');
});

test('promotion is fail-closed through inventory and Queens candidate first', () => {
  assert.match(source, /23_FILE_ASSET_INVENTORY/);
  assert.match(source, /37_QUEENS_RESEARCH_RESULTS/);
  assert.match(source, /CANDIDATE_REVIEW_REQUIRED/);
  assert.match(source, /NO_AUTO_SEED_PROMOTION/);
  assert.match(source, /runCentralMediaQaSeedLoop/);
});

test('existing 5m factory wake hook exists without trigger duplication', () => {
  assert.match(source, /function runDriveAutoClassifySeedWriteback10mFromFactoryV1\(/);
  assert.match(source, /source:'processTaskQueue'/);
  assert.match(source, /TRG_DRIVE_AUTO_CLASSIFY_SEED_REUSE_20260831/);
});
