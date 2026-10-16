-- Beta participation is an account choice, not paid billing or research/telemetry
-- consent. Missing membership means default Pro. Leaving/rejoining never edits
-- Apple subscription truth or deletes charts. The GLOBAL retention pause from
-- free_pro_access remains unchanged even for an account choosing Basic.
create table private.free_pro_beta_memberships (
    owner_id uuid primary key references auth.users(id) on delete cascade,
    participating boolean not null,
    updated_at timestamptz not null default now()
);
alter table private.free_pro_beta_memberships enable row level security;
revoke all on table private.free_pro_beta_memberships from public, anon, authenticated, service_role;
grant select on table private.free_pro_beta_memberships to service_role;

-- Reserved for a separately approved administrative notice. Defaults publish no
-- notice/date. A date is INFORMATION ONLY: no timer ends access, starts charging,
-- reactivates subscriptions, dispatches mail or resumes destructive retention.
alter table private.ichart_free_access_policy
    add column beta_notice_id text,
    add column beta_notice_title text,
    add column beta_notice_body text,
    add column beta_ending_at timestamptz,
    add constraint free_pro_beta_notice_complete_and_bounded check (
        (beta_notice_id is null and beta_notice_title is null and beta_notice_body is null and beta_ending_at is null)
        or (beta_notice_id is not null and beta_notice_title is not null and beta_notice_body is not null
            and beta_notice_id ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$'
            and length(btrim(beta_notice_title)) between 1 and 120
            and length(btrim(beta_notice_body)) between 1 and 2000
            and (beta_ending_at is null or isfinite(beta_ending_at)))
    );

create function private.free_pro_beta_account_eligible()
returns boolean language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from auth.users users where users.id = (select auth.uid())
            and users.deleted_at is null and users.is_anonymous is not true
            and (users.banned_until is null or users.banned_until <= now())
            and (users.email_confirmed_at is not null or users.phone_confirmed_at is not null)
    );
$$;
revoke all on function private.free_pro_beta_account_eligible()
    from public, anon, authenticated, service_role;

create or replace function public.current_user_has_free_pro_access()
returns boolean language sql stable security definer set search_path = ''
as $$
    select private.free_pro_access_enabled() and private.free_pro_beta_account_eligible()
        and coalesce((select membership.participating from private.free_pro_beta_memberships membership
            where membership.owner_id = (select auth.uid())), true);
$$;
revoke all on function public.current_user_has_free_pro_access() from public, anon;
grant execute on function public.current_user_has_free_pro_access() to authenticated, service_role;

create or replace function public.current_user_has_active_pro()
returns boolean language sql stable security definer set search_path = ''
as $$
    select private.free_pro_beta_account_eligible() and case
        -- During the free phase an explicit Basic choice wins even if Apple
        -- still has an active paid row. This does NOT cancel that subscription.
        when private.free_pro_access_enabled() then public.current_user_has_free_pro_access()
        -- Historical paid predicate is retained only for a future explicit
        -- product transition; the current global phase cannot time out.
        else exists (select 1 from public.subscriptions
            where owner_id = (select auth.uid()) and plan = 'studioSubscription' and status = 'active'
                and (entitlement_expires_at is null or entitlement_expires_at > now())
                and revoked_at is null)
        end;
$$;
revoke all on function public.current_user_has_active_pro() from public, anon;
grant execute on function public.current_user_has_active_pro() to authenticated, service_role;

create function public.free_pro_beta_status()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
    caller uuid := auth.uid();
    policy private.ichart_free_access_policy%rowtype;
    eligible boolean;
    participating boolean;
    available boolean;
begin
    if caller is null or not exists (select 1 from auth.users users where users.id = caller) then
        raise exception 'A current signed-in account is required' using errcode = '42501';
    end if;
    select * into policy from private.ichart_free_access_policy where singleton;
    eligible := private.free_pro_beta_account_eligible();
    available := private.free_pro_access_enabled();
    participating := coalesce((select membership.participating from private.free_pro_beta_memberships membership
        where membership.owner_id = caller), true);
    return jsonb_build_object('owner_id', caller,
        'policy_id', coalesce(policy.policy_id, 'free-pro-2026-10-15'),
        'beta_available', available, 'eligible', eligible, 'participating', participating,
        'free_pro_access', available and eligible and participating,
        'notice_id', policy.beta_notice_id, 'notice_title', policy.beta_notice_title,
        'notice_body', policy.beta_notice_body, 'beta_ending_at', policy.beta_ending_at);
end;
$$;
revoke all on function public.free_pro_beta_status() from public, anon, service_role;
grant execute on function public.free_pro_beta_status() to authenticated;

create function public.set_free_pro_beta_participation(p_participating boolean, p_expected_owner_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare caller uuid := auth.uid();
begin
    if p_participating is null then
        raise exception 'Participation choice is required' using errcode = '22004';
    end if;
    -- SDK session state may change after the UI starts this request. This UUID
    -- is a rejection guard, never authority: the actual owner remains auth.uid().
    if caller is null or p_expected_owner_id is null or caller <> p_expected_owner_id
        or not private.free_pro_beta_account_eligible() then
        raise exception 'A verified eligible signed-in account is required' using errcode = '42501';
    end if;
    if p_participating and not private.free_pro_access_enabled() then
        raise exception 'The free beta is not available' using errcode = '55000';
    end if;
    insert into private.free_pro_beta_memberships(owner_id, participating, updated_at)
    values (caller, p_participating, now())
    on conflict (owner_id) do update
        set participating = excluded.participating, updated_at = excluded.updated_at;
    return public.free_pro_beta_status();
end;
$$;
revoke all on function public.set_free_pro_beta_participation(boolean, uuid) from public, anon, service_role;
grant execute on function public.set_free_pro_beta_participation(boolean, uuid) to authenticated;
