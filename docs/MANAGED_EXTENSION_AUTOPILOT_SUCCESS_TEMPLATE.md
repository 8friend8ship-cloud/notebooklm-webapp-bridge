# Managed Chrome Extension success/failure template

## Success evidence
- SOURCE_COMMIT / PACKAGE_VERSION
- SOURCE_ARCHIVE_SHA256 or source tree hash
- MANIFEST_VERSION=3
- REQUIRED_FILES_PASS
- STAGED_PATH
- TREE_SHA256
- PREVIOUS_PATH / LAST_GOOD
- DEDICATED_CHROME_USER_DATA
- LOADED_EXTENSION_ID
- INSTALLED_VERSION
- SITE_PERMISSION_DOMAINS
- FIXTURE_1_RESULT
- FIXTURE_2_RESULT
- DRIVE_EVIDENCE_URL / CENTRAL_SHEET_ROW
- FINAL_STATUS

## Failure evidence
- STAGE
- ERROR_SIGNATURE
- LAST_GOOD
- ROOT_CAUSE
- MINIMUM_FIX
- RETEST_RESULT
- ROLLBACK_RESULT
- NEXT_RESUME_POINT

Rules: no blind retry, no duplicate extension install, no normal-Chrome restart, no credential capture, no public publish without gate, no new OAuth/scope/paid credit without user approval.
