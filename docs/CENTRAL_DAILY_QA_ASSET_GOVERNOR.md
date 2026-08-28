# Central Daily QA / Asset Governor — 2026-08-28

## Goal
Unify persona, language pack, voice pack, subtitle, media assets, front-app backdata, trend learning, API QA, publish URL writeback, and reusable Seed/Template promotion under the Central Agent.

## Runtime order
1. PRE_CHECK / recent lesson / LAST_GOOD lookup.
2. 30-minute lightweight health check.
3. Daily deep inventory of `42/47/48/49/59/60/66/67`.
4. API-free deterministic MVP QA first.
5. External AI QA only if `CENTRAL_EXTERNAL_AI_QA_ENABLED=true` and both provider configs exist.
6. OpenAI Responses API + Gemini Interactions API return the same strict QA JSON shape.
7. Central deterministic gate remains authoritative. Both providers must PASS with score >= 82 and complete evidence before promotion.
8. Approved results can be promoted to `35_INTERNAL_SEED_REGISTRY`, `48_SEARCHABLE_ASSET_INDEX`, and `77_TEMPLATE_EVOLUTION_FACTORY`.
9. Real platform results are registered only after an actual platform ID and HTTP(S) URL exist. No fake URLs.
10. A compact Drive JSON catalog is refreshed for front apps. GitHub recurring sync remains a separately authorized connector/app action so no PAT is embedded in code or Drive.

## Script Properties
No secret is committed. Optional external QA requires:
- `CENTRAL_EXTERNAL_AI_QA_ENABLED=true`
- `OPENAI_API_KEY`
- `OPENAI_QA_MODEL`
- `GEMINI_API_KEY`
- `GEMINI_QA_MODEL`
- optional `CENTRAL_STATIC_CATALOG_FOLDER_ID`

## Trigger handlers
- `runCentralWorkflowHealthTick` — intended 30-minute health check.
- `runCentralDailyQaAssetGovernor` — intended daily deep QA at hour 09 (project timezone).
- `installCentralDailyWorkflowGovernorTriggersV1` — explicit one-time installer; does not delete unrelated triggers.

## Completion rule
Code/PR/trigger creation is not VERIFIED. Completion requires actual trigger readback, same-fixture execution, output records in the Central Master Registry, Drive catalog readback, and regression confirmation. Until bound Apps Script synchronization and runtime proof are observed, status must remain `CODE_STAGED_BOUND_SYNC_PENDING` / `RUNTIME_PENDING`.

## Approval boundary
Normal reads, deterministic QA, Drive snapshot updates, and safe registry writes are automatic. Login/2FA, new secrets/scopes, paid API/billing activation, public deployment/publishing policy changes, destructive overwrite/delete, payments/contracts require the existing Central Agent approval gate.
