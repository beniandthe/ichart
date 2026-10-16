-- Serialize publication with voluntary access changes and Auth account updates.
-- A missing membership still means Pro; the account row is the mutex even when
-- there is no membership row to lock. No enrollment or billing row is created.
create or replace function public.set_free_pro_beta_participation(p_participating boolean, p_expected_owner_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare caller uuid := auth.uid();
begin
    if p_participating is null then
        raise exception 'Participation choice is required' using errcode = '22004';
    end if;
    if caller is null or p_expected_owner_id is null or caller <> p_expected_owner_id then
        raise exception 'A verified eligible signed-in account is required' using errcode = '42501';
    end if;
    -- Same lock/order as the service-only publisher. Auth bans/deletion also
    -- update this row, so a completed revocation cannot race a later publish.
    perform 1 from auth.users where id = caller for update;
    if not found or not private.free_pro_beta_account_eligible() then
        raise exception 'A verified eligible signed-in account is required' using errcode = '42501';
    end if;
    if p_participating and not private.free_pro_access_enabled() then
        raise exception 'The free access phase is not available' using errcode = '55000';
    end if;
    insert into private.free_pro_beta_memberships(owner_id, participating, updated_at)
    values (caller, p_participating, now())
    on conflict (owner_id) do update
        set participating = excluded.participating, updated_at = excluded.updated_at;
    return public.free_pro_beta_status();
end;
$$;
revoke all on function public.set_free_pro_beta_participation(boolean, uuid)
    from public, anon, service_role;
grant execute on function public.set_free_pro_beta_participation(boolean, uuid) to authenticated;

create function private.publish_forum_chart_post(
    target_post_id uuid,
    target_owner_id uuid,
    target_byte_size bigint,
    target_sha256 text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
    account_record auth.users%rowtype;
    post_record public.forum_chart_posts%rowtype;
    paid_record public.subscriptions%rowtype;
    allowed boolean;
begin
    -- target_owner_id is supplied only by the authenticated Edge handler, never
    -- taken from its JSON body. Clients cannot execute either RPC implementation.
    select * into account_record from auth.users
    where id = target_owner_id for update;
    if not found or account_record.deleted_at is not null
        or account_record.is_anonymous is true
        or (account_record.banned_until is not null and account_record.banned_until > now())
        or (account_record.email_confirmed_at is null and account_record.phone_confirmed_at is null) then
        raise exception 'Forum publishing access is no longer available' using errcode = '42501';
    end if;

    -- Each statement after the account lock sees a freshly committed membership
    -- choice under READ COMMITTED. Existing and initially absent rows are covered
    -- by the setter's account mutex. Do not reuse the Edge admission snapshot.
    if private.free_pro_access_enabled() then
        select coalesce((select participating from private.free_pro_beta_memberships
            where owner_id = target_owner_id), true) into allowed;
    else
        -- Preserve the existing paid-policy fallback without creating a grant.
        -- A subscription update/revocation cannot complete across this lock.
        select * into paid_record from public.subscriptions
        where owner_id = target_owner_id for update;
        allowed := found and paid_record.plan = 'studioSubscription' and paid_record.status = 'active'
            and (paid_record.entitlement_expires_at is null or paid_record.entitlement_expires_at > now())
            and paid_record.revoked_at is null;
    end if;
    if allowed is not true then
        raise exception 'Forum publishing access is no longer available' using errcode = '42501';
    end if;

    select * into post_record from public.forum_chart_posts
    where id = target_post_id for update;
    if not found then
        raise exception 'Forum post changed before publication' using errcode = '55000';
    end if;
    if post_record.owner_id <> target_owner_id then
        raise exception 'Forum post belongs to a different account' using errcode = '42501';
    end if;
    -- Repeated eligible requests do not rewrite provenance or publication time.
    if post_record.status in ('published', 'flagged') then
        return to_jsonb(post_record);
    end if;
    if post_record.status <> 'pending' then
        raise exception 'Only pending forum posts can be published' using errcode = '55000';
    end if;
    if post_record.pdf_storage_bucket <> 'forum_chart_pdfs'
        or post_record.pdf_storage_path <> target_owner_id::text || '/' || target_post_id::text || '.pdf'
        or target_byte_size is null or target_byte_size <= 0 or target_byte_size > 10485760
        or lower(btrim(coalesce(target_sha256, ''))) !~ '^[a-f0-9]{64}$' then
        raise exception 'Forum PDF provenance input is invalid' using errcode = '22023';
    end if;
    perform 1 from storage.objects
    where bucket_id = 'forum_chart_pdfs' and name = post_record.pdf_storage_path
        and storage.extension(name) = 'pdf' for share;
    if not found then
        raise exception 'Forum PDF storage object is unavailable' using errcode = '22023';
    end if;

    -- Both provenance and visibility change in this transaction; an exception
    -- rolls them back together. Withdrawal/removal wins if it completed first.
    perform private.finalize_forum_chart_post_pdf(target_post_id, target_byte_size, target_sha256);
    update public.forum_chart_posts set status = 'published', published_at = now()
    where id = target_post_id and status = 'pending' returning * into post_record;
    if not found then
        raise exception 'Forum post changed before publication' using errcode = '55000';
    end if;
    return to_jsonb(post_record);
end;
$$;
revoke all on function private.publish_forum_chart_post(uuid, uuid, bigint, text)
    from public, anon, authenticated, service_role;
grant execute on function private.publish_forum_chart_post(uuid, uuid, bigint, text) to service_role;

-- This bounded wrapper is service-only, like the existing PDF finalizer. There
-- is no authenticated moderation UPDATE grant or new client finalization path.
create function public.publish_forum_chart_post(
    target_post_id uuid,
    target_owner_id uuid,
    target_byte_size bigint,
    target_sha256 text
)
returns jsonb language sql security invoker set search_path = ''
as $$
    select private.publish_forum_chart_post(target_post_id, target_owner_id, target_byte_size, target_sha256);
$$;
revoke all on function public.publish_forum_chart_post(uuid, uuid, bigint, text)
    from public, anon, authenticated, service_role;
grant execute on function public.publish_forum_chart_post(uuid, uuid, bigint, text) to service_role;
