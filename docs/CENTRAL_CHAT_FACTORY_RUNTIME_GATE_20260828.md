# Central Chat Work Factory runtime gate — 2026-08-28

## Current state
- CentralChatWorkFactory.gs is staged on PR #11.
- Local bound-sync task: `LOCAL_CENTRAL_CHAT_FACTORY_SYNC_20260828_1332_01` in WEBAPP_TEMPLATE_03 / NotebookLM_Task_Queue row 285.
- Task status is intentionally `HOLD_RECOVERY`, not READY.
- Latest Drive `VIDEO_LOCAL_RUNTIME_READBACK.json` is from 2026-08-27 18:57 KST and reports `SELF_HEAL_FAILED`, Agent 1.1.21, Host 1.2.3 healthy, Bridge 0.2.66. It is stale relative to the current target runtime.

## No-blind-retry lesson
Repeated attempts on 2026-08-25 to discover the WEBAPP_TEMPLATE_03 bound Apps Script ID through Chrome UI/CDP ended with `BOUND_SCRIPT_ID_NOT_FOUND`. That route is `DO_NOT_REPEAT` unless materially new evidence exists.

## Approved minimum route
1. Fresh dedicated-device runtime readback first.
2. No other local task may already be CLAIMED/STARTED.
3. Run `RunCentralChatFactorySyncAfterD82Gate.ps1`.
4. It requires Host `/health` ok and a recent healthy LocalAgent state before any clasp work.
5. Reuse existing clasp auth only.
6. Resolve exactly one `WEBAPP_TEMPLATE_03` project from clasp.
7. Clone current bound source and verify the known existing Deployment ID.
8. Add only `CentralChatWorkFactory.gs` and `clasp push`.
9. `clasp pull` and require exact hash readback.
10. Attempt `installCentralChatWorkFactoryTriggersV1` and the same `runCentralChatWorkFactoryV1` fixture twice.
11. Verify central 34/07/59/35/77/80/83 readback before VERIFIED.

## Stop conditions
Stop without changing runtime on any of these:
- stale or unhealthy device readback;
- missing existing clasp authentication;
- zero or multiple matching Apps Script projects;
- existing Deployment ID mismatch;
- new OAuth/scope/permission request;
- source/hash readback mismatch.

No new Apps Script project or deployment is created. No public deployment or PR merge is part of this runtime gate.

## Independent PR status note
Commit statuses currently show Vercel deployment rate-limit failures on both linked Vercel projects. This is classified as `INFRA_RATE_LIMIT`, not as evidence that the Apps Script helper code failed. Do not blind-redeploy to clear it.
