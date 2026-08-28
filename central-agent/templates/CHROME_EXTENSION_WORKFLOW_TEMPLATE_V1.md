# CHROME_EXTENSION_WORKFLOW_TEMPLATE_V1

This is the canonical template for every managed Chrome extension task.

## Mandatory PRE_CHECK
Read central instructions, work orders, History, Library, Error Learning, recent success/failure and LAST_GOOD before touching runtime. Resolve extension ID, service, profile, canonical source, current version, required site permission, CDP/Browser Use state, traffic lock and approval state. Existing CMD/PowerShell/OAuth/clasp/Local Agent/Host/Bridge/Queue/ScheduledTask approval is reused unless new failure evidence proves a new approval boundary.

## Execution chain
Inventory/manifest integrity → source contract → required browser tab/service surface → same fixture runtime action → result/download complete event → exact nonzero SourcePath → service-specific CaptureBridge copy-only → Drive cloud fileId/size/mime/parent readback → automatic asset classification → Queens raw registration → analysis/Seed candidate → QA/x2 gate → template candidate → front/platform routing → History/Error Learning/Resume writeback.

## Download rule
Never sync all user Downloads. Only a completed artifact identified by the extension/browser event or exact SourcePath may enter `C:\HomeDesignAutomationV7\CaptureBridge\INBOX\<ServiceKey>`. Preserve the source. Route the central copy to `00_중앙에이전트\CaptureBridge\INBOX\<ServiceKey>`, then classify Audio/Video/Image/Document/Data/Other and register taskId, sourcePath, bytes, hash when available, Drive fileId, MIME, path and timestamps.

## Error rule
No blind retry. On repeat failure without changed evidence, HOLD and inspect the failed layer. Record FAILED_STAGE, EXPECTED, ACTUAL, ROOT_CAUSE, WRONG_ASSUMPTION, FAILED_APPROACH, MINIMUM_FIX, SAME_FIXTURE_RETEST, DO_NOT_REPEAT and RESUME_POINT. Patch only the failed layer and retest the same fixture.

## Approval boundary
Auto-reuse existing approvals. Stop only for genuinely new login/2FA, new OAuth scope, secret/API-key entry, new paid cost, public publishing, payment, destructive action, or new browser security permission.

## Completion
Do not mark complete from code, CI, queue or local copy alone. Completion requires actual runtime result/download, exact nonzero file evidence, Drive cloud object readback, required QA/readback, and central History/Lesson writeback.

## Cadence target
Capture reconcile 5m; Chrome health 15m; asset ingest 30m; Seed promotion hourly; Template promotion every 2h; full audit 06/14/22 KST; central fallback watch hourly. A trigger is not VERIFIED until runtime evidence exists.
