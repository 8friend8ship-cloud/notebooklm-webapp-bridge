# Recovery Learning Log — 2026-09-19

- Do not mistake a device-authorization gate for UAC.
- Do not start bare local Desktop Commander code for Remote mode.
- Do not use broad recursive dependency scans during active recovery.
- Do not let stale auth/failure logs override healthy live transport.
- Do not combine persistent bootstrap loops with independent minute-level schedulers.
- Serialize recurring automation with a Python no-window shim, task lock, and global lock.
- If the primary mounted drive is absent, use a verified local mirror fallback rather than creating a repeated failure loop.
- Completion requires readback, not only process launch.

## 2026-11-18 — R1 RemoteDC stall, R2/R3 independent operations (confirmed)

**Canonical lineage:** `TASK_20260909_REMOTE_DC_DISPLAY_OFF_RECOVERY_001`, `DUAL_EYE_MULTI_BRAIN_BRIDGE_V1`. Keep the original `0.2.51` runtime and one producer chain. No new task, scheduled trigger, OAuth, browser, reboot, cache reset, or broad Node kill.

**Real incident evidence:**
- OS last boot observed 09:02:35 KST; why it booted at that time is **not proved**.
- 09:03 KST KeepAlive: `HOLD_INSTALL_CHANGE_WINDOW`, reason `RECENT_INSTALLER_PROCESS`, R1 remote process 0, TCP 0; no restart attempted. Exact installer identity unavailable from this historical receipt.
- Existing `HomeDesignAutomation-PythonControl` scheduled task was **Disabled**; `HomeDesignAutomation-AutoResume` remained Ready with last run 09:03 and result 0x41306 (terminated). Existing AutoResume HKCU Run entry absent. Do **not** re-enable user-disabled 5-minute schedules to conceal this.
- Existing Python worker recorded `P0_REMOTE_DC_RECOVERY_DONE` despite `exitCode=4`. Fixed its exit-status/deferred-request interpretation and no-force-restart call; latest source re-installed locally with exact Git blob SHA readback.
- 10:36 KST approved KeepAlive recovered one R1 producer chain and TCP 1, no broad kill. Remote MCP Online, real PowerShell X2 and file write/read X2 verified at approximately 10:44 KST. The local `KEEP_SESSION` result alone must **never** stand in for a cloud X2 result.
- The independent 10-minute `CentralAgent_Failover_Check` task was already Ready and running. Its existing G/F probe previously chose the first `G:/` folder, which was the read-only Other Computers collection, causing a **false** `F_FAILOVER`. Changed only its existing script to select `G:/내 드라이브/00_중앙에이전트` exactly; G read/write X1/X2 returned `G_PRIMARY`.

**Changes under existing pack ownership:**
1. **RemoteDC/Notebook recovery:** existing `CentralAgent_Failover_Check` Python script now commits its G/F data route **before** any optional R1 recovery check; performs a rate-limited, guarded, exact KeepAlive call after stale receipt; never bypasses the installer/auth guard; never claims cloud X2 from TCP. Existing 10-minute task is unchanged; the R1-specific 5-minute task remains disabled.
2. **Remote Manager:** `CentralRemoteManager_Dispatcher.py` excludes an explicitly offline R1 from selected routes. Non-GUI FILE/PROCESS/SCRIPT/AUTOMATION preserve R2/R3 candidates; unsupported GUI actions are **HOLD** pending exact target/human check. Simulation: 7/7 checks × 2 runs PASS without disconnecting the live session.
3. **REA:** existing `RDC_REA_LearningLoop_V1.py` learns only whitelisted status fields from local worker, KeepAlive and G/F receipts, records historic false-DONE exit 4 and installer HOLD, never exports raw commands or outputs; existing privacy/dedupe self-test PASS; `--incident` receipt produced.
4. **GitHub source & local deployment:** `InstallChangeGuard.ps1` now records the active install process **name and PID only** for future attribution; current check returned `active=false`, 0 installer processes. The existing `HomeDesignAutoResume.ps1` and `central_control_worker_v1.py` were updated from their exact Git blob sources with rollback backups and SHA comparison; PowerShell syntax and Python self-test PASS.

**Limits:** the user's explicit disablement of recurring schedules is retained; R2 data-routing continuity is demonstrated, not a universal replacement for RemoteDC GUI work. A RemoteDC half-open cloud channel can still require fresh R3 cloud evidence and explicit one-shot recovery. No automatic version jump from `0.2.51` to later upstream releases without separate approval and X2 validation.

**Next gate:** observe the *next* existing 10-minute G/F task's real last-run receipt with no R1 restart; repeat cloud Online + command + RW X2 when the next genuine R1 failure occurs. Trace the boot cause and installer PID via Windows event records only if those records actually exist.
