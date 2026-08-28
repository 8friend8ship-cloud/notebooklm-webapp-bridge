# D82 → Central Chat Factory automation handoff — 2026-08-28

The existing hourly NotebookLM E2E Watch is the release controller for local task `LOCAL_CENTRAL_CHAT_FACTORY_SYNC_20260828_1332_01`.

Current state: `HOLD_RECOVERY` / `HOLD_PRECHECK_D82_DEVICE_READBACK`.

Release sequence:
1. detect fresh physical device readback after the stale 2026-08-27 18:57 KST baseline;
2. verify healthy Host/LocalAgent/dedicated-device state using the current central target contract;
3. continue existing D82 task exactly once and preserve all prior failures;
4. ensure no local task is CLAIMED or STARTED;
5. change the same row-285 task from HOLD_RECOVERY to READY once — never create a duplicate;
6. the task runs `RunCentralChatFactorySyncAfterD82Gate.ps1`, which independently rechecks Host/Agent freshness before any clasp operation;
7. the guarded sync reuses existing clasp auth only, requires exactly one WEBAPP_TEMPLATE_03 project and the known existing Deployment ID, syncs only CentralChatWorkFactory.gs, and requires pull/hash readback;
8. trigger installation and the same factory function must run twice, followed by central 34/07/59/35/77/80/83 readback before VERIFIED.

Stop on new OAuth/scope/permission, missing auth, ambiguous project, deployment mismatch, hash mismatch, or execution API gate. Vercel deployment rate limiting is tracked separately and must not cause blind redeploy.
