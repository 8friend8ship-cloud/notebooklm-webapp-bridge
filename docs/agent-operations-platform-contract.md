# Agent Operations Platform integration contract

Status: staging draft

## Purpose

Connect the approved Agent Operations Platform web app, Apps Script, Google Sheets queues, the Chrome bridge, and GitHub-managed schemas without changing production behavior.

The platform must support two parallel capabilities:

1. operational automation for comments, DMs, forms, trials, products, delivery, subscriptions, analytics, and audits;
2. high-volume master-content production, including meditation articles classified by real user concerns.

## Required identifiers

Every request and result must carry stable identifiers so the complete lineage can be audited.

- `REQUEST_ID`
- `TASK_ID`
- `PROJECT_ID`
- `CONTENT_ID`
- `MASTER_CONTENT_ID`
- `CONCERN_CATEGORY_ID`
- `CONCERN_SUBCATEGORY_ID`
- `AUDIENCE_ID`
- `LOCALE_ID`
- `PLATFORM_ID`
- `PUBLISH_ID`
- `RESULT_ID`
- `SCHEMA_VERSION`

## Meditation and concern classification

A meditation generation request must include:

- concern category and subcategory;
- audience and life stage;
- situation keywords;
- emotional state;
- desired depth and length;
- passage, theme, or source mapping;
- duplicate-prevention fingerprint;
- whether the output is a new master article or a platform edit of an existing master.

The system must never confuse master generation with platform adaptation. One master article may feed multiple platform outputs, but platform outputs must retain the source `MASTER_CONTENT_ID`.

## Queue separation

Use separate queues for:

- `MASTER_CONTENT_QUEUE`
- `PLATFORM_EDIT_QUEUE`
- `PUBLISH_QUEUE`
- `COMMENT_DM_QUEUE`
- `TRIAL_ENTITLEMENT_QUEUE`
- `PRODUCT_AFFILIATE_QUEUE`
- `BRIDGE_QUEUE`
- `RESULT_CALLBACK_QUEUE`
- `RETRY_QUEUE`
- `AUDIT_QUEUE`

## Minimum states

`QUEUED`, `CLAIMED`, `RUNNING`, `REVIEW_REQUIRED`, `DONE`, `RETRYABLE_ERROR`, `BLOCKED`, `CANCELLED`.

Retries must be idempotent. A retry must not create duplicate content, duplicate customer messages, duplicate subscriptions, or duplicate publishing actions.

## Health contract

The approved web app should expose non-destructive health responses for:

- web app availability;
- spreadsheet access;
- queue schema presence;
- Drive access;
- bridge configuration presence;
- schema-version compatibility;
- recent retryable and blocked counts.

Health checks must not claim live jobs, send messages, publish content, or write customer data.

## GitHub and web-app responsibilities

GitHub stores versioned schemas, validators, tests, selector mappings, migration notes, and release history.

The approved web app embeds the same category registry and queue controls so normal operation does not require editing GitHub files.

The web app and repository must share the same `SCHEMA_VERSION`. A mismatch must block processing and return a clear diagnostic.

## Production safety

Automated QA may create staging branches, add tests, run non-destructive checks, and prepare draft pull requests.

The following remain manual approval steps:

- merge to `main`;
- production Apps Script or Vercel deployment;
- customer messaging;
- billing or paid API changes;
- secret or permission changes;
- destructive data migration.
