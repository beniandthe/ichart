alter table private.recognition_study_capture_tickets
    add constraint recognition_study_capture_tickets_capture_grant_key
    unique (capture_authorization_id, authorization_id);

create table private.recognition_study_raw_captures (
    capture_authorization_id uuid primary key,
    authorization_id uuid not null,
    receipt_id uuid not null default extensions.gen_random_uuid() unique,
    envelope jsonb,
    envelope_sha256 text check (
        envelope_sha256 is null
        or envelope_sha256 ~ '^[0-9a-f]{64}$'
    ),
    canonical_packet bytea,
    canonical_packet_sha256 text check (
        canonical_packet_sha256 is null
        or canonical_packet_sha256 ~ '^[0-9a-f]{64}$'
    ),
    canonical_packet_byte_count integer check (
        canonical_packet_byte_count is null
        or canonical_packet_byte_count between 1 and 4194304
    ),
    grant_completed_at_receipt boolean not null default false,
    status text not null default 'received' check (
        status in ('received', 'deleted')
    ),
    received_at timestamptz not null default pg_catalog.clock_timestamp(),
    retention_deadline timestamptz not null,
    deleted_at timestamptz,
    deletion_reason text check (
        deletion_reason is null
        or deletion_reason in ('consent-withdrawn', 'retention-expired')
    ),
    constraint recognition_study_raw_captures_ticket_fkey foreign key (
        capture_authorization_id,
        authorization_id
    ) references private.recognition_study_capture_tickets (
        capture_authorization_id,
        authorization_id
    ) on delete cascade,
    constraint recognition_study_raw_captures_state_check check (
        (
            status = 'received'
            and envelope is not null
            and jsonb_typeof(envelope) = 'object'
            and envelope_sha256 is not null
            and canonical_packet is not null
            and canonical_packet_sha256 is not null
            and canonical_packet_byte_count is not null
            and octet_length(canonical_packet) = canonical_packet_byte_count
            and deleted_at is null
            and deletion_reason is null
        )
        or (
            status = 'deleted'
            and envelope is null
            and envelope_sha256 is null
            and canonical_packet is null
            and canonical_packet_sha256 is null
            and canonical_packet_byte_count is null
            and deleted_at is not null
            and deletion_reason is not null
        )
    ),
    constraint recognition_study_raw_captures_retention_check check (
        received_at < retention_deadline
    )
);

create index recognition_study_raw_captures_authorization_idx
    on private.recognition_study_raw_captures (authorization_id, status);

create index recognition_study_raw_captures_retention_idx
    on private.recognition_study_raw_captures (retention_deadline)
    where status = 'received';

alter table private.recognition_study_raw_captures enable row level security;
alter table private.recognition_study_raw_captures force row level security;

revoke all on table private.recognition_study_raw_captures
    from public, anon, authenticated, service_role;

create or replace function public.consume_recognition_study_capture(
    target_owner_id uuid,
    target_capture_authorization_id uuid,
    target_signed_grant_sha256 text,
    target_envelope jsonb,
    target_envelope_sha256 text,
    target_packet_base64 text,
    target_packet_sha256 text,
    target_packet_byte_count integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    grant_record private.recognition_study_capture_grants%rowtype;
    ticket_record private.recognition_study_capture_tickets%rowtype;
    existing_capture private.recognition_study_raw_captures%rowtype;
    stored_capture private.recognition_study_raw_captures%rowtype;
    decoded_packet bytea;
    grant_ticket jsonb;
    grant_completed boolean := false;
    ingestion_time timestamptz := pg_catalog.clock_timestamp();
begin
    if target_owner_id is null
        or target_capture_authorization_id is null
        or target_signed_grant_sha256 is null
        or target_signed_grant_sha256 !~ '^[0-9a-f]{64}$'
        or jsonb_typeof(target_envelope) <> 'object'
        or target_envelope_sha256 is null
        or target_envelope_sha256 !~ '^[0-9a-f]{64}$'
        or target_packet_sha256 is null
        or target_packet_sha256 !~ '^[0-9a-f]{64}$'
        or target_packet_byte_count is null
        or target_packet_byte_count not between 1 and 4194304
        or target_packet_base64 is null
        or octet_length(target_packet_base64) > 5592408
        or octet_length(target_packet_base64) % 4 <> 0
        or target_packet_base64 !~ '^[A-Za-z0-9+/]*={0,2}$' then
        raise exception 'capture upload has invalid required fields';
    end if;

    begin
        decoded_packet := decode(target_packet_base64, 'base64');
    exception when others then
        raise exception 'capture packet is not canonical base64';
    end;

    if octet_length(decoded_packet) <> target_packet_byte_count
        or encode(extensions.digest(decoded_packet, 'sha256'), 'hex')
            <> target_packet_sha256 then
        raise exception 'capture packet digest or byte count does not match';
    end if;

    select grants.*
    into grant_record
    from private.recognition_study_capture_grants grants
    join private.recognition_study_capture_tickets tickets
        on tickets.authorization_id = grants.authorization_id
    where grants.owner_id = target_owner_id
        and tickets.capture_authorization_id = target_capture_authorization_id;

    if not found then
        raise exception 'capture authorization was not found for this owner';
    end if;

    perform 1
    from private.recognition_study_consents
    where owner_id = target_owner_id
        and consent_record_id = grant_record.consent_record_id
        and status = 'active'
        and raw_stroke_donation_authorized
    for share;

    if not found
        or grant_record.consent_withdrawn_at is not null
        then
        raise exception 'active raw-stroke research consent is required';
    end if;

    select * into grant_record
    from private.recognition_study_capture_grants
    where authorization_id = grant_record.authorization_id
        and owner_id = target_owner_id
    for update;

    select * into ticket_record
    from private.recognition_study_capture_tickets
    where capture_authorization_id = target_capture_authorization_id
        and authorization_id = grant_record.authorization_id
    for update;

    if not found
        or grant_record.consent_withdrawn_at is not null
        or ticket_record.consent_withdrawn_at is not null then
        raise exception 'capture authorization changed while being consumed';
    end if;

    if grant_record.signed_grant_sha256 <> target_signed_grant_sha256 then
        raise exception 'signed grant digest does not match authorization';
    end if;

    grant_ticket := grant_record.signed_grant
        -> 'payload'
        -> 'captureTickets'
        -> ticket_record.ordinal;

    if target_envelope ->> 'schemaVersion'
            is distinct from 'recognition-study-authorized-capture-envelope-v1'
        or target_envelope ->> 'artifactKind'
            is distinct from 'externally-authorized-trajectory-v1'
        or (target_envelope ->> 'grantAuthorizationID')::uuid
            is distinct from grant_record.authorization_id
        or (target_envelope ->> 'serviceSessionID')::uuid
            is distinct from grant_record.service_session_id
        or (target_envelope ->> 'captureAuthorizationID')::uuid
            is distinct from ticket_record.capture_authorization_id
        or (target_envelope ->> 'ticketOrdinal')::integer
            is distinct from ticket_record.ordinal
        or target_envelope ->> 'signedGrantSHA256'
            is distinct from grant_record.signed_grant_sha256
        or target_envelope -> 'trajectoryDescriptor'
            ->> 'canonicalPacketSHA256' is distinct from target_packet_sha256
        or (target_envelope -> 'trajectoryDescriptor'
            ->> 'canonicalPacketByteCount')::integer
            is distinct from target_packet_byte_count
        or target_envelope -> 'clientAppContext' ->> 'bundleIdentifier'
            is distinct from grant_record.signed_grant -> 'payload'
                -> 'clientRequirements' ->> 'expectedBundleIdentifier'
        or target_envelope -> 'clientAppContext' ->> 'buildNumber' is null
        or target_envelope -> 'clientAppContext' ->> 'buildNumber'
            !~ '^(0|[1-9][0-9]{0,15})$'
        or (target_envelope -> 'clientAppContext' ->> 'buildNumber')::numeric
            > 9007199254740991
        or (target_envelope -> 'clientAppContext' ->> 'buildNumber')::bigint
            < (grant_record.signed_grant -> 'payload'
                -> 'clientRequirements' ->> 'minimumBuildNumber')::bigint
        or grant_ticket ->> 'captureAuthorizationID'
            is distinct from ticket_record.capture_authorization_id::text
        or (grant_ticket ->> 'ordinal')::integer
            is distinct from ticket_record.ordinal
        or target_envelope -> 'clientObservedSurface'
            ->> 'presentedChartStyle'
                is distinct from grant_ticket ->> 'presentedChartStyle'
        or target_envelope -> 'clientObservedSurface'
            ->> 'clientObservedOrientation'
                is distinct from grant_ticket ->> 'requestedOrientation'
        or target_envelope -> 'clientObservedSurface'
            ->> 'presentedPaceInstruction'
                is distinct from grant_ticket ->> 'presentedPace'
        or target_envelope -> 'clientObservedSurface'
            ->> 'presentedSizeInstruction'
                is distinct from grant_ticket ->> 'presentedSize'
        or target_envelope -> 'clientObservedSurface'
            ->> 'presentedConstructionInstruction'
                is distinct from grant_ticket ->> 'presentedConstruction' then
        raise exception 'capture envelope does not match its grant ticket';
    end if;

    select * into existing_capture
    from private.recognition_study_raw_captures
    where capture_authorization_id = target_capture_authorization_id;

    if found then
        if existing_capture.status <> 'received'
            or existing_capture.authorization_id <> grant_record.authorization_id
            or existing_capture.envelope <> target_envelope
            or existing_capture.envelope_sha256 <> target_envelope_sha256
            or existing_capture.canonical_packet <> decoded_packet
            or existing_capture.canonical_packet_sha256 <> target_packet_sha256
            or existing_capture.canonical_packet_byte_count
                <> target_packet_byte_count then
            raise exception 'capture ticket was already used with different bytes';
        end if;

        return jsonb_build_object(
            'accepted', true,
            'canonicalPacketByteCount',
                existing_capture.canonical_packet_byte_count,
            'canonicalPacketSHA256',
                existing_capture.canonical_packet_sha256,
            'captureAuthorizationID',
                existing_capture.capture_authorization_id,
            'envelopeSHA256', existing_capture.envelope_sha256,
            'grantCompleted', existing_capture.grant_completed_at_receipt,
            'receiptID', existing_capture.receipt_id,
            'receivedAtUnixMilliseconds',
                (extract(epoch from existing_capture.received_at) * 1000)::bigint,
            'replayed', true,
            'schemaVersion', 'recognition-study-capture-receipt-v1'
        );
    end if;

    if grant_record.status <> 'issued'
        or ticket_record.status <> 'issued'
        or ingestion_time < grant_record.not_before
        or ingestion_time >= grant_record.expires_at then
        raise exception 'capture authorization is not active';
    end if;

    if grant_record.signed_grant -> 'payload' -> 'consentBinding'
            ->> 'retentionPolicyVersion' <> 'retention-12-months-v1' then
        raise exception 'capture retention policy is unsupported';
    end if;

    select not exists (
        select 1
        from private.recognition_study_capture_tickets
        where authorization_id = grant_record.authorization_id
            and capture_authorization_id <> target_capture_authorization_id
            and status = 'issued'
    ) into grant_completed;

    insert into private.recognition_study_raw_captures (
        capture_authorization_id,
        authorization_id,
        envelope,
        envelope_sha256,
        canonical_packet,
        canonical_packet_sha256,
        canonical_packet_byte_count,
        grant_completed_at_receipt,
        received_at,
        retention_deadline
    ) values (
        target_capture_authorization_id,
        grant_record.authorization_id,
        target_envelope,
        target_envelope_sha256,
        decoded_packet,
        target_packet_sha256,
        target_packet_byte_count,
        grant_completed,
        ingestion_time,
        ingestion_time + interval '12 months'
    )
    returning * into stored_capture;

    update private.recognition_study_capture_tickets
    set status = 'consumed',
        consumed_at = ingestion_time
    where capture_authorization_id = target_capture_authorization_id
        and status = 'issued';

    if grant_completed then
        update private.recognition_study_capture_grants
        set status = 'completed',
            completed_at = ingestion_time
        where authorization_id = grant_record.authorization_id
            and status = 'issued';
        grant_completed := true;
    end if;

    return jsonb_build_object(
        'accepted', true,
        'canonicalPacketByteCount', stored_capture.canonical_packet_byte_count,
        'canonicalPacketSHA256', stored_capture.canonical_packet_sha256,
        'captureAuthorizationID', stored_capture.capture_authorization_id,
        'envelopeSHA256', stored_capture.envelope_sha256,
        'grantCompleted', grant_completed,
        'receiptID', stored_capture.receipt_id,
        'receivedAtUnixMilliseconds',
            (extract(epoch from stored_capture.received_at) * 1000)::bigint,
        'replayed', false,
        'schemaVersion', 'recognition-study-capture-receipt-v1'
    );
end;
$$;

create or replace function public.purge_expired_recognition_study_captures(
    run_at timestamptz default pg_catalog.clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    deleted_capture_count integer;
begin
    if run_at is null then
        raise exception 'retention run time is required';
    end if;

    update private.recognition_study_raw_captures
    set status = 'deleted',
        envelope = null,
        envelope_sha256 = null,
        canonical_packet = null,
        canonical_packet_sha256 = null,
        canonical_packet_byte_count = null,
        deleted_at = run_at,
        deletion_reason = 'retention-expired'
    where status = 'received'
        and retention_deadline <= run_at;
    get diagnostics deleted_capture_count = row_count;

    return jsonb_build_object(
        'deletedCaptureCount', deleted_capture_count,
        'runAtUnixMilliseconds',
            (extract(epoch from run_at) * 1000)::bigint
    );
end;
$$;

create or replace function public.withdraw_recognition_study_consent(
    target_owner_id uuid,
    target_consent_record_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    withdrawn_consent_count integer;
    revoked_grant_count integer;
    revoked_ticket_count integer;
    marked_nonissued_grant_count integer;
    marked_nonissued_ticket_count integer;
    deleted_capture_count integer;
    consent private.recognition_study_consents%rowtype;
    withdrawal_time timestamptz := pg_catalog.clock_timestamp();
begin
    select * into consent
    from private.recognition_study_consents
    where owner_id = target_owner_id
        and consent_record_id = target_consent_record_id
    for update;

    if not found then
        raise exception 'consent record was not found';
    end if;

    if consent.status = 'withdrawn' then
        return jsonb_build_object(
            'alreadyWithdrawn', true,
            'deletedCaptureCount', 0,
            'markedGrantCount', 0,
            'markedTicketCount', 0,
            'revokedGrantCount', 0,
            'revokedTicketCount', 0,
            'withdrawn', true
        );
    end if;

    update private.recognition_study_consents
    set status = 'withdrawn',
        withdrawn_at = withdrawal_time
    where owner_id = target_owner_id
        and consent_record_id = target_consent_record_id
        and status = 'active';
    get diagnostics withdrawn_consent_count = row_count;

    if withdrawn_consent_count <> 1 then
        raise exception 'active consent record could not be withdrawn';
    end if;

    update private.recognition_study_raw_captures captures
    set status = 'deleted',
        envelope = null,
        envelope_sha256 = null,
        canonical_packet = null,
        canonical_packet_sha256 = null,
        canonical_packet_byte_count = null,
        deleted_at = withdrawal_time,
        deletion_reason = 'consent-withdrawn'
    from private.recognition_study_capture_grants grants
    where grants.consent_record_id = target_consent_record_id
        and grants.authorization_id = captures.authorization_id
        and captures.status = 'received';
    get diagnostics deleted_capture_count = row_count;

    update private.recognition_study_capture_tickets tickets
    set status = 'revoked',
        revoked_at = withdrawal_time,
        consent_withdrawn_at = withdrawal_time
    from private.recognition_study_capture_grants grants
    where grants.consent_record_id = target_consent_record_id
        and grants.authorization_id = tickets.authorization_id
        and tickets.status = 'issued';
    get diagnostics revoked_ticket_count = row_count;

    update private.recognition_study_capture_tickets tickets
    set consent_withdrawn_at = withdrawal_time
    from private.recognition_study_capture_grants grants
    where grants.consent_record_id = target_consent_record_id
        and grants.authorization_id = tickets.authorization_id
        and tickets.status <> 'issued'
        and tickets.consent_withdrawn_at is null;
    get diagnostics marked_nonissued_ticket_count = row_count;

    update private.recognition_study_capture_grants
    set status = 'revoked',
        revoked_at = withdrawal_time,
        consent_withdrawn_at = withdrawal_time
    where consent_record_id = target_consent_record_id
        and status = 'issued';
    get diagnostics revoked_grant_count = row_count;

    update private.recognition_study_capture_grants
    set consent_withdrawn_at = withdrawal_time
    where consent_record_id = target_consent_record_id
        and status <> 'issued'
        and consent_withdrawn_at is null;
    get diagnostics marked_nonissued_grant_count = row_count;

    return jsonb_build_object(
        'alreadyWithdrawn', false,
        'deletedCaptureCount', deleted_capture_count,
        'markedGrantCount',
            revoked_grant_count + marked_nonissued_grant_count,
        'markedTicketCount',
            revoked_ticket_count + marked_nonissued_ticket_count,
        'revokedGrantCount', revoked_grant_count,
        'revokedTicketCount', revoked_ticket_count,
        'withdrawn', true
    );
end;
$$;

revoke all on function public.consume_recognition_study_capture(
    uuid, uuid, text, jsonb, text, text, text, integer
) from public, anon, authenticated;
revoke all on function public.purge_expired_recognition_study_captures(
    timestamptz
) from public, anon, authenticated;

grant execute on function public.consume_recognition_study_capture(
    uuid, uuid, text, jsonb, text, text, text, integer
) to service_role;
grant execute on function public.purge_expired_recognition_study_captures(
    timestamptz
) to service_role;

create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
    'recognition-study-retention-purge-v1',
    '17 3 * * *',
    'select public.purge_expired_recognition_study_captures();'
);
