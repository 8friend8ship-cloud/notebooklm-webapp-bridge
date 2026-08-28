# Next runtime action

After the current higher-priority Central Learning QA task clears the local runner:

1. Run `ManagedExtensionAutopilot.ps1 -Mode SyncRegistry` from current main.
2. Require successful download of registry and main archive.
3. Require stage of `Central Platform Publisher Bridge` through `InstallOrUpdateManagedChromeExtensions.ps1`.
4. Launch/restart only the dedicated managed Chrome profile.
5. Read back loaded extension ID/version/path and site-permission state.
6. Run per-platform no-publish fixture x2.
7. Write results to CentralAgent App/Platform Bridge Control and History.

Do not preempt a claimed local Chrome/Apps Script job and do not restart normal Chrome.
