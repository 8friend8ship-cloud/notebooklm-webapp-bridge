# Chrome Extension Automation Official Guide — 2026-08-29

Scope: canonical rules for managed Chrome-extension automation in this repository, derived from current Chrome for Developers documentation and the live NotebookLM bridge source.

## 1. Manifest V3 service worker

- Treat the service worker as disposable. It may stop after idle or lifecycle limits.
- Never keep task truth only in JS globals.
- Persist task ID, stage, timestamps and recovery state in `chrome.storage`.
- Register event listeners at top level.
- Long waits must be recoverable after worker restart.

Current NotebookLM bridge status: PASS. `local-powershell-runner.js` persists its ACTIVE record in `chrome.storage.local`, recreates its alarm on install/startup/worker load, and reconciles active queue/host state.

## 2. Alarms

- Use `chrome.alarms` instead of long `setTimeout`/`setInterval` scheduling for MV3 recovery loops.
- Current Chrome minimum alarm interval/delay is 30 seconds (`0.5` minutes). Values below `0.5` are not a reliable production contract.
- Device sleep does not wake because of an extension alarm; after wake, a missed repeating alarm fires at most once and is rescheduled.

Audit finding: `local-powershell-runner.js` currently creates the first alarm with `delayInMinutes:0.2` and `periodInMinutes:1`. The immediate explicit `poll()` calls already cover install/startup/worker-load, so this is not the root cause of `ASYNC_WRAPPER_EXITED_WITHOUT_RESULT`, but the delay should be normalized to `0.5` in the next runner source update.

## 3. Downloads

- `chrome.downloads` requires the `downloads` manifest permission.
- Use browser download events/API for browser-owned download tracking; never convert binary payloads to text as a storage shortcut.
- Treat `.crdownload`, `.part`, and temporary files as incomplete.
- Final asset integrity requires exact file size plus cryptographic hash readback.

Current NotebookLM manifest: PASS (`downloads` present).

## 4. Storage

- `chrome.storage` is available to extension service workers and content scripts.
- Persist recoverable state there rather than assuming a service worker remains alive.

Current NotebookLM manifest/runner: PASS (`storage` present; active/auth/session recovery uses storage).

## 5. Content scripts and scripting

- Content scripts execute in page-associated contexts and should use message contracts rather than assuming extension-worker globals.
- Dynamic injection through `chrome.scripting` requires the `scripting` permission plus the appropriate host permission or `activeTab` grant.
- Preserve exact target URLs and verify the target page before mutation.

Current NotebookLM manifest: PASS (`scripting` and service host permissions present).

## 6. Debugger / CDP

- `chrome.debugger` is the extension-side transport for the Chrome DevTools Protocol and requires the `debugger` permission.
- Do not add `debugger` merely because an external dedicated Chrome process is already being automated through a remote-debugging/CDP port.
- Add it only if the extension itself will call `chrome.debugger.attach/sendCommand`.

Current architecture: external dedicated-Chrome/CDP helpers perform the CDP work. Therefore absence of `debugger` in the NotebookLM extension manifest is intentional least privilege, not a defect.

## 7. Native messaging

- Native messaging requires a registered native host and `nativeMessaging` permission.
- On Windows, the host manifest is registered through the NativeMessagingHosts registry key and `allowed_origins` must contain exact extension origins/IDs.
- A native connection can be useful for a future HTTP-localhost replacement, but do not widen permissions while the current localhost host contract is still canonical.

Current architecture: `http://127.0.0.1:8765` host contract. Keep it until a deliberate native-messaging migration is tested end-to-end.

## 8. Current failure classification

`ASYNC_WRAPPER_EXITED_WITHOUT_RESULT` is emitted by Host 1.3.0 only after:

1. the host accepted the task,
2. a wrapper PID was launched,
3. the wrapper process later disappeared,
4. `result.json` did not exist.

Therefore this signature is a local wrapper/result durability failure, not proof of a Chrome MV3 service-worker shutdown or missing Chrome permission.

Minimum recovery rule:

- Keep the current browser/extension producer path unchanged.
- Add an independent raw-download capture lane for completed local files.
- Improve wrapper crash evidence separately; do not widen OAuth/Chrome permissions or duplicate queue jobs.

## 9. Python raw-download fallback

Canonical fallback source:

`local-agent/python/notebooklm_raw_download_capture.py`

Behavior:

1. ignores incomplete download suffixes,
2. waits until file size is stable,
3. reads magic bytes to determine binary media/document type,
4. uses binary-preserving `shutil.copy2`,
5. verifies source/destination SHA-256 and byte size,
6. writes an atomic JSON receipt.

Local self-test on 2026-08-29:

- status: `SELF_TEST_PASS`
- fixture: PNG
- size: 57 bytes
- SHA-256: `a948b5cccd6fc32a557c9cf6d5a2b79882e6a9acb67d8158f49ecbfd99ef16a9`
- detected MIME: `image/png`

GitHub commit introducing the fallback: `1ec7ab77e150634ae77fbdde840ca851c47dce67`.

## 10. Reusable automation checklist for every managed extension

Before execution:

1. Read actual `manifest.json` and classify architecture: MV3 worker, content-script/popup, or mixed.
2. Verify only required permissions: downloads/storage/alarms/scripting/host permissions as applicable.
3. Do not require `debugger` unless the extension itself uses `chrome.debugger`.
4. Do not require `nativeMessaging` unless a registered native host is actually used.
5. Persist workflow truth outside volatile worker globals.
6. Use alarms at Chrome-supported cadence; minimum `0.5` minute.
7. Verify exact target URL/context before browser mutation.
8. For downloads, wait for completion and preserve original bytes.
9. Require size + SHA + MIME/type readback before Drive/Seed promotion.
10. On failure, store the exact layer/signature and apply the minimum changed-condition fix before retry.

## Next runtime gate

One real NotebookLM browser download on the Windows device must complete and then be consumed by the Python raw-download fallback into the Google Drive Desktop synced destination. PASS requires two consecutive runs with matching source/destination size and SHA-256, correct binary MIME detection, and Drive readback. Until then, source/static/local self-test is PASS but device E2E remains pending.
