import assert from 'node:assert/strict';
import { EXTENSION_ID, SELECTORS, normalizeTask, validateOutputSubfolder, validatePreflight } from '../local-agent/governor/chatgpt-image-auto-exact-adapter-v1.mjs';

assert.equal(EXTENSION_ID, 'gedfnhdibkfgacmkbjgpfjihacalnlpn');
assert.equal(SELECTORS.prompt, '#prompt-input');
assert.equal(SELECTORS.addQueue, '#add-to-queue-button');
assert.equal(SELECTORS.start, '#start-button');
assert.equal(SELECTORS.autoDownload, '#auto-download-input');
assert.equal(SELECTORS.downloadFolder, '#download-folder-input');
assert.equal(SELECTORS.ratio16x9, '[data-aspect-value="16:9"]');

const task = normalizeTask({ taskId: 'BIND08_CANARY_A_20260912', prompt: 'test prompt', aspectRatio: '16:9' });
assert.equal(task.outputSubfolder, 'ChatGPT-Auto/BIND08_BIND08_CANARY_A_20260912');
assert.throws(() => normalizeTask({ taskId: 'BAD', prompt: 'x', aspectRatio: '1:1' }), /TASK_ID_POLICY_MISMATCH|ONLY_16_9_CANARY_ALLOWED_V1/);
assert.throws(() => validateOutputSubfolder('../escape'), /UNSAFE_OUTPUT_SUBFOLDER|OUTPUT_SUBFOLDER_POLICY_MISMATCH/);
assert.throws(() => validateOutputSubfolder('C:/escape'), /UNSAFE_OUTPUT_SUBFOLDER/);

const ready = { ok:true, missing:[], running:false, queueJobs:0, pendingCollect:0, pendingDescriptors:0, authState:'ready', blocker:null };
assert.equal(validatePreflight(ready), true);
assert.throws(() => validatePreflight({ ...ready, running:true }), /EXTENSION_ALREADY_RUNNING/);
assert.throws(() => validatePreflight({ ...ready, queueJobs:1 }), /EXTENSION_QUEUE_NOT_EMPTY/);
assert.throws(() => validatePreflight({ ...ready, authState:'unknown' }), /CHATGPT_AUTH_NOT_READY/);
assert.throws(() => validatePreflight({ ...ready, missing:['#start-button'] }), /SELECTOR_MISSING/);
assert.throws(() => validatePreflight({ ...ready, blocker:'LOGIN_REQUIRED' }), /READINESS_BLOCKER/);

console.log('CHATGPT_IMAGE_EXACT_ADAPTER_SELFTEST_PASS');
