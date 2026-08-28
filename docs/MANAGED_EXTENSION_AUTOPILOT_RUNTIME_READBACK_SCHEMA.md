# Runtime readback schema

Required readback fields per managed extension:
`name, expectedVersion, installedVersion, extensionId, activePath, previousPath, treeSha256, dedicatedProfile, hostPermissions, sitePermissionState, fixture1, fixture2, driveEvidence, lastGood, status, checkedAt`.

These runtime values are written back to Central Agent Sheets and take precedence over source/CI assumptions.
