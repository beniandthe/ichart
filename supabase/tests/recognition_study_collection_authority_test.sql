begin;

select no_plan();

insert into auth.users (id, email, raw_user_meta_data)
values (
    '91000000-0000-4000-8000-000000000001',
    'recognition-study-authority-test@example.invalid',
    '{}'::jsonb
)
on conflict (id) do nothing;

insert into private.recognition_study_consent_policy_presentations (
    presentation_id,
    presentation_sha256,
    presentation_artifact,
    consent_document_url,
    scope,
    consent_ledger_version,
    consent_text_version,
    privacy_notice_version,
    data_use_policy_version,
    retention_policy_version,
    raw_stroke_donation_required,
    enabled
)
select
    'database-contract-test-v1',
    encode(extensions.digest(document, 'sha256'), 'hex'),
    document,
    'https://example.invalid/recognition-study-consent-v1.json',
    'chord-recognition-research-v1',
    'consent-ledger-v1',
    'consent-text-v1',
    'privacy-notice-v1',
    'raw-stroke-research-v1',
    'retention-12-months-v1',
    true,
    true
from (select convert_to('{"testPolicy":true}', 'utf8') as document) fixture;

select ok(
    not has_table_privilege(
        'authenticated',
        'private.recognition_study_consents',
        'select'
    ),
    'authenticated cannot read private study consent rows'
);

select ok(
    not has_table_privilege(
        'service_role',
        'private.recognition_study_consents',
        'select'
    ),
    'service role cannot bypass the consent RPC boundary'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.prepare_recognition_study_capture_grant(uuid)',
        'execute'
    ),
    'authenticated cannot call the service-only grant RPC'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.prepare_recognition_study_capture_grant(uuid)',
        'execute'
    ),
    'service role can call the grant RPC'
);

select ok(
    has_function_privilege(
        'authenticated',
        'public.accept_recognition_study_consent(uuid,text,text,boolean)',
        'execute'
    ),
    'authenticated can call the server-authored consent acceptance RPC'
);

select ok(
    not has_function_privilege(
        'service_role',
        'public.accept_recognition_study_consent(uuid,text,text,boolean)',
        'execute'
    ),
    'service role cannot manufacture participant consent'
);

select ok(
    not has_function_privilege(
        'service_role',
        'public.record_recognition_study_consent(uuid,uuid,text,text,text,text,text,text)',
        'execute'
    ),
    'legacy caller-authored consent RPC is disabled'
);

select set_config(
    'request.jwt.claim.sub',
    '91000000-0000-4000-8000-000000000001',
    true
);

create temporary table recognition_study_consent_acceptance
on commit drop
as
select public.accept_recognition_study_consent(
    '91000000-0000-4000-8000-000000000002',
    'database-contract-test-v1',
    (
        select presentation_sha256
        from private.recognition_study_consent_policy_presentations
        where presentation_id = 'database-contract-test-v1'
    ),
    true
) as document;

select is(
    document ->> 'status',
    'active',
    'server-authored consent acceptance becomes active'
)
from recognition_study_consent_acceptance;

select is(
    (document ->> 'replayed')::boolean,
    false,
    'first consent acceptance is not a replay'
)
from recognition_study_consent_acceptance;

select is(
    (
        public.accept_recognition_study_consent(
            '91000000-0000-4000-8000-000000000002',
            'database-contract-test-v1',
            (
                select presentation_sha256
                from private.recognition_study_consent_policy_presentations
                where presentation_id = 'database-contract-test-v1'
            ),
            true
        ) ->> 'replayed'
    )::boolean,
    true,
    'exact consent acceptance retry returns the frozen response'
);

select throws_ok(
    $$
    select public.accept_recognition_study_consent(
        '91000000-0000-4000-8000-000000000099',
        'database-contract-test-v1',
        (
            select presentation_sha256
            from private.recognition_study_consent_policy_presentations
            where presentation_id = 'database-contract-test-v1'
        ),
        true
    )
    $$,
    'P0001',
    'an active consent record already exists for this owner',
    'a second active consent record is rejected'
);

select is(
    (
        select count(*)::integer
        from private.recognition_study_consent_events
        where event_type = 'accepted'
    ),
    1,
    'acceptance appends exactly one immutable ledger event'
);

create temporary table recognition_study_authority_test_state (
    prepared jsonb not null,
    grant_document jsonb not null
) on commit drop;

insert into recognition_study_authority_test_state (prepared, grant_document)
with prepared as (
    select public.prepare_recognition_study_capture_grant(
        '91000000-0000-4000-8000-000000000001'
    ) as document
)
select
    prepared.document,
    jsonb_build_object(
        'schemaVersion', 'recognition-study-signed-capture-grant-v1',
        'signingKeyID', 'database-contract-test',
        'signatureBase64', repeat('A', 88),
        'payload', jsonb_build_object(
            'artifactKind', 'externally-authorized-session-grant-v1',
            'authorizationEpoch',
                (prepared.document ->> 'authorizationEpoch')::bigint,
            'authorizationID', '91000000-0000-4000-8000-000000000004',
            'captureTickets', jsonb_build_array(jsonb_build_object(
                'captureAuthorizationID',
                    '91000000-0000-4000-8000-000000000006',
                'ordinal', 0,
                'promptID', 'isolated-c-major'
            )),
            'collectionProtocolVersion', 'writer-independent-capture-v2',
            'consentBinding', prepared.document -> 'consentBinding',
            'datasetVersion', 'capture-pilot-v1',
            'expectedCaptureCount', 1,
            'expiresAtUnixSeconds',
                extract(epoch from clock_timestamp())::bigint + 900,
            'issuedAtUnixSeconds',
                extract(epoch from clock_timestamp())::bigint,
            'notBeforeUnixSeconds',
                extract(epoch from clock_timestamp())::bigint,
            'promptPlanVersion', 'coverage-pilot-v1',
            'schemaVersion', 'recognition-study-capture-grant-v1',
            'serviceSessionID', '91000000-0000-4000-8000-000000000005'
        )
    )
from prepared;

select is(
    (
        public.commit_recognition_study_capture_grant(
            '91000000-0000-4000-8000-000000000001',
            '91000000-0000-4000-8000-000000000003',
            grant_document,
            repeat('cd', 32)
        ) ->> 'stored'
    )::boolean,
    true,
    'first grant commit stores the artifact'
)
from recognition_study_authority_test_state;

select is(
    (
        public.commit_recognition_study_capture_grant(
            '91000000-0000-4000-8000-000000000001',
            '91000000-0000-4000-8000-000000000003',
            grant_document,
            repeat('cd', 32)
        ) ->> 'stored'
    )::boolean,
    false,
    'exact grant retry returns the immutable stored artifact'
)
from recognition_study_authority_test_state;

update private.recognition_study_capture_tickets
set status = 'consumed', consumed_at = clock_timestamp()
where capture_authorization_id = '91000000-0000-4000-8000-000000000006';

update private.recognition_study_capture_grants
set status = 'completed', completed_at = clock_timestamp()
where authorization_id = '91000000-0000-4000-8000-000000000004';

create temporary table recognition_study_consent_withdrawal
on commit drop
as
select public.withdraw_recognition_study_consent_v2(
    '91000000-0000-4000-8000-000000000007',
    (
        select consent_record_id
        from private.recognition_study_consents
        where owner_id = '91000000-0000-4000-8000-000000000001'
            and authority_version = 'server-authored-v1'
    )
) as document;

select is(
    document ->> 'status',
    'withdrawn',
    'authenticated withdrawal changes the consent state'
)
from recognition_study_consent_withdrawal;

select is(
    (
        select count(*)::integer
        from private.recognition_study_capture_tickets
        where capture_authorization_id =
            '91000000-0000-4000-8000-000000000006'
            and status = 'consumed'
            and consent_withdrawn_at is not null
    ),
    1,
    'withdrawal marks an already-consumed ticket'
);

select is(
    public.prepare_recognition_study_capture_grant(
        '91000000-0000-4000-8000-000000000001'
    ),
    null::jsonb,
    'withdrawn consent cannot prepare a new grant'
);

select is(
    (
        select count(*)::integer
        from private.recognition_study_consent_events
        where event_type = 'withdrawn'
    ),
    1,
    'withdrawal appends one globally ordered ledger event'
);

select is(
    (
        public.accept_recognition_study_consent(
            '91000000-0000-4000-8000-000000000002',
            'database-contract-test-v1',
            (
                select presentation_sha256
                from private.recognition_study_consent_policy_presentations
                where presentation_id = 'database-contract-test-v1'
            ),
            true
        ) ->> 'status'
    ),
    'withdrawn',
    'acceptance replay reports the current withdrawn state instead of stale active state'
);

select ok(
    strpos(
        pg_get_functiondef(
            'public.accept_recognition_study_consent(uuid,text,text,boolean)'::regprocedure
        ),
        'from auth.users'
    ) < strpos(
        pg_get_functiondef(
            'public.accept_recognition_study_consent(uuid,text,text,boolean)'::regprocedure
        ),
        'pg_advisory_xact_lock'
    ),
    'acceptance locks the auth user before its owner advisory lock'
);

select ok(
    strpos(
        pg_get_functiondef(
            'public.withdraw_recognition_study_consent_v2(uuid,uuid)'::regprocedure
        ),
        'from auth.users'
    ) < strpos(
        pg_get_functiondef(
            'public.withdraw_recognition_study_consent_v2(uuid,uuid)'::regprocedure
        ),
        'pg_advisory_xact_lock'
    ),
    'withdrawal locks the auth user before its owner advisory lock'
);

select ok(
    strpos(
        pg_get_functiondef(
            'public.commit_recognition_study_capture_grant(uuid,uuid,jsonb,text)'::regprocedure
        ),
        'from auth.users'
    ) < strpos(
        pg_get_functiondef(
            'public.commit_recognition_study_capture_grant(uuid,uuid,jsonb,text)'::regprocedure
        ),
        'pg_advisory_xact_lock'
    ),
    'grant commit locks the auth user before its request advisory lock'
);

select is(
    (
        public.withdraw_recognition_study_consent_v2(
            '91000000-0000-4000-8000-000000000007',
            (
                select consent_record_id
                from private.recognition_study_consents
                where owner_id = '91000000-0000-4000-8000-000000000001'
                    and authority_version = 'server-authored-v1'
            )
        ) ->> 'replayed'
    )::boolean,
    true,
    'exact withdrawal retry returns the frozen response'
);

select throws_ok(
    format(
        'select public.commit_recognition_study_capture_grant(%L, %L, %L::jsonb, %L)',
        '91000000-0000-4000-8000-000000000001',
        '91000000-0000-4000-8000-000000000003',
        grant_document::text,
        repeat('cd', 32)
    ),
    'P0001',
    'signed grant is not bound to the active consent record',
    'withdrawn consent blocks idempotent grant replay'
)
from recognition_study_authority_test_state;

insert into auth.users (id, email, raw_user_meta_data)
values (
    '91000000-0000-4000-8000-000000000010',
    'recognition-study-deletion-test@example.invalid',
    '{}'::jsonb
);

select set_config(
    'request.jwt.claim.sub',
    '91000000-0000-4000-8000-000000000010',
    true
);

select public.accept_recognition_study_consent(
    '91000000-0000-4000-8000-000000000011',
    'database-contract-test-v1',
    (
        select presentation_sha256
        from private.recognition_study_consent_policy_presentations
        where presentation_id = 'database-contract-test-v1'
    ),
    true
);

create temporary table recognition_study_deletion_identity
on commit drop
as
select protected_writer_id, consent_record_id
from private.recognition_study_consents
where owner_id = '91000000-0000-4000-8000-000000000010';

delete from auth.users
where id = '91000000-0000-4000-8000-000000000010';

select is(
    (
        select count(*)::integer
        from private.recognition_study_consent_events events
        join recognition_study_deletion_identity identity
            on identity.protected_writer_id = events.protected_writer_id
            and identity.consent_record_id = events.consent_record_id
        where events.event_type = 'account-deletion'
    ),
    1,
    'account deletion appends a durable consent-revocation ledger event'
);

select is(
    (
        select count(*)::integer
        from private.recognition_study_consents
        where owner_id = '91000000-0000-4000-8000-000000000010'
    ),
    0,
    'account deletion removes the private consent row after ledgering revocation'
);

select throws_ok(
    $$
    update private.recognition_study_consent_events
    set event_type = 'accepted'
    where event_type = 'account-deletion'
    $$,
    'P0001',
    'recognition study consent ledger is append-only',
    'consent ledger events cannot be rewritten'
);

select * from finish();

rollback;
