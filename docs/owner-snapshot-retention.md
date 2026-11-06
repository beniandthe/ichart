# Owner-scoped snapshot archival and retention

This worker operates only on the owner selected by the unexposed SQL policy. A
request cannot select an owner, cutoff, Storage path, bucket or retention limit.
It archives exact canonical PostgreSQL row text; it does not edit chart contents
or ink and does not directly delete snapshots.

## Deployment and authorization

Deploy `owner-snapshot-retention/index.mjs` with the two shared files it imports:
`_shared/owner_snapshot_retention.mjs` and
`_shared/supabase_subscription_authority_store.mjs`. All imports are local or
`node:crypto`; no npm dependency is added. Gateway `verify_jwt` is false because
the handler requires the existing `x-ichart-retention-job-secret` capability.
It compares SHA-256 digests using native constant-time comparison, rejects a
missing/short configuration (minimum 32 characters), and never forwards that
capability to REST or Storage. Existing Edge `ICHART_RETENTION_JOB_SECRET` and its
Vault counterpart are reused. An ordinary JWT or caller-supplied role is not job
authorization.

The service key is selected by the existing shared configuration parser. Opaque
secret keys are sent only on `apikey`; legacy JWT service keys additionally use
Bearer authorization. Requests go only to configured HTTPS Supabase URLs with
redirects rejected. No chart rows, URLs, secrets or upstream error bodies are
logged by this worker.

After authentication and private-policy owner binding, archive mode checks the
fixed bucket `ichart-owner-snapshot-archives`. A missing bucket is created via
Storage API as private, gzip-only, 9 MiB per object and versioning DISABLED, then
read back. Existing metadata must match; it is never repaired or updated. Public,
versioned/suspended, unknown-versioning, unbounded or broad-MIME configurations
fail closed. SQL separately denies client access to this new bucket, including
restrictive protection against broad existing user policies.

Storage's compatibility error handler can return HTTP 400 for a missing bucket,
with logical `statusCode:404` and `code:NoSuchBucket`. Only that structured case
(or the exact legacy bucket-not-found body) and direct HTTP 404 permit creation;
other 400s, object-not-found codes and invalid JSON remain failures.

Authorized failures return only a static stage enum and optional numeric upstream
HTTP status. Stages are `read_policy`, `check_bucket`, `plan`, `upload`, `get`,
`verify`, `finalize` and `sign_links`. No upstream body, message, row or credential
is included; unauthorized responses do not include these diagnostics.

## Archive mode

POST an empty object or `{"mode":"archive"}`. Exactly one available batch is
processed in a 50-second request budget; no second batch is planned or retained
in the same invocation. SQL policy bounds new plans (the production target is
25 rows/2 MiB). Hard verification ceilings remain 100 rows/8 MiB so previously
created larger archives can still be replayed. The worker bounds RPC responses,
compressed objects and decompression.
The SQL lease and owner binding are validated before work and checked again
immediately before upload. Abort/stream failures cannot attest an archive.

For each planned batch:

1. Validate every row ID, owner, original UTF-8 row hash, byte count and ordered
   manifest. Never parse-and-reserialize the archived payload.
2. Gzip the exact row strings, separated by one LF including the final LF. Upload
   only to server-selected `ownerUUID/batchUUID.jsonl.gz` with `x-upsert:false` and
   Content-Type `application/gzip`. Do not set Content-Encoding.
3. GET the private object. A new upload must match its compressed bytes/hash; a
   duplicate must independently reconstruct the exact expected rows. No existing
   object is overwritten. Verified replays must match their stored compressed
   receipt and original row manifest.
4. Bounded decompression must reproduce the exact raw lines, owners, per-row
   hashes, row count and manifest. Only then call the receipt/finalization RPC.
   SQL independently rechecks its own policy, row hashes and protected references
   before any bounded prune.

Bootstrap policy initially archives the full owned history through its fixed
cutoff. SQL returns `verified_waiting_initial_restore` with zero deletes until
the operator restores and validates the actual complete downloaded archives and
document metadata in isolated PostgreSQL. Worker decompression is not that
database restoration proof. The operator-only initial gate must remain off until
the complete restore succeeds. SQL then applies its protected-current-head,
retired-head pin, newest/daily/age rules; the worker cannot override them.

Account deletion fences disable new planning and wait for existing leases to
acknowledge or expire. An in-flight worker accepts
`verified_waiting_account_deletion` only with zero deletes, preserves the object
and stops. Never delete an archive to roll back an ambiguous finalization error:
the database transaction may already have committed. Account deletion's separate
owner-scoped cleanup handles the complete fixed-prefix inventory after the fence.

## Private download-link export

POST `{"mode":"download-links","after":null}`. Follow `next_cursor` using the
same mode's optional `after` UUID. SQL lists at most 100 verified receipts for the
configured owner. The response contains `owner_id`, `archives` and `next_cursor`.
Each archive has `batch_id`, `bucket`, `object_key`, `archive_sha256`,
`archive_bytes`, `manifest_sha256`, `row_count`, `uncompressed_bytes`, `download_url`
and `expires_in:3600`.

These are ordinary Storage signed URLs: **reusable until their one-hour expiry**,
not single-use. Capture the capability-bearing response directly to restricted
operator files; do not print it, put it in chat or persist signed URLs in durable
SQL receipts. The response uses `Cache-Control: no-store`. Verify each downloaded
compressed hash/length before restoration. Regenerate an expired page through the
same privileged route. The worker never serves a public bucket or signs arbitrary
caller-selected objects.

Row SHA-256 covers exact UTF-8 JSON text excluding LF. The manifest covers
`snapshot_id:row_sha256` joined by one LF in ascending canonical UUID order, with
no trailing LF. Archive byte counts include the trailing LF for every row. Restore
the original text through PostgreSQL JSONB record conversion and compare its
canonical hashes; JSON parse-and-reserialize can lose large integers or ink decimal
precision.

## Focused validation

```sh
node --test supabase/functions/_shared/owner_snapshot_retention.test.mjs
```

Synthetic controls cover unauthorized/forged-role requests, forbidden selectors,
wrong owners/paths/hashes, upload/readback corruption, immutable duplicates,
verified replay, stale-reference refusal, deletion fencing, bucket setup and
misconfiguration, stream/abort/size/gzip-expansion failure and exact opaque ink
preservation. These are local controls; production acceptance still requires the
real initial archive/download/isolated-restore gate before the first deletion.
