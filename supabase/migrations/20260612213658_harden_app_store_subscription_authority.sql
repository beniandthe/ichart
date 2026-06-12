alter table public.subscriptions
    add column provider text not null default 'none',
    add column storekit_product_id text,
    add column storekit_original_transaction_id text,
    add column storekit_environment text,
    add column app_store_status text,
    add column app_store_notification_type text,
    add column app_store_last_transaction_id text,
    add column entitlement_expires_at timestamptz,
    add column grace_period_expires_at timestamptz,
    add column revoked_at timestamptz,
    add column last_verified_at timestamptz;

alter table public.subscriptions
    add constraint subscriptions_provider_check
    check (provider in ('none', 'storekit', 'stripe', 'manual')),
    add constraint subscriptions_storekit_environment_check
    check (storekit_environment is null or storekit_environment in ('sandbox', 'production')),
    add constraint subscriptions_app_store_status_check
    check (
        app_store_status is null
        or app_store_status in (
            'active',
            'grace',
            'billing_retry',
            'expired',
            'revoked',
            'refunded'
        )
    );

create unique index subscriptions_storekit_original_transaction_id_idx
    on public.subscriptions(storekit_original_transaction_id)
    where storekit_original_transaction_id is not null;

create index subscriptions_provider_status_idx
    on public.subscriptions(provider, app_store_status)
    where provider <> 'none';

create index subscriptions_last_verified_at_idx
    on public.subscriptions(last_verified_at desc)
    where last_verified_at is not null;
