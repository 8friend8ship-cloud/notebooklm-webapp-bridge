# 2026-08-28 managed extension autopilot changelog

- PR #16 introduced the self-contained `ManagedExtensionAutopilot.ps1`, central registry, Central Platform Publisher Bridge, and static CI.
- Post-merge runtime audit confirmed the autopilot itself already contains staging/hash/LAST_GOOD/dedicated-Chrome logic. A separate reusable package-manager lineage (`InstallOrUpdateManagedChromeExtensions.ps1`) existed only on the staged central-governor branch and was not yet on main.
- Follow-up promotes that reusable package manager to main and adds explicit runtime gate, success/failure template, user site-permission gate, platform scope, and package-contract CI.
- First follow-up CI failed because the test incorrectly assumed the self-contained autopilot must literally call the reusable package manager. The contract test was corrected to validate each implementation independently. This failure and correction are preserved as learning evidence; no blind retry.
