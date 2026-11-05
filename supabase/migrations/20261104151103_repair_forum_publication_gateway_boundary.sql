-- The consent ledger deliberately removed service_role's blanket private-schema
-- USAGE. Keep that boundary: the Edge service receives one narrow public entry
-- point, rather than access to every private schema object.
create or replace function public.publish_forum_chart_post(
    target_post_id uuid,
    target_owner_id uuid,
    target_byte_size bigint,
    target_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
    -- PostgREST sets the database role from the verified service JWT. Check
    -- that protected role setting, not a user-editable metadata claim. The
    -- session_user branch also supports a direct service_role SQL session.
    if current_setting('role', true) is distinct from 'service_role'
        and session_user is distinct from 'service_role' then
        raise exception 'Forum publication requires the service role'
            using errcode = '42501';
    end if;

    -- The existing private operation still locks and checks the real owner,
    -- eligibility, pending status, object path and PDF provenance atomically.
    return private.publish_forum_chart_post(
        target_post_id, target_owner_id, target_byte_size, target_sha256
    );
end;
$$;

revoke all on function public.publish_forum_chart_post(uuid, uuid, bigint, text)
    from public, anon, authenticated, service_role;
grant execute on function public.publish_forum_chart_post(uuid, uuid, bigint, text)
    to service_role;

comment on function public.publish_forum_chart_post(uuid, uuid, bigint, text) is
    'Service-only publication boundary; preserves the private-schema USAGE restriction and existing atomic owner/provenance checks.';
