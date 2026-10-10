-- Only server-verified Apple evidence may consume a campaign. Issuing a
-- signature reserves a product; it does not establish an entitlement or a
-- redeemed benefit. No signature, signing key, or bearer token is persisted.
create table public.storekit_complimentary_campaign_accounts (
    campaign_id text not null check (campaign_id ~ '^[A-Za-z0-9._-]{1,128}$'),
    environment text not null check (environment in ('sandbox', 'production')),
    owner_id uuid not null references auth.users(id) on delete cascade,
    state text not null check (state in ('prepared', 'scheduled', 'redeemed')),
    product_id text not null check (product_id in ('com.ichart.app.pro.monthly', 'com.ichart.app.pro.annual')),
    current_attempt_id uuid,
    reservation_expires_at timestamptz,
    original_transaction_id text check (original_transaction_id ~ '^[0-9]+$'),
    transaction_id text check (transaction_id ~ '^[0-9]+$'),
    access_starts_at timestamptz,
    access_ends_at timestamptz,
    benefit_recorded_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (campaign_id, environment, owner_id),
    check ((state = 'prepared' and benefit_recorded_at is null)
        or (state in ('scheduled', 'redeemed') and original_transaction_id is not null
            and environment is not null and benefit_recorded_at is not null)),
    check (access_ends_at is null or access_starts_at is null or access_ends_at > access_starts_at)
);

create unique index storekit_complimentary_campaign_original_owner_idx
    on public.storekit_complimentary_campaign_accounts(campaign_id, environment, original_transaction_id)
    where original_transaction_id is not null;

-- The campaign-first primary key does not cover auth.users deletion by owner.
create index storekit_complimentary_campaign_accounts_owner_idx
    on public.storekit_complimentary_campaign_accounts(owner_id);

create table public.storekit_complimentary_campaign_attempts (
    campaign_id text not null,
    environment text not null check (environment in ('sandbox', 'production')),
    owner_id uuid not null,
    attempt_id uuid not null,
    product_id text not null check (product_id in ('com.ichart.app.pro.monthly', 'com.ichart.app.pro.annual')),
    offer_id text check (offer_id ~ '^[A-Za-z0-9._-]{1,128}$'),
    decision text not null check (decision in ('introductory', 'promotional', 'scheduledPromotional')),
    nonce uuid not null unique,
    signature_timestamp bigint not null check (signature_timestamp > 0),
    signature_expires_at timestamptz not null,
    created_at timestamptz not null default now(),
    primary key (campaign_id, environment, owner_id, attempt_id),
    foreign key (campaign_id, environment, owner_id)
        references public.storekit_complimentary_campaign_accounts(campaign_id, environment, owner_id) on delete cascade,
    check (decision = 'introductory' or offer_id is not null)
);

alter table public.storekit_complimentary_campaign_accounts enable row level security;
alter table public.storekit_complimentary_campaign_attempts enable row level security;
revoke all on table public.storekit_complimentary_campaign_accounts from public, anon, authenticated;
revoke all on table public.storekit_complimentary_campaign_attempts from public, anon, authenticated;
grant select, insert, update on table public.storekit_complimentary_campaign_accounts to service_role;
grant select, insert on table public.storekit_complimentary_campaign_attempts to service_role;

create function public.reserve_storekit_complimentary_campaign_attempt(
    p_owner_id uuid, p_campaign_id text, p_environment text, p_attempt_id uuid, p_previous_attempt_id uuid,
    p_product_id text, p_offer_id text, p_decision text, p_nonce uuid,
    p_timestamp bigint, p_now timestamptz
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
    account public.storekit_complimentary_campaign_accounts%rowtype;
    attempt public.storekit_complimentary_campaign_attempts%rowtype;
    expires_at timestamptz;
begin
    if p_owner_id is null or p_attempt_id is null or p_nonce is null or p_now is null
        or p_campaign_id is null or p_campaign_id !~ '^[A-Za-z0-9._-]{1,128}$'
        or p_environment is null or p_environment not in ('sandbox', 'production')
        or p_product_id is null or p_product_id not in ('com.ichart.app.pro.monthly', 'com.ichart.app.pro.annual')
        or p_decision is null or p_decision not in ('introductory', 'promotional', 'scheduledPromotional')
        or (p_offer_id is not null and p_offer_id !~ '^[A-Za-z0-9._-]{1,128}$')
        or (p_decision <> 'introductory' and p_offer_id is null)
        or p_timestamp is null or p_timestamp <= 0 then
        return jsonb_build_object('ok', false, 'reason', 'invalid_attempt');
    end if;
    expires_at := to_timestamp(p_timestamp::double precision / 1000) + interval '24 hours';
    if abs(extract(epoch from (to_timestamp(p_timestamp::double precision / 1000) - p_now))) > 300 then
        return jsonb_build_object('ok', false, 'reason', 'invalid_attempt_time');
    end if;

    insert into public.storekit_complimentary_campaign_accounts(campaign_id, environment, owner_id, state, product_id, created_at, updated_at)
        values (p_campaign_id, p_environment, p_owner_id, 'prepared', p_product_id, p_now, p_now)
        on conflict (campaign_id, environment, owner_id) do nothing;
    select * into account from public.storekit_complimentary_campaign_accounts
        where campaign_id = p_campaign_id and environment = p_environment and owner_id = p_owner_id for update;
    if account.state <> 'prepared' then
        return jsonb_build_object('ok', false, 'reason', 'campaign_already_consumed');
    end if;

    select * into attempt from public.storekit_complimentary_campaign_attempts
        where campaign_id = p_campaign_id and environment = p_environment and owner_id = p_owner_id and attempt_id = p_attempt_id;
    if found then
        if account.current_attempt_id is distinct from p_attempt_id then
            return jsonb_build_object('ok', false, 'reason', 'attempt_retired');
        end if;
        if attempt.product_id is distinct from p_product_id or attempt.offer_id is distinct from p_offer_id
            or attempt.decision is distinct from p_decision then
            return jsonb_build_object('ok', false, 'reason', 'attempt_mismatch');
        end if;
        if attempt.signature_expires_at <= p_now then
            return jsonb_build_object('ok', false, 'reason', 'attempt_expired');
        end if;
    else
        if account.current_attempt_id is distinct from p_previous_attempt_id then
            return jsonb_build_object('ok', false, 'reason', 'attempt_conflict');
        end if;
        if account.product_id <> p_product_id and account.reservation_expires_at > p_now then
            return jsonb_build_object('ok', false, 'reason', 'another_product_reserved');
        end if;
        insert into public.storekit_complimentary_campaign_attempts(
            campaign_id, environment, owner_id, attempt_id, product_id, offer_id, decision, nonce,
            signature_timestamp, signature_expires_at, created_at
        ) values (p_campaign_id, p_environment, p_owner_id, p_attempt_id, p_product_id, p_offer_id, p_decision,
            p_nonce, p_timestamp, expires_at, p_now) returning * into attempt;
        update public.storekit_complimentary_campaign_accounts
            set current_attempt_id = p_attempt_id, product_id = p_product_id,
                reservation_expires_at = greatest(reservation_expires_at, expires_at), updated_at = p_now
            where campaign_id = p_campaign_id and environment = p_environment and owner_id = p_owner_id;
    end if;
    return jsonb_build_object('ok', true, 'attempt', jsonb_build_object(
        'attemptID', attempt.attempt_id, 'productID', attempt.product_id, 'offerID', attempt.offer_id,
        'decision', attempt.decision, 'nonce', attempt.nonce, 'timestamp', attempt.signature_timestamp));
end;
$$;

create function public.record_storekit_complimentary_campaign_benefit(
    p_owner_id uuid, p_campaign_id text, p_attempt_id uuid, p_product_id text,
    p_original_transaction_id text, p_transaction_id text, p_environment text, p_state text,
    p_access_starts_at timestamptz, p_access_ends_at timestamptz, p_now timestamptz
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
    account public.storekit_complimentary_campaign_accounts%rowtype;
begin
    if p_owner_id is null or p_now is null or p_campaign_id is null or p_campaign_id !~ '^[A-Za-z0-9._-]{1,128}$'
        or p_product_id is null or p_product_id not in ('com.ichart.app.pro.monthly', 'com.ichart.app.pro.annual')
        or p_original_transaction_id is null or p_original_transaction_id !~ '^[0-9]+$'
        or (p_transaction_id is not null and p_transaction_id !~ '^[0-9]+$')
        or p_environment is null or p_environment not in ('sandbox', 'production')
        or p_state is null or p_state not in ('scheduled', 'redeemed')
        or (p_access_starts_at is not null and p_access_ends_at is not null and p_access_ends_at <= p_access_starts_at) then
        return jsonb_build_object('ok', false, 'reason', 'invalid_benefit');
    end if;
    insert into public.storekit_complimentary_campaign_accounts(campaign_id, environment, owner_id, state, product_id, created_at, updated_at)
        values (p_campaign_id, p_environment, p_owner_id, 'prepared', p_product_id, p_now, p_now)
        on conflict (campaign_id, environment, owner_id) do nothing;
    select * into account from public.storekit_complimentary_campaign_accounts
        where campaign_id = p_campaign_id and environment = p_environment and owner_id = p_owner_id for update;

    if p_attempt_id is not null and account.current_attempt_id is distinct from p_attempt_id then
        return jsonb_build_object('ok', false, 'reason', 'attempt_retired');
    end if;
    if p_attempt_id is not null and not exists (
        select 1 from public.storekit_complimentary_campaign_attempts where campaign_id = p_campaign_id
            and environment = p_environment and owner_id = p_owner_id and attempt_id = p_attempt_id and product_id = p_product_id
    ) then
        return jsonb_build_object('ok', false, 'reason', 'unknown_attempt');
    end if;
    if account.state <> 'prepared' and (account.product_id <> p_product_id
        or account.original_transaction_id <> p_original_transaction_id or account.environment <> p_environment) then
        return jsonb_build_object('ok', false, 'reason', 'campaign_already_consumed');
    end if;
    -- A recorded actual gift is permanent. Do not replace it with a later
    -- transaction or extend its dates. A pending gift may become actual below.
    if account.state = 'redeemed' then
        if account.transaction_id is distinct from p_transaction_id then
            return jsonb_build_object('ok', false, 'reason', 'campaign_already_consumed');
        end if;
        return jsonb_build_object('ok', true);
    end if;
    update public.storekit_complimentary_campaign_accounts
        set state = case when account.state = 'redeemed' then 'redeemed' else p_state end,
            product_id = p_product_id, original_transaction_id = p_original_transaction_id,
            transaction_id = coalesce(p_transaction_id, transaction_id), environment = p_environment,
            access_starts_at = coalesce(p_access_starts_at, access_starts_at),
            access_ends_at = coalesce(p_access_ends_at, access_ends_at),
            benefit_recorded_at = coalesce(benefit_recorded_at, p_now), updated_at = p_now
        where campaign_id = p_campaign_id and environment = p_environment and owner_id = p_owner_id;
    return jsonb_build_object('ok', true);
exception when unique_violation then
    return jsonb_build_object('ok', false, 'reason', 'original_transaction_owner_conflict');
end;
$$;

revoke all on function public.reserve_storekit_complimentary_campaign_attempt(uuid, text, text, uuid, uuid, text, text, text, uuid, bigint, timestamptz)
    from public, anon, authenticated;
revoke all on function public.record_storekit_complimentary_campaign_benefit(uuid, text, uuid, text, text, text, text, text, timestamptz, timestamptz, timestamptz)
    from public, anon, authenticated;
grant execute on function public.reserve_storekit_complimentary_campaign_attempt(uuid, text, text, uuid, uuid, text, text, text, uuid, bigint, timestamptz)
    to service_role;
grant execute on function public.record_storekit_complimentary_campaign_benefit(uuid, text, uuid, text, text, text, text, text, timestamptz, timestamptz, timestamptz)
    to service_role;
