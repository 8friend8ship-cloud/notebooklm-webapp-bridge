# Security boundary

Automatic scope:
- inventory
- download known canonical package source
- ZIP extraction to temp
- Manifest/file integrity validation
- versioned staging
- SHA-256 tree hash
- LAST_GOOD preservation
- dedicated managed Chrome launch/restart
- no-publish editor probe and fill/readback/clear
- Drive/Sheets evidence writeback

Manual/user gate:
- ChatGPT Computer Use site permission confirmation
- new OAuth / new scope / new secret
- paid API or credit use
- first live public publish per platform
- destructive action or payment/contract

Forbidden automatic behavior:
- `<all_urls>` broad permission expansion
- credential/cookie/token capture
- normal Chrome restart
- deleting existing extension versions as cleanup
- public publish before platform gate
