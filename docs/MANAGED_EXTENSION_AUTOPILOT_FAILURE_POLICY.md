# Failure policy

- Preserve LAST_GOOD and current runtime evidence.
- Record exact stage and error signature.
- Identify root cause before changing code/config.
- Apply the smallest changed-condition fix.
- Run same fixture once; if it fails with the same signature, HOLD and do not blind retry.
- Roll back only the dedicated managed extension path when needed.
- Never restart normal Chrome as a repair shortcut.
- Write failure, fix, retest and next resume point to Central Agent History/Run Log.
