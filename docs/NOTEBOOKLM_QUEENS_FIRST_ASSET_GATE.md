# NotebookLM Queens-first Asset Gate

## Governing order

NotebookLM native artifact -> native binary preserved in Drive -> Queens registration metadata -> Seed derivative -> T1/T2 -> Johnson/front delivery.

The native artifact is L0 raw material and must never be replaced by JSON/TXT readback. JSON/TXT/capture metadata are sidecars only.

## Required gates

1. `SOURCE_IMMUTABLE`
   - Never delete, overwrite, or convert the source artifact in place.
2. `NATIVE_ORIGINAL_VERIFIED`
   - Native destination file exists and has positive bytes.
   - Preserve or repair only the filename extension; binary bytes stay unchanged.
3. `HASH_DEDUPE`
   - Compute SHA-256 and derive `ASSET_ID` as `NLM:<sha256>`.
4. `QUEENS_INBOX`
   - Write a `.capture.json` sidecar containing source/native paths, sizes, extension evidence, SHA-256, artifact type, and task ID.
5. `QUEENS_URL_VERIFIED`
   - Drive sync/readback must provide the accessible Drive file identity/URL before Queens is considered verified.
6. `SEED_DERIVATIVE_VERIFIED`
   - Only after Queens native original verification may analysis/summary/QTAG/keywords or other Seed derivatives be produced.
7. `JOHNSON_DELIVERY_ALLOWED`
   - Johnson/front packages may reference the native asset plus verified Seed metadata only after the Seed gate passes.

## Compatibility rule

Existing successful audio/video download behavior stays unchanged. The Queens-first wrapper is additive: it calls the existing mirror, verifies the source still exists, verifies the native destination, then emits metadata. It does not regenerate or transcode audio/video.

Image-specific repair remains allowed for generic browser names such as `.dat`, `.bin`, `.blob`, `.download` only when binary signature validation resolves a valid native image extension. Correctly named native files pass through unchanged.

## Completion rule

JSON/TXT-only output is never success for a binary artifact. Completion requires a positive-byte native binary first. Seed/Johnson status must remain false until their respective downstream verification gates are satisfied.
