-- Additive preparation only. Installing this migration does not activate paid
-- plans, rewrite Apple billing/membership, change notice copy or resume retention.
-- The existing protected singleton remains the sole phase authority.
do $$
begin
    if not private.free_pro_access_enabled() or not exists (
        select 1 from private.ichart_paid_feature_policy where singleton and not enabled
    ) then
        raise exception 'Coordinated activation preparation requires the existing free-beta phase'
            using errcode = '55000';
    end if;
end;
$$;

alter table private.ichart_paid_feature_policy
    add column policy_revision bigint not null default 1 check (policy_revision >= 1),
    add column policy_updated_at timestamptz not null default clock_timestamp();

-- Every real phase change, including a privileged direct UPDATE and rollback,
-- advances the same revision. No-op writes cannot invent a revision or timestamp.
-- Refuse reseeding/deletion/truncation: a replaced singleton must not reset caches
-- to revision 1 after clients have already observed a higher generation.
create function private.guard_product_access_policy_revision()
returns trigger language plpgsql set search_path = ''
as $$
begin
    if tg_op <> 'UPDATE' then
        raise exception 'The product-access singleton cannot be replaced or removed'
            using errcode = '55000';
    end if;
    if new.singleton is distinct from old.singleton
        or new.policy_revision is distinct from old.policy_revision
        or new.policy_updated_at is distinct from old.policy_updated_at then
        raise exception 'Product-access revision and timestamp are server managed'
            using errcode = '22023';
    end if;
    if new.enabled is distinct from old.enabled then
        if old.policy_revision = 9223372036854775807 then
            raise exception 'Product-access revision exhausted' using errcode = '22003';
        end if;
        new.policy_revision := old.policy_revision + 1;
        new.policy_updated_at := greatest(clock_timestamp(), old.policy_updated_at);
    else
        new.policy_revision := old.policy_revision;
        new.policy_updated_at := old.policy_updated_at;
    end if;
    return new;
end;
$$;
revoke all on function private.guard_product_access_policy_revision()
    from public, anon, authenticated, service_role;
create trigger product_access_policy_revision_guard
    before insert or update or delete on private.ichart_paid_feature_policy
    for each row execute function private.guard_product_access_policy_revision();
create trigger product_access_policy_truncate_guard
    before truncate on private.ichart_paid_feature_policy
    for each statement execute function private.guard_product_access_policy_revision();

-- Service-only compare-and-set. It locks only the singleton; never acquire an
-- account/subscription lock here (publication and membership lock account first).
-- PT409 is a deterministic stale administrative generation, not a retryable
-- PostgreSQL serialization failure. Equal phase + expected revision is a no-op.
create function private.set_product_access_phase(p_expected_revision bigint, p_paid_enabled boolean)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare policy private.ichart_paid_feature_policy%rowtype;
begin
    if p_expected_revision is null or p_expected_revision < 1 or p_paid_enabled is null then
        raise exception 'An expected revision and explicit paid phase are required' using errcode = '22023';
    end if;
    select * into policy from private.ichart_paid_feature_policy where singleton for update;
    if not found or not private.free_pro_access_enabled() then
        raise exception 'Product-access policy is unavailable' using errcode = '55000';
    end if;
    if policy.policy_revision <> p_expected_revision then
        raise exception 'Product-access policy revision changed' using errcode = 'PT409';
    end if;
    if policy.enabled is distinct from p_paid_enabled then
        update private.ichart_paid_feature_policy set enabled = p_paid_enabled
        where singleton returning * into policy;
    end if;
    return jsonb_build_object('schema_version', 1, 'policy_id', 'ichart-product-access-v1',
        'phase', case when policy.enabled then 'paid' else 'free_beta' end,
        'policy_revision', policy.policy_revision, 'policy_updated_at', policy.policy_updated_at,
        'server_now', clock_timestamp());
end;
$$;
revoke all on function private.set_product_access_phase(bigint, boolean)
    from public, anon, authenticated, service_role;
grant execute on function private.set_product_access_phase(bigint, boolean) to service_role;
create function public.set_product_access_phase(p_expected_revision bigint, p_paid_enabled boolean)
returns jsonb language sql security invoker set search_path = ''
begin atomic
    select private.set_product_access_phase(p_expected_revision, p_paid_enabled);
end;
revoke all on function public.set_product_access_phase(bigint, boolean)
    from public, anon, authenticated, service_role;
grant execute on function public.set_product_access_phase(bigint, boolean) to service_role;

-- This helper is only the strict, independently verified paid predicate. Legacy
-- compatibility JSON below must never become RLS, billing or service authority.
create function private.current_user_has_verified_paid_pro()
returns boolean language sql stable security definer set search_path = ''
as $$
    select private.free_pro_beta_account_eligible() and exists (
        select 1 from public.subscriptions subscription
        where subscription.owner_id = (select auth.uid())
            and subscription.provider = 'storekit'
            and subscription.plan = 'studioSubscription' and subscription.status = 'active'
            and subscription.app_store_status = 'active'
            and subscription.entitlement_expires_at > now()
            and subscription.revoked_at is null and subscription.last_verified_at is not null
    );
$$;
revoke all on function private.current_user_has_verified_paid_pro()
    from public, anon, authenticated, service_role;

-- Derive a coherent phase/revision from one captured policy row. STABLE reads
-- use one statement snapshot; no timestamp, client header, receipt or membership
-- can select the global phase. Existing current accounts can receive eligible
-- false so revocation is an explicit no-access response rather than an offline
-- error. Missing Auth identities cannot request another owner's status.
create function private.build_product_access_status()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
    caller uuid := auth.uid();
    policy private.ichart_paid_feature_policy%rowtype;
    beta_policy private.ichart_free_access_policy%rowtype;
    account_eligible boolean;
    recorded_participating boolean;
    available boolean;
begin
    if caller is null or not exists (select 1 from auth.users users where users.id = caller) then
        raise exception 'A current signed-in account is required' using errcode = '42501';
    end if;
    select * into policy from private.ichart_paid_feature_policy where singleton;
    if not found or not private.free_pro_access_enabled() then
        raise exception 'Product-access policy is unavailable' using errcode = '55000';
    end if;
    select * into beta_policy from private.ichart_free_access_policy where singleton;
    account_eligible := private.free_pro_beta_account_eligible();
    recorded_participating := coalesce((select membership.participating
        from private.free_pro_beta_memberships membership where membership.owner_id = caller), true);
    available := not policy.enabled;
    return jsonb_build_object('schema_version', 1, 'owner_id', caller,
        'policy_id', 'ichart-product-access-v1',
        'phase', case when policy.enabled then 'paid' else 'free_beta' end,
        'policy_revision', policy.policy_revision, 'server_now', clock_timestamp(),
        'policy_updated_at', policy.policy_updated_at,
        'beta_available', available, 'eligible', account_eligible,
        'participating', recorded_participating,
        'free_pro_access', available and account_eligible and recorded_participating,
        'notice_id', beta_policy.beta_notice_id, 'notice_title', beta_policy.beta_notice_title,
        'notice_body', beta_policy.beta_notice_body, 'beta_ending_at', beta_policy.beta_ending_at);
end;
$$;
revoke all on function private.build_product_access_status()
    from public, anon, authenticated, service_role;
create function public.product_access_status()
returns jsonb language sql stable security definer set search_path = ''
as $$ select private.build_product_access_status(); $$;
revoke all on function public.product_access_status() from public, anon, authenticated, service_role;
grant execute on function public.product_access_status() to authenticated;

-- Old clients require free_pro_access == beta_available && eligible &&
-- participating and ignore new phase fields. In the paid phase ONLY a genuine
-- verified paid owner receives this intentionally bounded local-feature
-- projection. It leaves stored membership and all Apple fields unchanged. It
-- cannot rename old Pro-Free UI, add checkout or enable compile-gated services.
create or replace function public.free_pro_beta_status()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
    truthful jsonb := private.build_product_access_status();
    legacy jsonb;
    revision text := truthful->>'policy_revision';
begin
    legacy := jsonb_build_object('owner_id', truthful->'owner_id',
        'policy_id', (select policy_id from private.ichart_free_access_policy where singleton),
        'beta_available', truthful->'beta_available', 'eligible', truthful->'eligible',
        'participating', truthful->'participating', 'free_pro_access', truthful->'free_pro_access',
        'notice_id', truthful->'notice_id', 'notice_title', truthful->'notice_title',
        'notice_body', truthful->'notice_body', 'beta_ending_at', truthful->'beta_ending_at');
    if truthful->>'phase' = 'paid' then
        legacy := legacy || jsonb_build_object(
            'recorded_participating', truthful->'participating',
            'notice_id', 'legacy-paid-update-v1-' || revision,
            'notice_title', 'Update iChart for current plan settings',
            'notice_body', 'The free Pro phase has ended. Update iChart to view current plan information and paid subscription controls. Basic keeps your saved charts and ink, PDFs and local setlists available. This does not create, renew or cancel an Apple subscription.');
        if private.current_user_has_verified_paid_pro() then
            legacy := legacy || jsonb_build_object('policy_id', 'legacy-paid-access-compat-v1',
                'beta_available', true, 'eligible', true, 'participating', true, 'free_pro_access', true,
                'access_reason', 'verified_paid_legacy_compat',
                'notice_body', 'Your paid Pro access is active. Your existing Apple subscription stays active and is managed with Apple; this update does not convert it to free access or cancel it. Update iChart to see current plan information and subscription controls. This older version may still label access as free. Your saved charts and ink, PDFs and local setlists remain available.');
        end if;
    end if;
    return legacy;
end;
$$;
revoke all on function public.free_pro_beta_status() from public, anon, authenticated, service_role;
grant execute on function public.free_pro_beta_status() to authenticated;

-- Preserve normal beta membership semantics and the account -> policy lock
-- order. Both directions reject before any write during paid phase: an old
-- projected client cannot accidentally change recorded enrollment on a failed
-- response-confirmation path. Future rollback restores the unchanged choice.
create or replace function public.set_free_pro_beta_participation(p_participating boolean, p_expected_owner_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare caller uuid := auth.uid(); paid boolean;
begin
    if p_participating is null then
        raise exception 'Participation choice is required' using errcode = '22004';
    end if;
    if caller is null or p_expected_owner_id is null or caller <> p_expected_owner_id then
        raise exception 'A verified eligible signed-in account is required' using errcode = '42501';
    end if;
    perform 1 from auth.users where id = caller for update;
    if not found or not private.free_pro_beta_account_eligible() then
        raise exception 'A verified eligible signed-in account is required' using errcode = '42501';
    end if;
    select enabled into paid from private.ichart_paid_feature_policy where singleton for share;
    if not found or paid or not private.free_pro_access_enabled() then
        raise exception 'The free access phase is not available; update iChart for current plan settings'
            using errcode = '55000';
    end if;
    insert into private.free_pro_beta_memberships(owner_id, participating, updated_at)
    values (caller, p_participating, now())
    on conflict (owner_id) do update set participating = excluded.participating, updated_at = excluded.updated_at;
    return public.free_pro_beta_status();
end;
$$;
revoke all on function public.set_free_pro_beta_participation(boolean, uuid)
    from public, anon, authenticated, service_role;
grant execute on function public.set_free_pro_beta_participation(boolean, uuid) to authenticated;
