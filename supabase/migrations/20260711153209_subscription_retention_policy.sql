alter table public.subscriptions
    add column if not exists app_store_auto_renew_status boolean,
    add column if not exists cloud_retention_deadline timestamptz,
    add column if not exists expiration_warning_sent_at timestamptz,
    add column if not exists cloud_retention_deleted_at timestamptz;

create index if not exists subscriptions_active_expiration_warning_idx
    on public.subscriptions(entitlement_expires_at)
    where provider = 'storekit'
        and status = 'active'
        and app_store_auto_renew_status is false
        and expiration_warning_sent_at is null;

create index if not exists subscriptions_cloud_retention_deadline_idx
    on public.subscriptions(cloud_retention_deadline)
    where provider = 'storekit'
        and status <> 'active'
        and cloud_retention_deleted_at is null;

update public.subscriptions
set cloud_retention_deadline = coalesce(
        grace_period_expires_at,
        entitlement_expires_at,
        current_period_end,
        updated_at
    )
where provider = 'storekit'
    and status <> 'active'
    and cloud_retention_deadline is null
    and app_store_status in ('grace', 'billing_retry', 'expired', 'revoked', 'refunded');

create table if not exists private.subscription_retention_events (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    event_type text not null check (event_type in ('expiration_warning', 'cloud_deleted')),
    recipient_email text,
    subject text not null,
    body text not null,
    dedupe_key text not null unique,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    dispatch_attempted_at timestamptz,
    dispatch_attempt_count integer not null default 0,
    sent_at timestamptz,
    send_error text
);

revoke all on table private.subscription_retention_events from public, anon, authenticated;
grant select, insert, update, delete on table private.subscription_retention_events to service_role;

create or replace function private.run_subscription_retention_jobs(run_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
    warning_event_count integer := 0;
    marked_warning_count integer := 0;
    deletion_event_count integer := 0;
begin
    with warning_candidates as (
        select
            subscriptions.id as subscription_id,
            subscriptions.owner_id,
            profiles.email as recipient_email,
            subscriptions.entitlement_expires_at,
            'expiration_warning:' || subscriptions.owner_id::text || ':' || subscriptions.entitlement_expires_at::text as dedupe_key
        from public.subscriptions
        left join public.profiles
            on profiles.id = subscriptions.owner_id
        where subscriptions.provider = 'storekit'
            and subscriptions.plan = 'studioSubscription'
            and subscriptions.status = 'active'
            and subscriptions.app_store_auto_renew_status is false
            and subscriptions.entitlement_expires_at is not null
            and subscriptions.entitlement_expires_at > run_at
            and subscriptions.entitlement_expires_at <= run_at + interval '24 hours'
            and subscriptions.expiration_warning_sent_at is null
    ),
    inserted_warnings as (
        insert into private.subscription_retention_events (
            owner_id,
            event_type,
            recipient_email,
            subject,
            body,
            dedupe_key,
            metadata
        )
        select
            owner_id,
            'expiration_warning',
            recipient_email,
            'Your iChart Pro access ends soon',
            'Your iChart Pro subscription is scheduled to end on '
                || to_char(entitlement_expires_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI "UTC"')
                || '. Local and cloud charts remain available until then. After Pro ends, cloud backup will be removed and chart editing will stay locked until you choose 3 Basic charts.',
            dedupe_key,
            jsonb_build_object(
                'subscription_id', subscription_id,
                'entitlement_expires_at', entitlement_expires_at
            )
        from warning_candidates
        on conflict (dedupe_key) do nothing
        returning 1
    ),
    marked_warnings as (
        update public.subscriptions
        set expiration_warning_sent_at = run_at
        from warning_candidates
        where subscriptions.id = warning_candidates.subscription_id
            and subscriptions.expiration_warning_sent_at is null
        returning subscriptions.id
    )
    select
        (select count(*) from inserted_warnings),
        (select count(*) from marked_warnings)
    into warning_event_count, marked_warning_count;

    with deletion_candidates as (
        select
            subscriptions.id as subscription_id,
            subscriptions.owner_id,
            profiles.email as recipient_email,
            subscriptions.cloud_retention_deadline,
            subscriptions.entitlement_expires_at,
            subscriptions.grace_period_expires_at,
            subscriptions.app_store_status,
            'cloud_deleted:' || subscriptions.owner_id::text || ':' || subscriptions.cloud_retention_deadline::text as dedupe_key
        from public.subscriptions
        left join public.profiles
            on profiles.id = subscriptions.owner_id
        where subscriptions.provider = 'storekit'
            and subscriptions.status <> 'active'
            and subscriptions.cloud_retention_deleted_at is null
            and subscriptions.cloud_retention_deadline is not null
            and subscriptions.cloud_retention_deadline <= run_at
            and subscriptions.app_store_status in ('grace', 'billing_retry', 'expired', 'revoked', 'refunded')
            and (
                subscriptions.app_store_status in ('revoked', 'refunded')
                or coalesce(
                    subscriptions.grace_period_expires_at,
                    subscriptions.entitlement_expires_at,
                    subscriptions.cloud_retention_deadline
                ) <= run_at
            )
    ),
    deleted_documents as (
        delete from public.chart_documents
        using deletion_candidates
        where chart_documents.owner_id = deletion_candidates.owner_id
        returning chart_documents.owner_id
    ),
    deleted_document_counts as (
        select owner_id, count(*) as deleted_document_count
        from deleted_documents
        group by owner_id
    ),
    marked_deletions as (
        update public.subscriptions
        set cloud_retention_deleted_at = run_at
        from deletion_candidates
        where subscriptions.id = deletion_candidates.subscription_id
            and subscriptions.cloud_retention_deleted_at is null
        returning
            deletion_candidates.subscription_id,
            deletion_candidates.owner_id,
            deletion_candidates.recipient_email,
            deletion_candidates.cloud_retention_deadline,
            deletion_candidates.entitlement_expires_at,
            deletion_candidates.grace_period_expires_at,
            deletion_candidates.app_store_status,
            deletion_candidates.dedupe_key
    ),
    inserted_deletions as (
        insert into private.subscription_retention_events (
            owner_id,
            event_type,
            recipient_email,
            subject,
            body,
            dedupe_key,
            metadata
        )
        select
            marked_deletions.owner_id,
            'cloud_deleted',
            marked_deletions.recipient_email,
            'Your iChart cloud backup was removed',
            'Your iChart Pro subscription has ended. Cloud backup is no longer available. Your local charts remain on this device, but chart editing stays locked until you choose 3 Basic charts.',
            marked_deletions.dedupe_key,
            jsonb_build_object(
                'subscription_id', marked_deletions.subscription_id,
                'cloud_retention_deadline', marked_deletions.cloud_retention_deadline,
                'entitlement_expires_at', marked_deletions.entitlement_expires_at,
                'grace_period_expires_at', marked_deletions.grace_period_expires_at,
                'app_store_status', marked_deletions.app_store_status,
                'deleted_document_count', coalesce(deleted_document_counts.deleted_document_count, 0)
            )
        from marked_deletions
        left join deleted_document_counts
            on deleted_document_counts.owner_id = marked_deletions.owner_id
        on conflict (dedupe_key) do nothing
        returning 1
    )
    select count(*) into deletion_event_count
    from inserted_deletions;

    return jsonb_build_object(
        'expiration_warning_events', warning_event_count,
        'expiration_warning_rows_marked', marked_warning_count,
        'cloud_deleted_events', deletion_event_count,
        'ran_at', run_at
    );
end;
$$;

revoke all on function private.run_subscription_retention_jobs(timestamptz)
    from public, anon, authenticated;
grant execute on function private.run_subscription_retention_jobs(timestamptz)
    to service_role;

create or replace function public.run_subscription_retention_jobs(run_at timestamptz default now())
returns jsonb
language sql
security definer
set search_path = public, private, auth, pg_temp
as $$
    select private.run_subscription_retention_jobs(run_at);
$$;

revoke all on function public.run_subscription_retention_jobs(timestamptz)
    from public, anon, authenticated;
grant execute on function public.run_subscription_retention_jobs(timestamptz)
    to service_role;

create or replace function public.claim_subscription_retention_events(batch_limit integer default 25)
returns table (
    id uuid,
    recipient_email text,
    subject text,
    body text
)
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
begin
    return query
    with candidates as (
        select events.id
        from private.subscription_retention_events events
        where events.sent_at is null
            and events.recipient_email is not null
            and length(trim(events.recipient_email)) > 0
            and coalesce(events.dispatch_attempt_count, 0) < 5
            and (
                events.dispatch_attempted_at is null
                or events.dispatch_attempted_at <= now() - interval '15 minutes'
            )
        order by events.created_at asc
        limit least(greatest(batch_limit, 0), 50)
        for update skip locked
    ),
    claimed as (
        update private.subscription_retention_events events
        set
            dispatch_attempted_at = now(),
            dispatch_attempt_count = coalesce(events.dispatch_attempt_count, 0) + 1,
            send_error = null
        from candidates
        where events.id = candidates.id
        returning events.id, events.recipient_email, events.subject, events.body
    )
    select
        claimed.id,
        claimed.recipient_email,
        claimed.subject,
        claimed.body
    from claimed;
end;
$$;

revoke all on function public.claim_subscription_retention_events(integer)
    from public, anon, authenticated;
grant execute on function public.claim_subscription_retention_events(integer)
    to service_role;

create or replace function public.mark_subscription_retention_event_sent(event_id uuid)
returns void
language sql
security definer
set search_path = public, private, auth, pg_temp
as $$
    update private.subscription_retention_events
    set
        sent_at = now(),
        send_error = null
    where id = event_id;
$$;

revoke all on function public.mark_subscription_retention_event_sent(uuid)
    from public, anon, authenticated;
grant execute on function public.mark_subscription_retention_event_sent(uuid)
    to service_role;

create or replace function public.mark_subscription_retention_event_failed(
    event_id uuid,
    error_message text
)
returns void
language sql
security definer
set search_path = public, private, auth, pg_temp
as $$
    update private.subscription_retention_events
    set send_error = left(coalesce(error_message, 'Unknown email dispatch failure.'), 1000)
    where id = event_id
        and sent_at is null;
$$;

revoke all on function public.mark_subscription_retention_event_failed(uuid, text)
    from public, anon, authenticated;
grant execute on function public.mark_subscription_retention_event_failed(uuid, text)
    to service_role;
