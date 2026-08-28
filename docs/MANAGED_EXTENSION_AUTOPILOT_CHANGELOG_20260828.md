# 2026-08-28 managed extension autopilot changelog

- PR #16 introduced registry, PowerShell autopilot, Central Platform Publisher Bridge, and static CI.
- Runtime dependency audit after merge found `ManagedExtensionAutopilot.ps1` calls `InstallOrUpdateManagedChromeExtensions.ps1` but that package manager was not yet on main.
- Follow-up adds the missing package manager plus runtime gate, success/failure template, user site-permission gate, platform scope, and dependency CI.
- This is a changed-condition fix, not a blind retry.
