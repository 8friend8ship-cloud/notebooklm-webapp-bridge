# Chrome Extension E2E Status — 2026-08-26

## Completion rule
An extension is COMPLETE only when the full chain is verified:

`Queue/Input -> Extension claim/receive -> Real browser action -> Result generation -> Drive/target persistence -> ACK -> Central readback -> Reconnect after logon/sleep-resume`

Installation or enabled state alone is not COMPLETE.

## Current status

| Component | Status | Evidence / next gate |
|---|---|---|
| NotebookLM WebApp Bridge | LIVE_READBACK_REQUIRED | Stable line reached 0.2.29; final PC readback and NotebookLM Queue->result->ACK required. |
| Local Agent | LIVE_READBACK_REQUIRED | Resume/self-heal path exists; verify current process health and version after wake/login. |
| Command Host | LIVE_READBACK_REQUIRED | Verify host health before any claim. |
| Dedicated Chrome / Governor | LIVE_READBACK_REQUIRED | Verify dedicated Chrome session, governor health and queue readback. |
| Sleep/logon auto-resume | CODE_READY_PC_TEST_REQUIRED | Scheduled-task/self-heal commits added 2026-08-26; require one actual sleep/wake and one logon recovery test. |
| Google AI Local Bridge | BLOCKED_RETEST | Previous central registry showed ERROR_VISIBLE. Must pass health->claim->action->result->ACK. |
| Flow Agent Bridge | E2E_NOT_COMPLETE | Must pass prompt->generation->Drive->ACK with a real generated asset. |
| AI Studio Bridge | PARTIAL | Preview iframe selection and regression test still required. |
| Front App Test Bridge | PARTIAL | Verify Vercel/AI Studio/Apps Script live regression path. |
| SketchUp Plan Template Bridge | E2E_NOT_COMPLETE | Must pass one real Plan->template match->result->ACK case. |
| ChatGPT Image Auto | ADAPTER_REQUIRED | Must connect Image Queue->prompt/attach->result->asset register. |
| ChatGPT browser companion | OPTIONAL_PASS | Manual companion only; verify no permission/page-control conflict. |
| UniConverter | REMOVE_CANDIDATE | Not a core automation bridge; retain only if an explicit dependency remains. |
| Save to Google Drive | REMOVE_VERIFY | Historical registry marked malware warning; verify removal. |
| Google Docs Offline / Drive app launcher | OPTIONAL_PASS | Utility only; exclude from central E2E completion calculation. |

## Mandatory runtime test order

1. PRE_CHECK recent lesson/LAST_GOOD.
2. Confirm Local Agent process/version.
3. Confirm Command Host health **before claim**.
4. Confirm Bridge version/readiness.
5. Confirm dedicated Chrome + Governor session.
6. Run NotebookLM queue round trip.
7. Run Google AI Local Bridge health->claim->action->result->ACK.
8. Run Flow prompt->generation->Drive->ACK.
9. Run Front App / AI Studio regression.
10. Run SketchUp one-case E2E.
11. Run ChatGPT Image Auto queue/asset-register E2E.
12. Verify Save to Google Drive removal and extension permission conflicts.
13. Put Windows to sleep, wake, and repeat steps 2-6 without manual reinstall/OAuth.
14. Reboot/logon and repeat steps 2-6.
15. Write evidence/readback and mark COMPLETE only for chains with real outputs.

## Failure policy

- No blind retry on the same condition/error without new evidence.
- On second repeat: `DIAGNOSTIC_HOLD -> ROOT_CAUSE -> minimum fix -> same-condition retest`.
- If Host health fails, do not claim tasks.
- If claim succeeds but Host delivery fails, immediately return task to retry and clear claim.
- Never treat an old Drive readback as current evidence.
