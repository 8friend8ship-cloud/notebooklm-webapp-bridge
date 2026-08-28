# Completion gate

COMPLETE=true only when all are evidenced:
1. Source commit/hash verified.
2. Manifest V3 and referenced files pass.
3. Versioned stage succeeds and LAST_GOOD is preserved.
4. Dedicated managed Chrome loads the staged extension.
5. Extension ID/version/path are read back from runtime.
6. Exact site-permission state is read back or the user is asked for the final site-permission confirmation.
7. Same no-publish fixture passes twice.
8. Drive/Sheets evidence is written and read back.
9. No regression in NotebookLM/Flow/current managed bridges.

Static CI alone never satisfies completion.
