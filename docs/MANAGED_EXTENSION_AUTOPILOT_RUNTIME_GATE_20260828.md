# Managed Extension Autopilot runtime gate — 2026-08-28

## Goal
Central Agent owns managed Chrome-extension build/update/install/rollback so the user no longer manually downloads ZIPs, extracts folders, or reloads unpacked extensions for the dedicated managed Chrome profile.

## Runtime order
1. History/registry/workflow precheck.
2. Sync `config/managed-extension-autopilot-v1.json` from main.
3. For each managed package, download GitHub archive to a temporary path.
4. `InstallOrUpdateManagedChromeExtensions.ps1 -Mode Stage` expands, resolves `manifest.json`, validates Manifest V3 and referenced worker/content-script files, computes SHA-256 tree hash, preserves previous active path as LAST_GOOD, and stages versioned files under `%LOCALAPPDATA%\HomeDesignAutomationV7\ManagedExtensions`.
5. Only the dedicated managed Chrome profile may be launched/restarted with `--load-extension`. Normal Chrome is not restarted.
6. Read back extension ID/version/loaded path, then run same fixture x2.
7. Write runtime evidence to Drive/central Sheets.
8. User gate is reduced to ChatGPT Computer Use site-permission review, unless a new OAuth/scope/secret/paid credit/public publish/destructive action is required.

## Current publisher package
`Central Platform Publisher Bridge 0.1.0` covers Blogger, YouTube Studio, Instagram, TikTok, Naver Blog, Naver Cafe, Naver Clip, and Pinterest. Current implementation is probe + draft fill/readback/clear only. Public publish is fail-closed.

## Completion gate
`SOURCE_HASH_PASS -> MANIFEST_V3_PASS -> REQUIRED_FILES_PASS -> STAGE_PASS -> LAST_GOOD_PRESERVED -> DEDICATED_CHROME_LOAD_PASS -> EXTENSION_ID_READBACK -> SITE_PERMISSION_READBACK -> SAME_FIXTURE_X2_PASS -> DRIVE_WRITEBACK_PASS`.

Do not declare COMPLETE from static CI alone.
