# FIX-036 notification ledger grants

Fresh staging accepted the verified monthly claim, but mapped Apple notifications
returned HTTP500 with an authority permission error. The claim branch does not
write `public.app_store_notification_events`; the notification branch of
`apply_storekit_subscription_authority` does. Its `SECURITY INVOKER` contract
therefore requires explicit service-role ledger privileges on fresh databases.

The migration grants only `INSERT(notification_uuid, original_transaction_id,
signed_at)` and `SELECT(notification_uuid)` to `service_role`. The SELECT grant is
required by `ON CONFLICT (notification_uuid) DO NOTHING`, including the conflict
target used for unique-index inference. INSERT alone is insufficient. See the
[PostgreSQL17 INSERT reference](https://www.postgresql.org/docs/17/sql-insert.html).

The change adds no client grants, RLS policies, UPDATE/DELETE privileges or
SECURITY DEFINER function. It neither rewrites subscriptions/events nor modifies
the authority RPC, Edge Functions, app source or user guidance. Existing broader
service-role grants are retained. Reapplying the grants is idempotent.

The release owner applied the same column grants to staging only under migration
`20261122162817`; this source migration makes the repair reproducible on future
fresh databases. Production's preexisting service-role SELECT/INSERT access was
observed separately and was not changed by that staging repair. Do not infer a
deployment or genuine Apple-notification retry from this source patch.

## Isolated regression

Use a new disposable PostgreSQL17 cluster with TCP disabled and a private Unix
socket, and create a database named `ichart_authority_audit`. Run `psql -X -v
ON_ERROR_STOP=1` against that explicit local socket, in order:

1. `supabase/tests/support/storekit_authority_atomic_fixture.psql`
2. `supabase/migrations/20261106045008_atomic_storekit_subscription_authority.sql`
3. `supabase/tests/storekit_notification_ledger_grants_test.psql`

The regression removes the fixture's broad ledger grants, reproduces both the
missing-grant and INSERT-only failures, then runs the new migration twice. It
checks mapped notification storage, duplicate idempotency, atomic failure and
the unchanged client/RLS/invoker/column boundaries. The test rolls back; it must
never run against a linked Supabase project. This is synthetic PostgreSQL
evidence, separate from physical StoreKit and hosted-notification acceptance.
