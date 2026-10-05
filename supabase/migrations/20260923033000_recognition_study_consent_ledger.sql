create sequence private.recognition_study_consent_event_epoch_seq
    as bigint
    minvalue 1
    start with 1;

create table private.recognition_study_consent_policy_presentations (
    presentation_id text primary key check (
        presentation_id ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
    ),
    presentation_sha256 text not null unique check (
        presentation_sha256 ~ '^[0-9a-f]{64}$'
    ),
    presentation_artifact bytea not null check (
        octet_length(presentation_artifact) between 1 and 1048576
        and encode(
            extensions.digest(presentation_artifact, 'sha256'),
            'hex'
        ) = presentation_sha256
    ),
    consent_document_url text not null check (
        octet_length(consent_document_url) between 9 and 2048
        and consent_document_url ~ '^https://[^#]+$'
        and consent_document_url !~ '^https://[^/]*@'
    ),
    scope text not null check (scope = 'chord-recognition-research-v1'),
    consent_ledger_version text not null check (
        consent_ledger_version ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
    ),
    consent_text_version text not null check (
        consent_text_version ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
    ),
    privacy_notice_version text not null check (
        privacy_notice_version ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
    ),
    data_use_policy_version text not null check (
        data_use_policy_version ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
    ),
    retention_policy_version text not null check (
        retention_policy_version ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
    ),
    raw_stroke_donation_required boolean not null check (
        raw_stroke_donation_required
    ),
    enabled boolean not null default false,
    created_at timestamptz not null default pg_catalog.clock_timestamp(),
    constraint recognition_study_consent_policy_id_digest_key unique (
        presentation_id,
        presentation_sha256
    )
);

create unique index recognition_study_one_enabled_consent_policy_idx
    on private.recognition_study_consent_policy_presentations (enabled)
    where enabled;

create table private.recognition_study_writer_registry (
    owner_id uuid primary key references auth.users(id) on delete cascade,
    protected_writer_id uuid not null default extensions.gen_random_uuid() unique,
    created_at timestamptz not null default pg_catalog.clock_timestamp(),
    constraint recognition_study_writer_owner_protected_key unique (
        owner_id,
        protected_writer_id
    )
);

alter table private.recognition_study_consents
    add column authority_version text not null default 'legacy-untrusted-v0'
        check (authority_version in ('legacy-untrusted-v0', 'server-authored-v1')),
    add column protected_writer_id uuid,
    add column client_request_id uuid,
    add column acceptance_request_sha256 text check (
        acceptance_request_sha256 is null
        or acceptance_request_sha256 ~ '^[0-9a-f]{64}$'
    ),
    add column presentation_id text,
    add column presentation_sha256 text check (
        presentation_sha256 is null
        or presentation_sha256 ~ '^[0-9a-f]{64}$'
    ),
    add column consent_artifact bytea,
    add column acceptance_event_epoch bigint,
    add column latest_event_epoch bigint;

alter table private.recognition_study_consents
    add constraint recognition_study_consents_writer_fkey foreign key (
        owner_id,
        protected_writer_id
    ) references private.recognition_study_writer_registry (
        owner_id,
        protected_writer_id
    ) on delete cascade,
    add constraint recognition_study_consents_policy_fkey foreign key (
        presentation_id,
        presentation_sha256
    ) references private.recognition_study_consent_policy_presentations (
        presentation_id,
        presentation_sha256
    ),
    add constraint recognition_study_consents_server_authority_check check (
        authority_version = 'legacy-untrusted-v0'
        or (
            protected_writer_id is not null
            and client_request_id is not null
            and acceptance_request_sha256 is not null
            and presentation_id is not null
            and presentation_sha256 is not null
            and consent_artifact is not null
            and acceptance_event_epoch is not null
            and latest_event_epoch is not null
            and consent_ledger_epoch = acceptance_event_epoch
            and latest_event_epoch >= acceptance_event_epoch
            and encode(
                extensions.digest(consent_artifact, 'sha256'),
                'hex'
            ) = consent_record_sha256
        )
    );

create unique index recognition_study_consents_owner_client_request_idx
    on private.recognition_study_consents (owner_id, client_request_id)
    where client_request_id is not null;

create table private.recognition_study_consent_requests (
    owner_id uuid not null references auth.users(id) on delete cascade,
    client_request_id uuid not null,
    operation text not null check (operation in ('accept', 'withdraw')),
    request_sha256 text not null check (request_sha256 ~ '^[0-9a-f]{64}$'),
    consent_record_id uuid,
    response_snapshot jsonb not null check (
        jsonb_typeof(response_snapshot) = 'object'
    ),
    created_at timestamptz not null default pg_catalog.clock_timestamp(),
    primary key (owner_id, client_request_id)
);

create table private.recognition_study_consent_events (
    event_epoch bigint primary key check (event_epoch > 0),
    event_type text not null check (
        event_type in ('accepted', 'withdrawn', 'account-deletion')
    ),
    protected_writer_id uuid not null,
    consent_record_id uuid not null,
    client_request_id uuid,
    request_sha256 text check (
        request_sha256 is null or request_sha256 ~ '^[0-9a-f]{64}$'
    ),
    event_at timestamptz not null,
    event_artifact bytea not null,
    event_artifact_sha256 text not null check (
        event_artifact_sha256 ~ '^[0-9a-f]{64}$'
        and encode(
            extensions.digest(event_artifact, 'sha256'),
            'hex'
        ) = event_artifact_sha256
    ),
    created_at timestamptz not null default pg_catalog.clock_timestamp()
);

create index recognition_study_consent_events_writer_epoch_idx
    on private.recognition_study_consent_events (
        protected_writer_id,
        event_epoch
    );

alter table private.recognition_study_consent_policy_presentations
    enable row level security;
alter table private.recognition_study_consent_policy_presentations
    force row level security;
alter table private.recognition_study_writer_registry enable row level security;
alter table private.recognition_study_writer_registry force row level security;
alter table private.recognition_study_consent_requests enable row level security;
alter table private.recognition_study_consent_requests force row level security;
alter table private.recognition_study_consent_events enable row level security;
alter table private.recognition_study_consent_events force row level security;

revoke all on table private.recognition_study_consent_policy_presentations
    from public, anon, authenticated, service_role;
revoke all on table private.recognition_study_writer_registry
    from public, anon, authenticated, service_role;
revoke all on table private.recognition_study_consent_requests
    from public, anon, authenticated, service_role;
revoke all on table private.recognition_study_consent_events
    from public, anon, authenticated, service_role;
revoke all on sequence private.recognition_study_consent_event_epoch_seq
    from public, anon, authenticated, service_role;
revoke all on table private.recognition_study_consents from service_role;
revoke all on table private.recognition_study_capture_grants from service_role;
revoke all on table private.recognition_study_capture_tickets from service_role;
revoke all on sequence private.recognition_study_authorization_epoch_seq
    from service_role;
revoke usage on schema private from service_role;

create or replace function private.reject_recognition_study_ledger_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    raise exception 'recognition study consent ledger is append-only';
end;
$$;

create trigger recognition_study_consent_events_append_only
before update or delete on private.recognition_study_consent_events
for each row execute function private.reject_recognition_study_ledger_mutation();

create or replace function private.recognition_study_current_policy_summary()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select jsonb_build_object(
        'consentDocumentURL', policy.consent_document_url,
        'consentLedgerVersion', policy.consent_ledger_version,
        'consentTextVersion', policy.consent_text_version,
        'dataUsePolicyVersion', policy.data_use_policy_version,
        'presentationID', policy.presentation_id,
        'presentationSHA256', policy.presentation_sha256,
        'privacyNoticeVersion', policy.privacy_notice_version,
        'rawStrokeDonationRequired', policy.raw_stroke_donation_required,
        'retentionPolicyVersion', policy.retention_policy_version,
        'schemaVersion', 'recognition-study-consent-policy-v1',
        'scope', policy.scope
    )
    from private.recognition_study_consent_policy_presentations policy
    where policy.enabled
    limit 1
$$;

create or replace function private.recognition_study_consent_summary(
    target_consent_record_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select jsonb_build_object(
        'acceptedAtUnixMilliseconds',
            (extract(epoch from consent.accepted_at) * 1000)::bigint,
        'consentLedgerEpoch', consent.latest_event_epoch,
        'consentLedgerVersion', consent.consent_ledger_version,
        'consentRecordID', consent.consent_record_id,
        'consentRecordSHA256', consent.consent_record_sha256,
        'consentTextVersion', consent.consent_text_version,
        'dataUsePolicyVersion', consent.data_use_policy_version,
        'privacyNoticeVersion', consent.privacy_notice_version,
        'rawStrokeDonationAuthorized', consent.raw_stroke_donation_authorized,
        'retentionPolicyVersion', consent.retention_policy_version,
        'schemaVersion', 'recognition-study-consent-record-summary-v1',
        'scope', consent.scope,
        'status', consent.status,
        'withdrawnAtUnixMilliseconds', case
            when consent.withdrawn_at is null then null
            else (extract(epoch from consent.withdrawn_at) * 1000)::bigint
        end
    )
    from private.recognition_study_consents consent
    where consent.consent_record_id = target_consent_record_id
        and consent.authority_version = 'server-authored-v1'
$$;

create or replace function private.recognition_study_consent_store_response(
    target_consent_record_id uuid,
    target_status text,
    target_replayed boolean
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select jsonb_build_object(
        'consent', case
            when target_consent_record_id is null then null
            else private.recognition_study_consent_summary(
                target_consent_record_id
            )
        end,
        'currentPolicy', private.recognition_study_current_policy_summary(),
        'replayed', target_replayed,
        'schemaVersion', 'recognition-study-consent-store-response-v1',
        'status', target_status
    )
$$;

create or replace function public.accept_recognition_study_consent(
    target_client_request_id uuid,
    target_presentation_id text,
    target_presentation_sha256 text,
    target_explicit_raw_stroke_authorization boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_owner_id uuid := auth.uid();
    policy private.recognition_study_consent_policy_presentations%rowtype;
    existing_request private.recognition_study_consent_requests%rowtype;
    existing_consent_status text;
    protected_writer uuid;
    consent_record uuid := extensions.gen_random_uuid();
    acceptance_time timestamptz := pg_catalog.clock_timestamp();
    event_epoch bigint;
    request_document jsonb;
    request_digest text;
    consent_document jsonb;
    consent_bytes bytea;
    consent_digest text;
    event_document jsonb;
    event_bytes bytea;
    response_document jsonb;
begin
    if target_owner_id is null then
        raise exception 'a signed-in account is required';
    end if;
    if target_client_request_id is null
        or target_presentation_id is null
        or target_presentation_id !~ '^[a-z0-9][a-z0-9._-]{0,127}$'
        or target_presentation_sha256 is null
        or target_presentation_sha256 !~ '^[0-9a-f]{64}$'
        or target_explicit_raw_stroke_authorization is distinct from true then
        raise exception 'consent acceptance request is invalid';
    end if;

    request_document := jsonb_build_object(
        'clientRequestID', target_client_request_id,
        'explicitRawStrokeDonationAuthorization', true,
        'presentationID', target_presentation_id,
        'presentationSHA256', target_presentation_sha256,
        'schemaVersion', 'recognition-study-consent-accept-request-v1'
    );
    request_digest := encode(
        extensions.digest(convert_to(request_document::text, 'utf8'), 'sha256'),
        'hex'
    );

    perform 1
    from auth.users
    where id = target_owner_id
    for key share;
    if not found then
        raise exception 'signed-in account is unavailable';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'recognition-study-consent:' || target_owner_id::text,
            0
        )
    );

    select * into existing_request
    from private.recognition_study_consent_requests
    where owner_id = target_owner_id
        and client_request_id = target_client_request_id;
    if found then
        if existing_request.operation <> 'accept'
            or existing_request.request_sha256 <> request_digest then
            raise exception 'consent request id was already used with different bytes';
        end if;
        select status into existing_consent_status
        from private.recognition_study_consents
        where owner_id = target_owner_id
            and consent_record_id = existing_request.consent_record_id
            and authority_version = 'server-authored-v1';
        if not found then
            raise exception 'consent replay record is unavailable';
        end if;
        return private.recognition_study_consent_store_response(
            existing_request.consent_record_id,
            existing_consent_status,
            true
        );
    end if;

    select * into policy
    from private.recognition_study_consent_policy_presentations
    where presentation_id = target_presentation_id
        and presentation_sha256 = target_presentation_sha256
        and enabled
    for share;
    if not found then
        raise exception 'reviewed consent presentation is unavailable';
    end if;

    perform 1
    from private.recognition_study_consents
    where owner_id = target_owner_id
        and scope = 'chord-recognition-research-v1'
        and status = 'active'
    for update;
    if found then
        raise exception 'an active consent record already exists for this owner';
    end if;

    insert into private.recognition_study_writer_registry (owner_id)
    values (target_owner_id)
    on conflict (owner_id) do nothing;
    select protected_writer_id into protected_writer
    from private.recognition_study_writer_registry
    where owner_id = target_owner_id;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'recognition-study-consent-ledger-global',
            0
        )
    );
    event_epoch := nextval(
        'private.recognition_study_consent_event_epoch_seq'::regclass
    );
    consent_document := jsonb_build_object(
        'acceptedAtUnixMilliseconds',
            (extract(epoch from acceptance_time) * 1000)::bigint,
        'consentLedgerEpoch', event_epoch,
        'consentRecordID', consent_record,
        'explicitRawStrokeDonationAuthorization', true,
        'presentationID', policy.presentation_id,
        'presentationSHA256', policy.presentation_sha256,
        'schemaVersion', 'recognition-study-consent-record-v1',
        'scope', policy.scope
    );
    consent_bytes := convert_to(consent_document::text, 'utf8');
    consent_digest := encode(
        extensions.digest(consent_bytes, 'sha256'),
        'hex'
    );

    insert into private.recognition_study_consents (
        consent_record_id,
        owner_id,
        consent_ledger_epoch,
        consent_record_sha256,
        scope,
        consent_ledger_version,
        consent_text_version,
        privacy_notice_version,
        data_use_policy_version,
        retention_policy_version,
        raw_stroke_donation_authorized,
        accepted_at,
        authority_version,
        protected_writer_id,
        client_request_id,
        acceptance_request_sha256,
        presentation_id,
        presentation_sha256,
        consent_artifact,
        acceptance_event_epoch,
        latest_event_epoch
    ) overriding system value values (
        consent_record,
        target_owner_id,
        event_epoch,
        consent_digest,
        policy.scope,
        policy.consent_ledger_version,
        policy.consent_text_version,
        policy.privacy_notice_version,
        policy.data_use_policy_version,
        policy.retention_policy_version,
        true,
        acceptance_time,
        'server-authored-v1',
        protected_writer,
        target_client_request_id,
        request_digest,
        policy.presentation_id,
        policy.presentation_sha256,
        consent_bytes,
        event_epoch,
        event_epoch
    );

    event_document := jsonb_build_object(
        'consentRecordID', consent_record,
        'consentRecordSHA256', consent_digest,
        'eventAtUnixMilliseconds',
            (extract(epoch from acceptance_time) * 1000)::bigint,
        'eventEpoch', event_epoch,
        'eventType', 'accepted',
        'schemaVersion', 'recognition-study-consent-ledger-event-v1'
    );
    event_bytes := convert_to(event_document::text, 'utf8');
    insert into private.recognition_study_consent_events (
        event_epoch,
        event_type,
        protected_writer_id,
        consent_record_id,
        client_request_id,
        request_sha256,
        event_at,
        event_artifact,
        event_artifact_sha256
    ) values (
        event_epoch,
        'accepted',
        protected_writer,
        consent_record,
        target_client_request_id,
        request_digest,
        acceptance_time,
        event_bytes,
        encode(extensions.digest(event_bytes, 'sha256'), 'hex')
    );

    response_document := private.recognition_study_consent_store_response(
        consent_record,
        'active',
        false
    );
    insert into private.recognition_study_consent_requests (
        owner_id,
        client_request_id,
        operation,
        request_sha256,
        consent_record_id,
        response_snapshot
    ) values (
        target_owner_id,
        target_client_request_id,
        'accept',
        request_digest,
        consent_record,
        response_document
    );
    return response_document;
end;
$$;

create or replace function public.recognition_study_consent_status()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_owner_id uuid := auth.uid();
    consent private.recognition_study_consents%rowtype;
begin
    if target_owner_id is null then
        raise exception 'a signed-in account is required';
    end if;
    select * into consent
    from private.recognition_study_consents
    where owner_id = target_owner_id
        and authority_version = 'server-authored-v1'
    order by latest_event_epoch desc
    limit 1;
    if not found then
        return private.recognition_study_consent_store_response(
            null,
            'not-accepted',
            false
        );
    end if;
    return private.recognition_study_consent_store_response(
        consent.consent_record_id,
        consent.status,
        false
    );
end;
$$;

create or replace function private.apply_recognition_study_consent_withdrawal(
    target_owner_id uuid,
    target_consent_record_id uuid,
    target_event_type text,
    target_client_request_id uuid default null,
    target_request_sha256 text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    consent private.recognition_study_consents%rowtype;
    withdrawal_time timestamptz := pg_catalog.clock_timestamp();
    event_epoch bigint;
    event_document jsonb;
    event_bytes bytea;
begin
    if target_event_type not in ('withdrawn', 'account-deletion') then
        raise exception 'unsupported consent withdrawal event type';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'recognition-study-consent:' || target_owner_id::text,
            0
        )
    );
    select * into consent
    from private.recognition_study_consents
    where owner_id = target_owner_id
        and consent_record_id = target_consent_record_id
        and authority_version = 'server-authored-v1'
    for update;
    if not found then
        raise exception 'consent record was not found';
    end if;
    if consent.status = 'withdrawn' then
        return private.recognition_study_consent_store_response(
            consent.consent_record_id,
            'withdrawn',
            true
        );
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'recognition-study-consent-ledger-global',
            0
        )
    );

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

    update private.recognition_study_capture_tickets tickets
    set status = 'revoked',
        revoked_at = withdrawal_time,
        consent_withdrawn_at = withdrawal_time
    from private.recognition_study_capture_grants grants
    where grants.consent_record_id = target_consent_record_id
        and grants.authorization_id = tickets.authorization_id
        and tickets.status = 'issued';

    update private.recognition_study_capture_tickets tickets
    set consent_withdrawn_at = withdrawal_time
    from private.recognition_study_capture_grants grants
    where grants.consent_record_id = target_consent_record_id
        and grants.authorization_id = tickets.authorization_id
        and tickets.status <> 'issued'
        and tickets.consent_withdrawn_at is null;

    update private.recognition_study_capture_grants
    set status = 'revoked',
        revoked_at = withdrawal_time,
        consent_withdrawn_at = withdrawal_time
    where consent_record_id = target_consent_record_id
        and status = 'issued';

    update private.recognition_study_capture_grants
    set consent_withdrawn_at = withdrawal_time
    where consent_record_id = target_consent_record_id
        and status <> 'issued'
        and consent_withdrawn_at is null;

    event_epoch := nextval(
        'private.recognition_study_consent_event_epoch_seq'::regclass
    );
    update private.recognition_study_consents
    set status = 'withdrawn',
        withdrawn_at = withdrawal_time,
        latest_event_epoch = event_epoch
    where consent_record_id = target_consent_record_id;

    event_document := jsonb_build_object(
        'consentRecordID', target_consent_record_id,
        'consentRecordSHA256', consent.consent_record_sha256,
        'eventAtUnixMilliseconds',
            (extract(epoch from withdrawal_time) * 1000)::bigint,
        'eventEpoch', event_epoch,
        'eventType', target_event_type,
        'schemaVersion', 'recognition-study-consent-ledger-event-v1'
    );
    event_bytes := convert_to(event_document::text, 'utf8');
    insert into private.recognition_study_consent_events (
        event_epoch,
        event_type,
        protected_writer_id,
        consent_record_id,
        client_request_id,
        request_sha256,
        event_at,
        event_artifact,
        event_artifact_sha256
    ) values (
        event_epoch,
        target_event_type,
        consent.protected_writer_id,
        target_consent_record_id,
        target_client_request_id,
        target_request_sha256,
        withdrawal_time,
        event_bytes,
        encode(extensions.digest(event_bytes, 'sha256'), 'hex')
    );
    return private.recognition_study_consent_store_response(
        target_consent_record_id,
        'withdrawn',
        false
    );
end;
$$;

create or replace function public.withdraw_recognition_study_consent_v2(
    target_client_request_id uuid,
    target_consent_record_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_owner_id uuid := auth.uid();
    existing_request private.recognition_study_consent_requests%rowtype;
    request_document jsonb;
    request_digest text;
    response_document jsonb;
begin
    if target_owner_id is null then
        raise exception 'a signed-in account is required';
    end if;
    if target_client_request_id is null or target_consent_record_id is null then
        raise exception 'consent withdrawal request is invalid';
    end if;
    request_document := jsonb_build_object(
        'clientRequestID', target_client_request_id,
        'consentRecordID', target_consent_record_id,
        'schemaVersion', 'recognition-study-consent-withdraw-request-v1'
    );
    request_digest := encode(
        extensions.digest(convert_to(request_document::text, 'utf8'), 'sha256'),
        'hex'
    );
    perform 1
    from auth.users
    where id = target_owner_id
    for key share;
    if not found then
        raise exception 'signed-in account is unavailable';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'recognition-study-consent:' || target_owner_id::text,
            0
        )
    );
    select * into existing_request
    from private.recognition_study_consent_requests
    where owner_id = target_owner_id
        and client_request_id = target_client_request_id;
    if found then
        if existing_request.operation <> 'withdraw'
            or existing_request.request_sha256 <> request_digest then
            raise exception 'consent request id was already used with different bytes';
        end if;
        return private.recognition_study_consent_store_response(
            existing_request.consent_record_id,
            'withdrawn',
            true
        );
    end if;

    response_document := private.apply_recognition_study_consent_withdrawal(
        target_owner_id,
        target_consent_record_id,
        'withdrawn',
        target_client_request_id,
        request_digest
    );
    insert into private.recognition_study_consent_requests (
        owner_id,
        client_request_id,
        operation,
        request_sha256,
        consent_record_id,
        response_snapshot
    ) values (
        target_owner_id,
        target_client_request_id,
        'withdraw',
        request_digest,
        target_consent_record_id,
        response_document
    );
    return response_document;
end;
$$;

create or replace function private.handle_recognition_study_account_deletion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    consent_record record;
begin
    for consent_record in
        select consent_record_id
        from private.recognition_study_consents
        where owner_id = old.id
            and authority_version = 'server-authored-v1'
            and status = 'active'
        order by consent_record_id
    loop
        perform private.apply_recognition_study_consent_withdrawal(
            old.id,
            consent_record.consent_record_id,
            'account-deletion',
            null,
            null
        );
    end loop;
    return old;
end;
$$;

create trigger recognition_study_account_deletion_consent_ledger
before delete on auth.users
for each row execute function private.handle_recognition_study_account_deletion();

create or replace function public.prepare_recognition_study_capture_grant(
    target_owner_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    consent private.recognition_study_consents%rowtype;
    next_authorization_epoch bigint;
begin
    if target_owner_id is null then
        raise exception 'owner id is required';
    end if;
    select * into consent
    from private.recognition_study_consents
    where owner_id = target_owner_id
        and scope = 'chord-recognition-research-v1'
        and status = 'active'
        and raw_stroke_donation_authorized
        and authority_version = 'server-authored-v1'
    for share;
    if not found then
        return null;
    end if;
    next_authorization_epoch := nextval(
        'private.recognition_study_authorization_epoch_seq'::regclass
    );
    return jsonb_build_object(
        'authorizationEpoch', next_authorization_epoch,
        'consentBinding', jsonb_build_object(
            'consentLedgerEpoch', consent.acceptance_event_epoch,
            'consentLedgerVersion', consent.consent_ledger_version,
            'consentRecordID', consent.consent_record_id,
            'consentRecordSHA256', consent.consent_record_sha256,
            'consentTextVersion', consent.consent_text_version,
            'dataUsePolicyVersion', consent.data_use_policy_version,
            'privacyNoticeVersion', consent.privacy_notice_version,
            'rawStrokeDonationAuthorized', true,
            'retentionPolicyVersion', consent.retention_policy_version,
            'schemaVersion', 'recognition-study-consent-binding-v1',
            'scope', consent.scope
        )
    );
end;
$$;

create or replace function private.require_server_authored_recognition_study_grant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not exists (
        select 1
        from private.recognition_study_consents consent
        where consent.owner_id = new.owner_id
            and consent.consent_record_id = new.consent_record_id
            and consent.authority_version = 'server-authored-v1'
            and consent.status = 'active'
    ) then
        raise exception 'capture grant requires server-authored active consent';
    end if;
    return new;
end;
$$;

create trigger recognition_study_capture_grants_require_server_consent
before insert on private.recognition_study_capture_grants
for each row execute function private.require_server_authored_recognition_study_grant();

revoke all on function public.record_recognition_study_consent(
    uuid, uuid, text, text, text, text, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.withdraw_recognition_study_consent(uuid, uuid)
    from public, anon, authenticated, service_role;
revoke all on function public.accept_recognition_study_consent(
    uuid, text, text, boolean
) from public, anon, service_role;
revoke all on function public.recognition_study_consent_status()
    from public, anon, service_role;
revoke all on function public.withdraw_recognition_study_consent_v2(uuid, uuid)
    from public, anon, service_role;

grant execute on function public.accept_recognition_study_consent(
    uuid, text, text, boolean
) to authenticated;
grant execute on function public.recognition_study_consent_status()
    to authenticated;
grant execute on function public.withdraw_recognition_study_consent_v2(uuid, uuid)
    to authenticated;

revoke all on function private.reject_recognition_study_ledger_mutation()
    from public, anon, authenticated, service_role;
revoke all on function private.recognition_study_current_policy_summary()
    from public, anon, authenticated, service_role;
revoke all on function private.recognition_study_consent_summary(uuid)
    from public, anon, authenticated, service_role;
revoke all on function private.recognition_study_consent_store_response(
    uuid, text, boolean
) from public, anon, authenticated, service_role;
revoke all on function private.apply_recognition_study_consent_withdrawal(
    uuid, uuid, text, uuid, text
) from public, anon, authenticated, service_role;
revoke all on function private.handle_recognition_study_account_deletion()
    from public, anon, authenticated, service_role;
revoke all on function private.require_server_authored_recognition_study_grant()
    from public, anon, authenticated, service_role;
