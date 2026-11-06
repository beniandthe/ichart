# Owner snapshot retention integration tests

Run the frozen owner-only archive migration against synthetic data in a new,
private PostgreSQL **17.11** cluster. The 30 cases cover owner isolation, initial
full-history archive and restore gates, keepers, bounded batches, receipt and
payload tampering, concurrent writers and locks, archive-bucket RLS, and account
deletion fencing. Storage, authentication and cron SQL adapters are synthetic;
this suite does not validate the deployed Storage HTTP service or schedule jobs.
The worker's HTTP and request contracts have separate Node tests in
`supabase/functions/_shared/owner_snapshot_retention.test.mjs`.

From the repository root, as an unprivileged user with native PostgreSQL 17.11
installed:

```sh
ICHART_RETENTION_TEST_PG_BIN=/absolute/path/to/postgresql/17/bin \
  node --test supabase/tests/owner_snapshot_retention/retention.test.mjs
```

The harness loads
`supabase/migrations/20261106170932_owner_scoped_chart_snapshot_retention.sql`
and requires SHA-256
`b3147d4aab4e4ebfdb4e112c4ec0ad49241d7fd502e2db1df59ac25600084f1a`.
`ICHART_RETENTION_MIGRATION_SQL` may instead select an absolute `.sql` file with
the same immutable bytes. A different revision requires an intentional update
to this gate after review.

Each invocation uses `initdb` in a mode-0700 directory under `os.tmpdir()`, then
connects only through that directory's private Unix socket. TCP listening is
disabled, host authentication rejects connections, inherited `PG*` settings are
removed, and personal psql startup/password files are ignored. It never accepts
a connection URL or reuses an existing database. `TMPDIR` must resolve outside the
repository to a short, absolute Unix path containing only letters, numbers,
`_`, `.`, `/` and `-` so PostgreSQL's socket
and startup arguments remain unambiguous.

The cluster is stopped after the run. Its temporary directory is retained for
local diagnosis and contains only synthetic fixture data; it is never created
inside the repository. The migration and fixture hashes are checked again after
execution. The fixture creates fresh databases per case and applies the actual
migration to each one.

The dedicated GitHub Actions workflow pins `ubuntu-24.04`, an immutable official
`postgres:17.11` image, and action commits. It uses the image's `gosu` to run Node
and PostgreSQL as the unprivileged `postgres` user. GitHub overrides the job
container's default entrypoint, so the harness owns the only initialized test
cluster. The workflow has no production credentials, database service or exposed
TCP port, and makes no host package upgrades.
