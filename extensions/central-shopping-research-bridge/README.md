# Central Shopping Research & Affiliate Bridge (BRG_032)

Shared browser research adapter for KFood, Interior, Travel and other approved commerce-capable fronts.

## Flow

`app request → product/service candidate → approved shopping provider page → bounded public review scan → JSON download → Drive sync → Queens → dedupe/noise/ad filter → repeated-signal Seed → domain T1/T2 → live provider price/delivery comparison → recommendation reason card`

Supported research hosts in v0.1.0:

- Coupang
- AliExpress
- Amazon.com

Nearby/local availability is handled by the front/backend map routing layer, not by scraping map pages.

## Trigger

The bridge accepts a runtime message:

`CENTRAL_SHOPPING_RESEARCH_SCAN`

with optional `{ appId, taskId, query }`.

For manual/runtime smoke tests, a supported product page may be opened with a URL fragment containing `central-shopping-scan`, for example:

`#central-shopping-scan&appId=APP_KFOOD&taskId=TEST_001&query=whole%20milk`

The downloaded file is written under:

`CentralAgent_ShoppingBridge/<APP_ID>/<PLATFORM>/<timestamp>_<productId>.json`

The existing Google Drive Desktop/download handoff can then mirror the JSON into canonical Drive storage.

## Non-negotiable research rules

- Public visible UI only.
- No login automation and no cookie/token extraction.
- No CAPTCHA or anti-bot bypass.
- Bounded scrolling only; no endless crawl.
- Reviewer names/accounts are not collected.
- Store short snippets and repeated signal counts; do not archive complete review pages.
- A single review is never promoted as a fact.
- Safety, nutrition, medical, legal, structural or other high-stakes claims require official-source cross-check before Seed promotion.

## Recommendation rules

Review sentiment can explain **why** an item may fit a use case, but a shopping recommendation can win only when the commerce runtime separately verifies current price and destination delivery/booking availability. Unknown delivery never wins merely because reviews are positive.

A final front recommendation should surface the reason, for example:

- lowest verified delivered unit cost,
- faster verified delivery at a small price premium,
- stronger repeated quality signal with comparable cost,
- local availability when shipping is unavailable.

Affiliate status must be disclosed in the front UI.

## Runtime verification

Code presence is not runtime proof. BRG_032 remains pending until the same safe test is successful twice with all receipts:

`extension scan → non-empty JSON → exact local path → Drive cloud readback → Queens row → Seed decision → provider live offer → front recommendation reason`.
