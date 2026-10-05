create schema if not exists private;
revoke all on schema private from public;

create sequence private.recognition_study_authorization_epoch_seq
    as bigint
    minvalue 1
    start with 1;

create table private.recognition_study_consents (
    consent_record_id uuid primary key,
    owner_id uuid not null references auth.users(id) on delete cascade,
    consent_ledger_epoch bigint generated always as identity,
    consent_record_sha256 text not null check (
        consent_record_sha256 ~ '^[0-9a-f]{64}$'
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
    raw_stroke_donation_authorized boolean not null check (
        raw_stroke_donation_authorized
    ),
    status text not null default 'active' check (
        status in ('active', 'withdrawn')
    ),
    accepted_at timestamptz not null default now(),
    withdrawn_at timestamptz,
    created_at timestamptz not null default now(),
    constraint recognition_study_consents_withdrawal_state_check check (
        (status = 'active' and withdrawn_at is null)
        or (status = 'withdrawn' and withdrawn_at is not null)
    ),
    constraint recognition_study_consents_owner_record_key unique (
        owner_id,
        consent_record_id
    )
);

create unique index recognition_study_consents_owner_active_idx
    on private.recognition_study_consents (owner_id, scope)
    where status = 'active';

create index recognition_study_consents_owner_epoch_idx
    on private.recognition_study_consents (owner_id, consent_ledger_epoch desc);

create table private.recognition_study_capture_grants (
    authorization_id uuid primary key,
    service_session_id uuid not null unique,
    client_request_id uuid not null,
    owner_id uuid not null references auth.users(id) on delete cascade,
    consent_record_id uuid not null,
    authorization_epoch bigint not null unique check (authorization_epoch > 0),
    signed_grant_sha256 text not null unique check (
        signed_grant_sha256 ~ '^[0-9a-f]{64}$'
    ),
    signed_grant jsonb not null check (jsonb_typeof(signed_grant) = 'object'),
    dataset_version text not null check (
        dataset_version ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
    ),
    prompt_plan_version text not null check (
        prompt_plan_version ~ '^[a-z0-9][a-z0-9._-]{0,127}$'
    ),
    expected_capture_count smallint not null check (
        expected_capture_count between 1 and 256
    ),
    issued_at timestamptz not null,
    not_before timestamptz not null,
    expires_at timestamptz not null,
    status text not null default 'issued' check (
        status in ('issued', 'completed', 'revoked')
    ),
    consent_withdrawn_at timestamptz,
    completed_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz not null default now(),
    constraint recognition_study_capture_grants_consent_fkey foreign key (
        owner_id,
        consent_record_id
    ) references private.recognition_study_consents (
        owner_id,
        consent_record_id
    ) on delete cascade,
    constraint recognition_study_capture_grants_owner_request_key unique (
        owner_id,
        client_request_id
    ),
    constraint recognition_study_capture_grants_time_check check (
        issued_at <= not_before and not_before < expires_at
    ),
    constraint recognition_study_capture_grants_state_check check (
        (status = 'issued' and completed_at is null and revoked_at is null)
        or (status = 'completed' and completed_at is not null and revoked_at is null)
        or (status = 'revoked' and completed_at is null and revoked_at is not null)
    )
);

create index recognition_study_capture_grants_owner_status_idx
    on private.recognition_study_capture_grants (owner_id, status, expires_at);

create index recognition_study_capture_grants_consent_idx
    on private.recognition_study_capture_grants (consent_record_id);

create index recognition_study_capture_grants_expiry_idx
    on private.recognition_study_capture_grants (expires_at)
    where status = 'issued' and consent_withdrawn_at is null;

create table private.recognition_study_capture_tickets (
    capture_authorization_id uuid primary key,
    authorization_id uuid not null references
        private.recognition_study_capture_grants(authorization_id)
        on delete cascade,
    ordinal smallint not null check (ordinal between 0 and 255),
    prompt_id text not null check (
        prompt_id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
        and octet_length(prompt_id) <= 64
    ),
    status text not null default 'issued' check (
        status in ('issued', 'consumed', 'revoked')
    ),
    consent_withdrawn_at timestamptz,
    consumed_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz not null default now(),
    constraint recognition_study_capture_tickets_ordinal_key unique (
        authorization_id,
        ordinal
    ),
    constraint recognition_study_capture_tickets_prompt_key unique (
        authorization_id,
        prompt_id
    ),
    constraint recognition_study_capture_tickets_state_check check (
        (status = 'issued' and consumed_at is null and revoked_at is null)
        or (status = 'consumed' and consumed_at is not null and revoked_at is null)
        or (status = 'revoked' and consumed_at is null and revoked_at is not null)
    )
);

create index recognition_study_capture_tickets_grant_status_idx
    on private.recognition_study_capture_tickets (authorization_id, status);

alter table private.recognition_study_consents enable row level security;
alter table private.recognition_study_consents force row level security;
alter table private.recognition_study_capture_grants enable row level security;
alter table private.recognition_study_capture_grants force row level security;
alter table private.recognition_study_capture_tickets enable row level security;
alter table private.recognition_study_capture_tickets force row level security;

revoke all on table private.recognition_study_consents
    from public, anon, authenticated;
revoke all on table private.recognition_study_capture_grants
    from public, anon, authenticated;
revoke all on table private.recognition_study_capture_tickets
    from public, anon, authenticated;
revoke all on sequence private.recognition_study_authorization_epoch_seq
    from public, anon, authenticated;

grant usage on schema private to service_role;
grant select, insert, update on table private.recognition_study_consents
    to service_role;
grant select, insert, update on table private.recognition_study_capture_grants
    to service_role;
grant select, insert, update on table private.recognition_study_capture_tickets
    to service_role;
grant usage, select on sequence private.recognition_study_authorization_epoch_seq
    to service_role;

create or replace function public.record_recognition_study_consent(
    target_owner_id uuid,
    target_consent_record_id uuid,
    target_consent_record_sha256 text,
    target_consent_ledger_version text,
    target_consent_text_version text,
    target_privacy_notice_version text,
    target_data_use_policy_version text,
    target_retention_policy_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    stored private.recognition_study_consents%rowtype;
begin
    if target_owner_id is null or target_consent_record_id is null then
        raise exception 'owner and consent record ids are required';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'recognition-study-consent:' || target_owner_id::text,
            0
        )
    );

    select * into stored
    from private.recognition_study_consents
    where consent_record_id = target_consent_record_id;

    if found then
        if stored.owner_id <> target_owner_id
            or stored.consent_record_sha256 <> target_consent_record_sha256
            or stored.consent_ledger_version <> target_consent_ledger_version
            or stored.consent_text_version <> target_consent_text_version
            or stored.privacy_notice_version <> target_privacy_notice_version
            or stored.data_use_policy_version <> target_data_use_policy_version
            or stored.retention_policy_version <> target_retention_policy_version then
            raise exception 'consent record id already exists with different immutable fields';
        end if;
    else
        if exists (
            select 1
            from private.recognition_study_consents
            where owner_id = target_owner_id
                and scope = 'chord-recognition-research-v1'
                and status = 'active'
        ) then
            raise exception 'an active consent record already exists for this owner';
        end if;
        insert into private.recognition_study_consents (
            consent_record_id,
            owner_id,
            consent_record_sha256,
            scope,
            consent_ledger_version,
            consent_text_version,
            privacy_notice_version,
            data_use_policy_version,
            retention_policy_version,
            raw_stroke_donation_authorized
        ) values (
            target_consent_record_id,
            target_owner_id,
            target_consent_record_sha256,
            'chord-recognition-research-v1',
            target_consent_ledger_version,
            target_consent_text_version,
            target_privacy_notice_version,
            target_data_use_policy_version,
            target_retention_policy_version,
            true
        )
        returning * into stored;
    end if;

    return jsonb_build_object(
        'consentLedgerEpoch', stored.consent_ledger_epoch,
        'consentLedgerVersion', stored.consent_ledger_version,
        'consentRecordID', stored.consent_record_id,
        'consentRecordSHA256', stored.consent_record_sha256,
        'consentTextVersion', stored.consent_text_version,
        'dataUsePolicyVersion', stored.data_use_policy_version,
        'privacyNoticeVersion', stored.privacy_notice_version,
        'rawStrokeDonationAuthorized', stored.raw_stroke_donation_authorized,
        'retentionPolicyVersion', stored.retention_policy_version,
        'schemaVersion', 'recognition-study-consent-binding-v1',
        'scope', stored.scope,
        'status', stored.status
    );
end;
$$;

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
            'consentLedgerEpoch', consent.consent_ledger_epoch,
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

create or replace function public.commit_recognition_study_capture_grant(
    target_owner_id uuid,
    target_client_request_id uuid,
    target_signed_grant jsonb,
    target_signed_grant_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    payload jsonb;
    tickets jsonb;
    consent private.recognition_study_consents%rowtype;
    existing private.recognition_study_capture_grants%rowtype;
    target_authorization_id uuid;
    target_service_session_id uuid;
    target_consent_record_id uuid;
    target_authorization_epoch bigint;
    target_expected_capture_count integer;
    target_issued_at timestamptz;
    target_not_before timestamptz;
    target_expires_at timestamptz;
begin
    if target_owner_id is null
        or target_client_request_id is null
        or target_signed_grant is null
        or target_signed_grant_sha256 !~ '^[0-9a-f]{64}$' then
        raise exception 'owner, signed grant, and canonical digest are required';
    end if;

    payload := target_signed_grant -> 'payload';
    tickets := payload -> 'captureTickets';
    if jsonb_typeof(payload) <> 'object'
        or jsonb_typeof(tickets) <> 'array'
        or target_signed_grant ->> 'schemaVersion'
            <> 'recognition-study-signed-capture-grant-v1'
        or payload ->> 'schemaVersion'
            <> 'recognition-study-capture-grant-v1'
        or payload ->> 'artifactKind'
            <> 'externally-authorized-session-grant-v1'
        or payload ->> 'collectionProtocolVersion'
            <> 'writer-independent-capture-v2' then
        raise exception 'signed grant has the wrong fixed contract values';
    end if;

    target_authorization_id := (payload ->> 'authorizationID')::uuid;
    target_service_session_id := (payload ->> 'serviceSessionID')::uuid;
    target_consent_record_id :=
        (payload -> 'consentBinding' ->> 'consentRecordID')::uuid;
    target_authorization_epoch := (payload ->> 'authorizationEpoch')::bigint;
    target_expected_capture_count := (payload ->> 'expectedCaptureCount')::integer;
    target_issued_at := to_timestamp((payload ->> 'issuedAtUnixSeconds')::bigint);
    target_not_before := to_timestamp((payload ->> 'notBeforeUnixSeconds')::bigint);
    target_expires_at := to_timestamp((payload ->> 'expiresAtUnixSeconds')::bigint);

    perform 1
    from auth.users
    where id = target_owner_id
    for key share;
    if not found then
        raise exception 'capture grant owner is unavailable';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            target_owner_id::text || ':' || target_client_request_id::text,
            0
        )
    );

    if target_expected_capture_count < 1
        or target_expected_capture_count > 256
        or jsonb_array_length(tickets) <> target_expected_capture_count
        or target_authorization_epoch < 1
        or target_issued_at > target_not_before
        or target_not_before >= target_expires_at
        or target_expires_at <= pg_catalog.clock_timestamp() then
        raise exception 'signed grant has invalid count, epoch, or time invariants';
    end if;

    if not (
        select bool_and(
            (ticket ->> 'ordinal')::integer = ticket_ordinality - 1
        )
        from jsonb_array_elements(tickets) with ordinality
            as prompt(ticket, ticket_ordinality)
    ) then
        raise exception 'capture ticket ordinals must be contiguous';
    end if;

    select * into consent
    from private.recognition_study_consents
    where owner_id = target_owner_id
        and consent_record_id = target_consent_record_id
        and status = 'active'
        and raw_stroke_donation_authorized
    for share;

    if not found
        or consent.consent_ledger_epoch
            <> (payload -> 'consentBinding' ->> 'consentLedgerEpoch')::bigint
        or consent.consent_record_sha256
            <> payload -> 'consentBinding' ->> 'consentRecordSHA256' then
        raise exception 'signed grant is not bound to the active consent record';
    end if;

    select * into existing
    from private.recognition_study_capture_grants
    where owner_id = target_owner_id
        and client_request_id = target_client_request_id;

    if found then
        if existing.status <> 'issued'
            or existing.consent_withdrawn_at is not null
            or existing.expires_at <= pg_catalog.clock_timestamp() then
            raise exception 'stored capture authorization is no longer active';
        end if;
        return jsonb_build_object(
            'authorizationID', existing.authorization_id,
            'signedGrant', existing.signed_grant,
            'signedGrantSHA256', existing.signed_grant_sha256,
            'status', existing.status,
            'stored', false
        );
    end if;

    select * into existing
    from private.recognition_study_capture_grants
    where authorization_id = target_authorization_id;

    if found then
        if existing.owner_id <> target_owner_id
            or existing.signed_grant_sha256 <> target_signed_grant_sha256
            or existing.signed_grant <> target_signed_grant then
            raise exception 'authorization id already exists with different immutable fields';
        end if;
        if existing.status <> 'issued'
            or existing.consent_withdrawn_at is not null
            or existing.expires_at <= pg_catalog.clock_timestamp() then
            raise exception 'stored capture authorization is no longer active';
        end if;
        return jsonb_build_object(
            'authorizationID', existing.authorization_id,
            'signedGrant', existing.signed_grant,
            'signedGrantSHA256', existing.signed_grant_sha256,
            'status', existing.status,
            'stored', false
        );
    end if;

    insert into private.recognition_study_capture_grants (
        authorization_id,
        service_session_id,
        client_request_id,
        owner_id,
        consent_record_id,
        authorization_epoch,
        signed_grant_sha256,
        signed_grant,
        dataset_version,
        prompt_plan_version,
        expected_capture_count,
        issued_at,
        not_before,
        expires_at
    ) values (
        target_authorization_id,
        target_service_session_id,
        target_client_request_id,
        target_owner_id,
        target_consent_record_id,
        target_authorization_epoch,
        target_signed_grant_sha256,
        target_signed_grant,
        payload ->> 'datasetVersion',
        payload ->> 'promptPlanVersion',
        target_expected_capture_count,
        target_issued_at,
        target_not_before,
        target_expires_at
    );

    insert into private.recognition_study_capture_tickets (
        capture_authorization_id,
        authorization_id,
        ordinal,
        prompt_id
    )
    select
        (ticket ->> 'captureAuthorizationID')::uuid,
        target_authorization_id,
        (ticket ->> 'ordinal')::smallint,
        ticket ->> 'promptID'
    from jsonb_array_elements(tickets) as prompt(ticket);

    return jsonb_build_object(
        'authorizationID', target_authorization_id,
        'signedGrant', target_signed_grant,
        'signedGrantSHA256', target_signed_grant_sha256,
        'status', 'issued',
        'stored', true
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

revoke all on function public.record_recognition_study_consent(
    uuid, uuid, text, text, text, text, text, text
) from public, anon, authenticated;
revoke all on function public.prepare_recognition_study_capture_grant(uuid)
    from public, anon, authenticated;
revoke all on function public.commit_recognition_study_capture_grant(
    uuid, uuid, jsonb, text
) from public, anon, authenticated;
revoke all on function public.withdraw_recognition_study_consent(uuid, uuid)
    from public, anon, authenticated;

grant execute on function public.record_recognition_study_consent(
    uuid, uuid, text, text, text, text, text, text
) to service_role;
grant execute on function public.prepare_recognition_study_capture_grant(uuid)
    to service_role;
grant execute on function public.commit_recognition_study_capture_grant(
    uuid, uuid, jsonb, text
) to service_role;
grant execute on function public.withdraw_recognition_study_consent(uuid, uuid)
    to service_role;
