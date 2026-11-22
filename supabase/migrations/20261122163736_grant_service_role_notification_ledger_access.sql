-- The SECURITY INVOKER StoreKit authority RPC writes the replay ledger only
-- for mapped notifications. Fresh databases need these service-role grants.
grant insert (notification_uuid, original_transaction_id, signed_at)
    on table public.app_store_notification_events to service_role;

-- ON CONFLICT (notification_uuid) DO NOTHING also reads its conflict target.
-- Other ledger columns and client privileges are intentionally unchanged.
grant select (notification_uuid)
    on table public.app_store_notification_events to service_role;
