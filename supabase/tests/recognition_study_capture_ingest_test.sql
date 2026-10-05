begin;

select no_plan();

insert into auth.users (id, email, raw_user_meta_data)
values (
    '92000000-0000-4000-8000-000000000001',
    'recognition-study-ingest-test@example.invalid',
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
    'database-ingest-test-v1',
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
from (select convert_to('{"ingestTestPolicy":true}', 'utf8') as document) fixture;

select set_config(
    'request.jwt.claim.sub',
    '92000000-0000-4000-8000-000000000001',
    true
);

select public.accept_recognition_study_consent(
    '92000000-0000-4000-8000-000000000002',
    'database-ingest-test-v1',
    (
        select presentation_sha256
        from private.recognition_study_consent_policy_presentations
        where presentation_id = 'database-ingest-test-v1'
    ),
    true
);

select ok(
    not has_table_privilege(
        'authenticated',
        'private.recognition_study_raw_captures',
        'select'
    ),
    'authenticated cannot read raw research captures'
);

select ok(
    not has_table_privilege(
        'service_role',
        'private.recognition_study_raw_captures',
        'select'
    ),
    'service role must use audited capture RPCs instead of direct raw reads'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.consume_recognition_study_capture(uuid,uuid,text,jsonb,text,text,text,integer)',
        'execute'
    ),
    'authenticated cannot invoke the service-only capture consume RPC'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.consume_recognition_study_capture(uuid,uuid,text,jsonb,text,text,text,integer)',
        'execute'
    ),
    'service role can invoke the capture consume RPC'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.purge_expired_recognition_study_captures(timestamptz)',
        'execute'
    ),
    'authenticated cannot invoke the retention purge RPC'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.purge_expired_recognition_study_captures(timestamptz)',
        'execute'
    ),
    'service role can invoke the retention purge RPC'
);

select ok(
    exists (
        select 1 from pg_extension where extname = 'pg_cron'
    ),
    'pg_cron is installed for operational retention enforcement'
);

select is(
    (
        select schedule
        from cron.job
        where jobname = 'recognition-study-retention-purge-v1'
    ),
    '17 3 * * *',
    'retention purge runs daily on the frozen UTC schedule'
);

select is(
    (
        select command
        from cron.job
        where jobname = 'recognition-study-retention-purge-v1'
    ),
    'select public.purge_expired_recognition_study_captures();',
    'retention job invokes only the content-deleting purge function'
);

select is(
    (
        select active
        from cron.job
        where jobname = 'recognition-study-retention-purge-v1'
    ),
    true,
    'retention purge job is active after migration replay'
);

create temporary table recognition_study_ingest_test_state (
    grant_document jsonb not null,
    envelope jsonb not null,
    packet_base64 text not null,
    packet_sha256 text not null
) on commit drop;

insert into recognition_study_ingest_test_state (
    grant_document,
    envelope,
    packet_base64,
    packet_sha256
)
with prepared as (
    select public.prepare_recognition_study_capture_grant(
        '92000000-0000-4000-8000-000000000001'
    ) as document
), packet as (
    select
        encode(convert_to('{}', 'utf8'), 'base64') as base64,
        encode(
            extensions.digest(convert_to('{}', 'utf8'), 'sha256'),
            'hex'
        ) as sha256
), grant_artifact as (
    select jsonb_build_object(
        'schemaVersion', 'recognition-study-signed-capture-grant-v1',
        'signingKeyID', 'database-ingest-test',
        'signatureBase64', repeat('A', 88),
        'payload', jsonb_build_object(
            'artifactKind', 'externally-authorized-session-grant-v1',
            'authorizationEpoch',
                (prepared.document ->> 'authorizationEpoch')::bigint,
            'authorizationID', '92000000-0000-4000-8000-000000000004',
            'captureTickets', jsonb_build_array(
                jsonb_build_object(
                    'captureAuthorizationID',
                        '92000000-0000-4000-8000-000000000006',
                    'displayText', 'C7',
                    'ordinal', 0,
                    'presentedChartStyle', 'simple-chord-sheet',
                    'presentedConstruction', 'root-first',
                    'presentedPace', 'natural',
                    'presentedSize', 'normal',
                    'promptID', 'isolated-c-seven',
                    'promptKind', 'isolated-chord',
                    'requestedOrientation', 'portrait'
                ),
                jsonb_build_object(
                    'captureAuthorizationID',
                        '92000000-0000-4000-8000-000000000007',
                    'displayText', 'G7',
                    'ordinal', 1,
                    'presentedChartStyle', 'simple-chord-sheet',
                    'presentedConstruction', 'root-first',
                    'presentedPace', 'natural',
                    'presentedSize', 'normal',
                    'promptID', 'isolated-g-seven',
                    'promptKind', 'isolated-chord',
                    'requestedOrientation', 'portrait'
                )
            ),
            'clientRequirements', jsonb_build_object(
                'captureContractVersion',
                    'recognition-study-authorized-capture-v1',
                'expectedBundleIdentifier', 'com.ichart.recognitionstudy',
                'minimumBuildNumber', 51
            ),
            'collectionProtocolVersion', 'writer-independent-capture-v2',
            'consentBinding', prepared.document -> 'consentBinding',
            'datasetVersion', 'capture-pilot-v1',
            'expectedCaptureCount', 2,
            'expiresAtUnixSeconds',
                floor(extract(epoch from clock_timestamp()))::bigint + 900,
            'issuedAtUnixSeconds',
                floor(extract(epoch from clock_timestamp()))::bigint,
            'notBeforeUnixSeconds',
                floor(extract(epoch from clock_timestamp()))::bigint,
            'promptPlanVersion', 'coverage-pilot-v1',
            'schemaVersion', 'recognition-study-capture-grant-v1',
            'serviceSessionID', '92000000-0000-4000-8000-000000000005'
        )
    ) as document
    from prepared
)
select
    grant_artifact.document,
    jsonb_build_object(
        'artifactKind', 'externally-authorized-trajectory-v1',
        'captureAuthorizationID',
            '92000000-0000-4000-8000-000000000006',
        'clientAppContext', jsonb_build_object(
            'appVersion', '1.0',
            'buildNumber', '51',
            'bundleIdentifier', 'com.ichart.recognitionstudy',
            'operatingSystemMajorVersion', 26,
            'operatingSystemMinorVersion', 5
        ),
        'clientCapturedAtUnixMilliseconds', 1800000100000,
        'clientObservedSurface', jsonb_build_object(
            'canvasHeight', '4090000000000000',
            'canvasWidth', '4088000000000000',
            'clientObservedOrientation', 'portrait',
            'presentedChartStyle', 'simple-chord-sheet',
            'presentedConstructionInstruction', 'root-first',
            'presentedPaceInstruction', 'natural',
            'presentedSizeInstruction', 'normal',
            'surfaceVersion', 'recognition-study-presented-surface-v1'
        ),
        'grantAuthorizationID', '92000000-0000-4000-8000-000000000004',
        'schemaVersion',
            'recognition-study-authorized-capture-envelope-v1',
        'serviceSessionID', '92000000-0000-4000-8000-000000000005',
        'signedGrantSHA256', repeat('cd', 32),
        'ticketOrdinal', 0,
        'trajectoryDescriptor', jsonb_build_object(
            'canonicalPacketByteCount', 2,
            'canonicalPacketSHA256', packet.sha256,
            'containsNonFiniteTiming', false,
            'coordinateSpace', 'transformed-prepared-drawing',
            'creationTimingCoverage', 'unavailable',
            'emptyStrokeCount', 0,
            'overallTimingCoverage', 'unavailable',
            'packetFormatVersion', 'ink-trajectory-packet-v1',
            'pointCount', 0,
            'pointTimingCoverage', 'unavailable',
            'schemaVersion',
                'recognition-study-trajectory-descriptor-v1',
            'strokeCount', 0
        )
    ),
    packet.base64,
    packet.sha256
from grant_artifact
cross join packet;

select is(
    (
        public.commit_recognition_study_capture_grant(
            '92000000-0000-4000-8000-000000000001',
            '92000000-0000-4000-8000-000000000003',
            grant_document,
            repeat('cd', 32)
        ) ->> 'stored'
    )::boolean,
    true,
    'capture grant is committed before ingest'
)
from recognition_study_ingest_test_state;

select is(
    (
        select status
        from private.recognition_study_capture_grants
        where authorization_id =
            '92000000-0000-4000-8000-000000000004'
    ),
    'issued',
    'new capture grant is issued before its first upload'
);

select is(
    (
        select status
        from private.recognition_study_capture_tickets
        where capture_authorization_id =
            '92000000-0000-4000-8000-000000000006'
    ),
    'issued',
    'new capture ticket is issued before its first upload'
);

select ok(
    (
        select not_before <= clock_timestamp()
            and expires_at > clock_timestamp()
        from private.recognition_study_capture_grants
        where authorization_id =
            '92000000-0000-4000-8000-000000000004'
    ),
    'new capture grant is within its active time window'
);

create temporary table recognition_study_ingest_receipt
on commit drop
as
select public.consume_recognition_study_capture(
    '92000000-0000-4000-8000-000000000001',
    '92000000-0000-4000-8000-000000000006',
    repeat('cd', 32),
    envelope,
    repeat('ef', 32),
    packet_base64,
    packet_sha256,
    2
) as document
from recognition_study_ingest_test_state;

select is(
    (document ->> 'accepted')::boolean,
    true,
    'first exact capture upload is accepted'
)
from recognition_study_ingest_receipt;

select is(
    (document ->> 'replayed')::boolean,
    false,
    'first capture upload is not marked as a replay'
)
from recognition_study_ingest_receipt;

select is(
    (document ->> 'grantCompleted')::boolean,
    false,
    'consuming an early ticket does not complete a multi-ticket grant'
)
from recognition_study_ingest_receipt;

select is(
    (
        select status
        from private.recognition_study_capture_tickets
        where capture_authorization_id =
            '92000000-0000-4000-8000-000000000006'
    ),
    'consumed',
    'accepted raw bytes consume exactly one ticket'
);

select is(
    (
        select status
        from private.recognition_study_capture_grants
        where authorization_id =
            '92000000-0000-4000-8000-000000000004'
    ),
    'issued',
    'multi-ticket grant remains issued after its first capture'
);

select is(
    (
        select count(*)::integer
        from private.recognition_study_raw_captures
        where capture_authorization_id =
            '92000000-0000-4000-8000-000000000006'
            and status = 'received'
            and canonical_packet = convert_to('{}', 'utf8')
    ),
    1,
    'raw packet and envelope are stored behind the private boundary'
);

select is(
    (
        public.consume_recognition_study_capture(
            '92000000-0000-4000-8000-000000000001',
            '92000000-0000-4000-8000-000000000006',
            repeat('cd', 32),
            envelope,
            repeat('ef', 32),
            packet_base64,
            packet_sha256,
            2
        ) ->> 'replayed'
    )::boolean,
    true,
    'exact upload retry returns the original immutable receipt'
)
from recognition_study_ingest_test_state;

select is(
    (
        public.consume_recognition_study_capture(
            '92000000-0000-4000-8000-000000000001',
            '92000000-0000-4000-8000-000000000006',
            repeat('cd', 32),
            envelope,
            repeat('ef', 32),
            packet_base64,
            packet_sha256,
            2
        ) ->> 'grantCompleted'
    )::boolean,
    false,
    'early ticket replay preserves its original incomplete-grant receipt bit'
)
from recognition_study_ingest_test_state;

create temporary table recognition_study_last_ticket_receipt
on commit drop
as
select public.consume_recognition_study_capture(
    '92000000-0000-4000-8000-000000000001',
    '92000000-0000-4000-8000-000000000007',
    repeat('cd', 32),
    jsonb_set(
        jsonb_set(
            envelope,
            '{captureAuthorizationID}',
            to_jsonb('92000000-0000-4000-8000-000000000007'::text)
        ),
        '{ticketOrdinal}',
        '1'::jsonb
    ),
    repeat('de', 32),
    packet_base64,
    packet_sha256,
    2
) as document
from recognition_study_ingest_test_state;

select is(
    (document ->> 'grantCompleted')::boolean,
    true,
    'consuming the final ticket completes a multi-ticket grant'
)
from recognition_study_last_ticket_receipt;

select is(
    (
        select status
        from private.recognition_study_capture_grants
        where authorization_id =
            '92000000-0000-4000-8000-000000000004'
    ),
    'completed',
    'multi-ticket grant is completed only after the final capture'
);

update private.recognition_study_capture_grants
set issued_at = clock_timestamp() - interval '2 seconds',
    not_before = clock_timestamp() - interval '1 second',
    expires_at = clock_timestamp() - interval '1 millisecond'
where authorization_id = '92000000-0000-4000-8000-000000000004';

select is(
    (
        public.consume_recognition_study_capture(
            '92000000-0000-4000-8000-000000000001',
            '92000000-0000-4000-8000-000000000006',
            repeat('cd', 32),
            envelope,
            repeat('ef', 32),
            packet_base64,
            packet_sha256,
            2
        ) ->> 'grantCompleted'
    )::boolean,
    false,
    'expired exact replay recovers the original early-ticket receipt'
)
from recognition_study_ingest_test_state;

select is(
    (
        public.consume_recognition_study_capture(
            '92000000-0000-4000-8000-000000000001',
            '92000000-0000-4000-8000-000000000006',
            repeat('cd', 32),
            envelope,
            repeat('ef', 32),
            packet_base64,
            packet_sha256,
            2
        ) ->> 'receiptID'
    ),
    (
        select document ->> 'receiptID'
        from recognition_study_ingest_receipt
    ),
    'exact retry preserves the original receipt identifier'
)
from recognition_study_ingest_test_state;

select throws_ok(
    format(
        'select public.consume_recognition_study_capture(%L, %L, %L, %L::jsonb, %L, %L, %L, %s)',
        '92000000-0000-4000-8000-000000000001',
        '92000000-0000-4000-8000-000000000006',
        repeat('cd', 32),
        envelope::text,
        repeat('aa', 32),
        packet_base64,
        packet_sha256,
        2
    ),
    'P0001',
    'capture ticket was already used with different bytes',
    'same ticket cannot be replayed with different envelope bytes'
)
from recognition_study_ingest_test_state;

select is(
    (
        public.withdraw_recognition_study_consent_v2(
            '92000000-0000-4000-8000-000000000008',
            (
                select consent_record_id
                from private.recognition_study_consents
                where owner_id = '92000000-0000-4000-8000-000000000001'
                    and authority_version = 'server-authored-v1'
            )
        ) ->> 'status'
    ),
    'withdrawn',
    'consent withdrawal deletes raw captures and returns minimal state'
);

select is(
    (
        select count(*)::integer
        from private.recognition_study_raw_captures
        where capture_authorization_id =
            '92000000-0000-4000-8000-000000000006'
            and status = 'deleted'
            and deletion_reason = 'consent-withdrawn'
            and envelope is null
            and envelope_sha256 is null
            and canonical_packet is null
            and canonical_packet_sha256 is null
            and canonical_packet_byte_count is null
    ),
    1,
    'withdrawal retains only a content-free deletion receipt'
);

select throws_ok(
    format(
        'select public.consume_recognition_study_capture(%L, %L, %L, %L::jsonb, %L, %L, %L, %s)',
        '92000000-0000-4000-8000-000000000001',
        '92000000-0000-4000-8000-000000000006',
        repeat('cd', 32),
        envelope::text,
        repeat('ef', 32),
        packet_base64,
        packet_sha256,
        2
    ),
    'P0001',
    'active raw-stroke research consent is required',
    'withdrawal blocks even an exact content replay'
)
from recognition_study_ingest_test_state;

update private.recognition_study_raw_captures
set status = 'received',
    envelope = (select envelope from recognition_study_ingest_test_state),
    envelope_sha256 = repeat('ef', 32),
    canonical_packet = convert_to('{}', 'utf8'),
    canonical_packet_sha256 = (
        select packet_sha256 from recognition_study_ingest_test_state
    ),
    canonical_packet_byte_count = 2,
    received_at = clock_timestamp() - interval '2 years',
    retention_deadline = clock_timestamp() - interval '1 year',
    deleted_at = null,
    deletion_reason = null
where capture_authorization_id =
    '92000000-0000-4000-8000-000000000006';

select is(
    (
        public.purge_expired_recognition_study_captures(
            clock_timestamp()
        ) ->> 'deletedCaptureCount'
    )::integer,
    1,
    'retention purge deletes expired raw capture content'
);

select is(
    (
        select deletion_reason
        from private.recognition_study_raw_captures
        where capture_authorization_id =
            '92000000-0000-4000-8000-000000000006'
    ),
    'retention-expired',
    'retention purge records a content-free deletion reason'
);

select * from finish();

rollback;
