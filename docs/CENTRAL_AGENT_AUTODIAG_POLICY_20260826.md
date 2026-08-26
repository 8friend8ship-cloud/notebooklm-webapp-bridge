# Central Agent Auto-Diagnosis / Auto-Fix Policy

Effective: 2026-08-26

## Mandatory execution order
PRE_CHECK -> diagnose -> ROOT_CAUSE -> minimal safe fix -> same-condition recheck -> record -> continue.

## No blind retry
If the same project/component/error layer fails again without new evidence, do not repeat the same command. Record DIAGNOSTIC_HOLD, identify the root-cause layer, change only the minimum needed, and retest under the same conditions.

## User interruption rule
Do not stop for ordinary diagnostics, safe repairs, backups, tests, readbacks, or alternative preparation. Ask the user only for approvals that are genuinely required: login/2FA, account/security/secret changes, paid service activation, publishing/deletion, irreversible data changes, destructive extension removal, payments/contracts, or other high-risk actions.

## Completion rule
Installed, coded, uploaded, or opened is not complete. COMPLETE means VERIFIED after real input -> execution -> real output -> Drive/front/ACK/readback -> error log review -> retest/regression pass.

## Runtime responsibilities
The HomeDesign Governor must self-create missing state directories/files, diagnose Agent/Host/Dedicated Chrome, invoke only safe self-heal actions automatically, recheck after repair, archive temporary desktop artifacts into the central Control folder, and attempt Drive central readback. Missing prior state files must be treated as a state-layer root cause and repaired before Drive diagnosis.

## Evidence statuses
Use BACKLOG -> ANALYZING -> READY -> IMPLEMENTING -> RUNNING -> PRODUCED -> VERIFYING -> RETESTING -> VERIFIED. Use FAILED_TEST for test failure, BLOCKED_ACCESS for missing account/source/access, and BLOCKED_APPROVAL only when explicit user approval is required.
