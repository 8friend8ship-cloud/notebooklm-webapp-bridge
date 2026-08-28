# Drive writeback contract

For every managed extension run, Central Agent records:
- source repo/ref/commit
- package/version
- manifest version and required-file result
- staging path and SHA-256 tree hash
- previous/LAST_GOOD path
- dedicated Chrome profile path
- loaded extension ID/version
- exact site-permission domains
- fixture 1 / fixture 2 outcome
- platform/editor detection result
- Drive evidence URL or central-sheet row
- failure signature/root cause/minimum fix/retest/rollback/next resume point when applicable

Runtime evidence wins over source/CI state.
