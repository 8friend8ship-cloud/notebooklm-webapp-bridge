# Runtime blocker index — 2026-08-28

| Blocker | Layer | State | Action |
|---|---|---|---|
| D82 stale physical device readback | Local notebook runtime | HOLD | Fresh device readback first; do not create duplicate LOCAL/PowerShell/clasp tasks. |
| 2026-08-25 bound Script ID discovery failures | Apps Script source binding | DO_NOT_REPEAT | Use existing clasp project listing + existing deployment ID verification instead of Chrome UI/CDP. |
| Vercel deployment build rate limit | Preview/deployment CI status | INFRA_RATE_LIMIT | Do not blind-redeploy; unrelated to guarded Apps Script source sync. |
| PR #11 mergeability | Git | MERGEABLE / UNSTABLE | No conflict currently; unstable state is driven by failing Vercel commit statuses. Merge remains prohibited until runtime x2 anyway. |

The row-285 local task is intentionally `HOLD_RECOVERY`. When the D82 fresh-device gate is satisfied, release the same task rather than enqueueing a duplicate.
