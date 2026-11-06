-- Commit the Apple replay ledger and subscription authority together. All
-- verified claim/notification writers use the same original -> owner -> row
-- lock order, including when no subscription row exists yet.
create or replace function public.apply_storekit_subscription_authority(
    authority_update jsonb,
    claim_owner_id uuid default null
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog
as $$
declare
    original_id text;
    notification_id text;
    mapped_owner_id uuid;
    current_subscription public.subscriptions%rowtype;
    incoming_subscription public.subscriptions%rowtype;
    saved_subscription public.subscriptions%rowtype;
    has_original boolean;
    has_owner boolean;
    is_claim boolean := claim_owner_id is not null;
    incoming_signed_at timestamptz;
    existing_order_time timestamptz;
    incoming_order_time timestamptz;
    existing_transaction text;
    incoming_transaction text;
    is_stale boolean := false;
    patch jsonb;
    allowed_fields constant text[] := array[
        'provider', 'plan', 'status', 'storekit_product_id',
        'storekit_original_transaction_id', 'storekit_app_account_token',
        'storekit_environment', 'app_store_status', 'app_store_auto_renew_status',
        'app_store_notification_type', 'app_store_notification_uuid',
        'app_store_last_transaction_id', 'app_store_signed_at', 'current_period_end',
        'entitlement_expires_at', 'grace_period_expires_at', 'cloud_retention_deadline',
        'cloud_retention_deleted_at', 'expiration_warning_sent_at', 'revoked_at',
        'last_verified_at'
    ];
begin
    -- EXECUTE grants are the first boundary. Keep an independent effective-role
    -- check so future default-grant changes cannot expose billing mutations.
    if current_user <> 'service_role' then
        raise insufficient_privilege using message = 'Service role required.';
    end if;
    if authority_update is null or jsonb_typeof(authority_update) <> 'object' then
        raise invalid_parameter_value using message = 'Authority update must be an object.';
    end if;
    original_id := nullif(btrim(authority_update ->> 'storekit_original_transaction_id'), '');
    if original_id is null then
        return jsonb_build_object('stored', false, 'mapping_status', 'missing_original_transaction');
    end if;
    if exists (
        select 1 from jsonb_object_keys(authority_update) as fields(name)
        where not (fields.name = any(allowed_fields))
    ) then
        raise invalid_parameter_value using message = 'Unsupported authority field.';
    end if;
    patch := authority_update || jsonb_build_object('storekit_original_transaction_id', original_id);
    incoming_signed_at := (authority_update ->> 'app_store_signed_at')::timestamptz;
    notification_id := nullif(btrim(authority_update ->> 'app_store_notification_uuid'), '');

    -- Separate two-int namespaces keep original/owner hash collisions from
    -- reversing lock classes. Hash collisions within a class only serialize
    -- otherwise independent updates; they do not weaken ownership checks.
    perform pg_advisory_xact_lock(1497066561, hashtext(original_id));
    if is_claim then
        mapped_owner_id := claim_owner_id;
    else
        select subscriptions.owner_id into mapped_owner_id
        from public.subscriptions
        where subscriptions.storekit_original_transaction_id = original_id;
        if not found then
            return jsonb_build_object('stored', false, 'mapping_status', 'unmapped_original_transaction');
        end if;
    end if;
    perform pg_advisory_xact_lock(1497066562, hashtext(mapped_owner_id::text));

    select subscriptions.* into current_subscription
    from public.subscriptions
    where subscriptions.storekit_original_transaction_id = original_id
    for update;
    has_original := found;
    if is_claim and has_original and current_subscription.owner_id <> mapped_owner_id then
        return jsonb_build_object('stored', false, 'mapping_status', 'original_transaction_owner_conflict',
            'subscription', to_jsonb(current_subscription));
    end if;
    if not is_claim then
        if not has_original then
            -- While this notification waited for the owner lock, a verified
            -- claim may have moved that owner's row to a different original.
            return jsonb_build_object('stored', false, 'mapping_status', 'unmapped_original_transaction');
        end if;
        if current_subscription.owner_id <> mapped_owner_id then
            raise serialization_failure using message = 'Subscription mapping changed; retry.';
        end if;
    end if;

    has_owner := has_original;
    if is_claim and not has_original then
        select subscriptions.* into current_subscription
        from public.subscriptions
        where subscriptions.owner_id = mapped_owner_id
        for update;
        has_owner := found;
    end if;

    if not is_claim and notification_id is not null then
        insert into public.app_store_notification_events(notification_uuid, original_transaction_id, signed_at)
        values (notification_id, original_id, incoming_signed_at)
        on conflict (notification_uuid) do nothing;
        if not found then
            return jsonb_build_object('stored', false, 'mapping_status', 'duplicate_notification',
                'subscription', to_jsonb(current_subscription));
        end if;
    end if;

    -- Ordering is scoped to the original transaction. A newly claimed
    -- original retains the previous replacement semantics rather than being
    -- compared with an unrelated subscription's signed clock.
    if has_original and current_subscription.app_store_signed_at is not null then
        -- The previous JavaScript Date comparison had millisecond precision.
        -- Preserve that ordering for legacy PostgreSQL values with finer
        -- precision, without rewriting the timestamps stored in either table.
        existing_order_time := date_trunc('milliseconds', current_subscription.app_store_signed_at);
        incoming_order_time := date_trunc('milliseconds', incoming_signed_at);
        is_stale := incoming_order_time is null
            or incoming_order_time < existing_order_time;
        if incoming_order_time = existing_order_time then
            existing_transaction := btrim(current_subscription.app_store_last_transaction_id);
            incoming_transaction := btrim(authority_update ->> 'app_store_last_transaction_id');
            if existing_transaction ~ '^[0-9]+$' and incoming_transaction ~ '^[0-9]+$' then
                is_stale := incoming_transaction::numeric < existing_transaction::numeric;
            end if;
        end if;
    end if;
    if is_stale then
        -- Stale notification UUIDs remain acknowledged in the ledger, exactly
        -- as before. An update error below rolls this insert back as well.
        return jsonb_build_object('stored', false,
            'mapping_status', case when is_claim then 'stale_transaction_claim' else 'stale_notification' end,
            'subscription', to_jsonb(current_subscription));
    end if;

    if is_claim and has_owner and not has_original
        and coalesce(btrim(current_subscription.storekit_original_transaction_id), '') <> original_id
        and btrim(authority_update ->> 'provider') = 'storekit'
        and btrim(authority_update ->> 'status') = 'active' then
        patch := patch || jsonb_build_object('app_store_auto_renew_status', null);
    end if;
    if not has_owner then
        -- These are the existing table defaults. Populate before merging so
        -- an explicit JSON null still fails a NOT NULL constraint, whereas an
        -- omitted field retains its old default/presence semantics.
        current_subscription.provider := 'none';
        current_subscription.plan := 'free';
        current_subscription.status := 'inactive';
    end if;
    incoming_subscription := jsonb_populate_record(current_subscription, patch);
    if has_owner then
        update public.subscriptions set
            provider = incoming_subscription.provider,
            plan = incoming_subscription.plan,
            status = incoming_subscription.status,
            storekit_product_id = incoming_subscription.storekit_product_id,
            storekit_original_transaction_id = incoming_subscription.storekit_original_transaction_id,
            storekit_app_account_token = incoming_subscription.storekit_app_account_token,
            storekit_environment = incoming_subscription.storekit_environment,
            app_store_status = incoming_subscription.app_store_status,
            app_store_auto_renew_status = incoming_subscription.app_store_auto_renew_status,
            app_store_notification_type = incoming_subscription.app_store_notification_type,
            app_store_notification_uuid = incoming_subscription.app_store_notification_uuid,
            app_store_last_transaction_id = incoming_subscription.app_store_last_transaction_id,
            app_store_signed_at = incoming_subscription.app_store_signed_at,
            current_period_end = incoming_subscription.current_period_end,
            entitlement_expires_at = incoming_subscription.entitlement_expires_at,
            grace_period_expires_at = incoming_subscription.grace_period_expires_at,
            cloud_retention_deadline = incoming_subscription.cloud_retention_deadline,
            cloud_retention_deleted_at = incoming_subscription.cloud_retention_deleted_at,
            expiration_warning_sent_at = incoming_subscription.expiration_warning_sent_at,
            revoked_at = incoming_subscription.revoked_at,
            last_verified_at = incoming_subscription.last_verified_at
        where subscriptions.id = current_subscription.id
        returning subscriptions.* into saved_subscription;
    else
        insert into public.subscriptions(
            owner_id, provider, plan, status, storekit_product_id,
            storekit_original_transaction_id, storekit_app_account_token, storekit_environment,
            app_store_status, app_store_auto_renew_status, app_store_notification_type,
            app_store_notification_uuid, app_store_last_transaction_id, app_store_signed_at,
            current_period_end, entitlement_expires_at, grace_period_expires_at,
            cloud_retention_deadline, cloud_retention_deleted_at, expiration_warning_sent_at,
            revoked_at, last_verified_at
        ) values (
            mapped_owner_id, incoming_subscription.provider, incoming_subscription.plan, incoming_subscription.status,
            incoming_subscription.storekit_product_id, incoming_subscription.storekit_original_transaction_id,
            incoming_subscription.storekit_app_account_token, incoming_subscription.storekit_environment,
            incoming_subscription.app_store_status, incoming_subscription.app_store_auto_renew_status,
            incoming_subscription.app_store_notification_type, incoming_subscription.app_store_notification_uuid,
            incoming_subscription.app_store_last_transaction_id, incoming_subscription.app_store_signed_at,
            incoming_subscription.current_period_end, incoming_subscription.entitlement_expires_at,
            incoming_subscription.grace_period_expires_at, incoming_subscription.cloud_retention_deadline,
            incoming_subscription.cloud_retention_deleted_at, incoming_subscription.expiration_warning_sent_at,
            incoming_subscription.revoked_at, incoming_subscription.last_verified_at
        ) returning subscriptions.* into saved_subscription;
    end if;
    return jsonb_build_object('stored', true,
        'mapping_status', case when is_claim then 'claimed' else 'updated' end,
        'subscription', to_jsonb(saved_subscription));
end;
$$;

revoke all on function public.apply_storekit_subscription_authority(jsonb, uuid)
    from public, anon, authenticated;
grant execute on function public.apply_storekit_subscription_authority(jsonb, uuid)
    to service_role;
