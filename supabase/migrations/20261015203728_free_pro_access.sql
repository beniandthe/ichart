-- Feature access is free while the product is being stabilized. This is NOT a
-- purchase, promotional trial, renewal, or rewrite of Apple subscription truth.
-- No client/service-role switch can end this phase: a separately reviewed
-- transition migration, customer notice and explicit future purchase consent
-- are required before paid gating or subscription-based deletion can resume.
create table private.ichart_free_access_policy (
    singleton boolean primary key default true check (singleton),
    policy_id text not null check (policy_id = 'free-pro-2026-10-15'),
    enabled boolean not null default true check (enabled),
    started_at timestamptz not null default now()
);
alter table private.ichart_free_access_policy enable row level security;
revoke all on table private.ichart_free_access_policy from public, anon, authenticated, service_role;
grant select on table private.ichart_free_access_policy to service_role;
insert into private.ichart_free_access_policy(singleton, policy_id, enabled)
values (true, 'free-pro-2026-10-15', true);

create function private.free_pro_access_enabled()
returns boolean language sql stable security definer set search_path = ''
as $$
    select exists (select 1 from private.ichart_free_access_policy
        where singleton and enabled and policy_id = 'free-pro-2026-10-15');
$$;
revoke all on function private.free_pro_access_enabled() from public, anon, authenticated;
grant execute on function private.free_pro_access_enabled() to service_role;

-- No caller-supplied owner, user_metadata or paid receipt is accepted. Check the
-- live account so a deleted/banned/anonymous account cannot use an old JWT to
-- gain feature access. The original email/phone verification requirement stays.
create function public.current_user_has_free_pro_access()
returns boolean language sql stable security definer set search_path = ''
as $$
    select private.free_pro_access_enabled() and exists (
        select 1 from auth.users users
        where users.id = (select auth.uid())
            and users.deleted_at is null
            and users.is_anonymous is not true
            and (users.banned_until is null or users.banned_until <= now())
            and (users.email_confirmed_at is not null or users.phone_confirmed_at is not null)
    );
$$;
revoke all on function public.current_user_has_free_pro_access() from public, anon;
grant execute on function public.current_user_has_free_pro_access() to authenticated, service_role;

-- Legacy RLS entry point retained so ownership, moderation, PDF provenance and
-- quota predicates remain unchanged. A true result means feature ACCESS, not
-- that the account has an active paid StoreKit subscription.
create or replace function public.current_user_has_active_pro()
returns boolean language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from auth.users users
        where users.id = (select auth.uid())
            and users.deleted_at is null and users.is_anonymous is not true
            and (users.banned_until is null or users.banned_until <= now())
            and (users.email_confirmed_at is not null or users.phone_confirmed_at is not null)
    ) and (private.free_pro_access_enabled() or exists (
        select 1 from public.subscriptions
        where owner_id = (select auth.uid())
            and plan = 'studioSubscription' and status = 'active'
            and (entitlement_expires_at is null or entitlement_expires_at > now())
            and revoked_at is null
    ));
$$;
revoke all on function public.current_user_has_active_pro() from public, anon;
grant execute on function public.current_user_has_active_pro() to authenticated, service_role;

-- Preserve the original paid implementation for a FUTURE reviewed migration,
-- but remove all public/service invocation paths to this destructive code.
alter function private.run_subscription_retention_jobs(timestamptz)
    rename to run_subscription_retention_jobs_paid_parked;
revoke all on function private.run_subscription_retention_jobs_paid_parked(timestamptz)
    from public, anon, authenticated, service_role;

alter table private.subscription_retention_events
    add column suppressed_at timestamptz,
    add column suppression_reason text;

update private.subscription_retention_events
set suppressed_at = now(), suppression_reason = 'free-pro-2026-10-15'
where sent_at is null and suppressed_at is null;

create function private.run_subscription_retention_jobs(run_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
    if not private.free_pro_access_enabled() then
        raise exception 'Free-access policy missing; an explicit retention transition is required';
    end if;
    update private.subscription_retention_events
    set suppressed_at = now(), suppression_reason = 'free-pro-2026-10-15'
    where sent_at is null and suppressed_at is null;
    return jsonb_build_object('expiration_warning_events', 0,
        'expiration_warning_rows_marked', 0, 'cloud_deleted_events', 0,
        'retention_status', 'paused_free_access', 'policy_id', 'free-pro-2026-10-15',
        'ran_at', run_at);
end;
$$;
revoke all on function private.run_subscription_retention_jobs(timestamptz)
    from public, anon, authenticated;
grant execute on function private.run_subscription_retention_jobs(timestamptz) to service_role;

-- Rebind explicitly to the guarded implementation after the original rename.
create or replace function public.run_subscription_retention_jobs(run_at timestamptz default now())
returns jsonb language sql security definer set search_path = ''
as $$ select private.run_subscription_retention_jobs(run_at); $$;
revoke all on function public.run_subscription_retention_jobs(timestamptz)
    from public, anon, authenticated;
grant execute on function public.run_subscription_retention_jobs(timestamptz) to service_role;

alter function public.claim_subscription_retention_events(integer)
    rename to claim_subscription_retention_events_paid_parked;
-- Move the parked public function into the non-exposed schema as well.
alter function public.claim_subscription_retention_events_paid_parked(integer) set schema private;
revoke all on function private.claim_subscription_retention_events_paid_parked(integer)
    from public, anon, authenticated, service_role;

create function public.claim_subscription_retention_events(batch_limit integer default 25)
returns table (id uuid, recipient_email text, subject text, body text)
language plpgsql security definer set search_path = ''
as $$
begin
    if not private.free_pro_access_enabled() then
        raise exception 'Free-access policy missing; an explicit email transition is required';
    end if;
    update private.subscription_retention_events
    set suppressed_at = now(), suppression_reason = 'free-pro-2026-10-15'
    where sent_at is null and suppressed_at is null;
    -- Intentionally no claims and no sent_at/dispatch-attempt changes. These
    -- notices describe access loss that does not happen during free access.
    return;
end;
$$;
revoke all on function public.claim_subscription_retention_events(integer)
    from public, anon, authenticated;
grant execute on function public.claim_subscription_retention_events(integer) to service_role;
