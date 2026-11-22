-- The rollout is server-owned and starts in the existing beta phase. Enabling
-- it is a separate release action. Retention stays governed by its independent
-- pause, and no Apple billing or beta-membership records are rewritten.
create table private.ichart_paid_feature_policy (
    singleton boolean primary key default true check (singleton),
    enabled boolean not null default false
);
alter table private.ichart_paid_feature_policy enable row level security;
revoke all on table private.ichart_paid_feature_policy
    from public, anon, authenticated, service_role;
grant select on table private.ichart_paid_feature_policy to service_role;
insert into private.ichart_paid_feature_policy(singleton, enabled) values (true, false);

create function private.paid_features_enabled()
returns boolean language sql stable security definer set search_path = ''
as $$
    select coalesce((select enabled from private.ichart_paid_feature_policy where singleton), false);
$$;
revoke all on function private.paid_features_enabled() from public, anon, authenticated;
grant execute on function private.paid_features_enabled() to service_role;

-- Existing beta status and enrollment use the same server rollout boundary.
-- Membership stays as recorded when paid access starts.
create or replace function public.current_user_has_free_pro_access()
returns boolean language sql stable security definer set search_path = ''
as $$
    select private.free_pro_access_enabled() and not private.paid_features_enabled()
        and private.free_pro_beta_account_eligible()
        and coalesce((select membership.participating from private.free_pro_beta_memberships membership
            where membership.owner_id = (select auth.uid())), true);
$$;
revoke all on function public.current_user_has_free_pro_access() from public, anon;
grant execute on function public.current_user_has_free_pro_access() to authenticated, service_role;

create or replace function public.free_pro_beta_status()
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
    available := private.free_pro_access_enabled() and not private.paid_features_enabled();
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
    -- Join/leave shares the release boundary with the publication transaction.
    perform 1 from private.ichart_paid_feature_policy where singleton for share;
    if p_participating and (not private.free_pro_access_enabled() or private.paid_features_enabled()) then
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

create or replace function public.current_user_has_active_pro()
returns boolean language sql stable security definer set search_path = ''
as $$
    select private.free_pro_beta_account_eligible() and case
        when private.paid_features_enabled() then exists (
            select 1 from public.subscriptions
            where owner_id = (select auth.uid())
                and provider = 'storekit' and plan = 'studioSubscription' and status = 'active'
                and app_store_status = 'active' and entitlement_expires_at > now()
                and revoked_at is null and last_verified_at is not null
        )
        when private.free_pro_access_enabled() then public.current_user_has_free_pro_access()
        else exists (
            select 1 from public.subscriptions
            where owner_id = (select auth.uid())
                and plan = 'studioSubscription' and status = 'active'
                and (entitlement_expires_at is null or entitlement_expires_at > now())
                and revoked_at is null
        )
    end;
$$;
revoke all on function public.current_user_has_active_pro() from public, anon;
grant execute on function public.current_user_has_active_pro() to authenticated, service_role;

create or replace function private.publish_forum_chart_post(
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
    paid_features boolean;
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
    -- Serializes publication with the administrative paid rollout update.
    -- A release switch completed before this lock cannot retain beta authority.
    select enabled into paid_features from private.ichart_paid_feature_policy
    where singleton for share;
    if not coalesce(paid_features, false) and private.free_pro_access_enabled() then
        select coalesce((select participating from private.free_pro_beta_memberships
            where owner_id = target_owner_id), true) into allowed;
    else
        -- Preserve the existing paid-policy fallback without creating a grant.
        -- A subscription update/revocation cannot complete across this lock.
        select * into paid_record from public.subscriptions
        where owner_id = target_owner_id for update;
        allowed := found and paid_record.plan = 'studioSubscription' and paid_record.status = 'active'
            and paid_record.revoked_at is null and case
                when paid_features then paid_record.provider = 'storekit'
                    and paid_record.app_store_status = 'active'
                    and paid_record.entitlement_expires_at > now()
                    and paid_record.last_verified_at is not null
                else paid_record.entitlement_expires_at is null or paid_record.entitlement_expires_at > now()
            end;
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

-- Readers must have a live, verified, non-anonymous account. The existing
-- private eligibility predicate also rejects deleted or banned accounts.
create function private.current_user_can_read_forum()
returns boolean language sql stable security definer set search_path = ''
as $$
    select (select auth.uid()) is not null and private.free_pro_beta_account_eligible();
$$;
revoke all on function private.current_user_can_read_forum()
    from public, anon, authenticated, service_role;
grant execute on function private.current_user_can_read_forum() to authenticated;

create function public.current_user_can_read_forum()
returns boolean language sql stable security invoker set search_path = ''
begin atomic
    select private.current_user_can_read_forum();
end;
revoke all on function public.current_user_can_read_forum() from public, anon, service_role;
grant execute on function public.current_user_can_read_forum() to authenticated;

alter policy "forum_songs_select_active_pro" on public.forum_songs
    using (
        (select public.current_user_can_read_forum())
        and (
            exists (
                select 1 from public.forum_chart_posts
                where forum_chart_posts.song_id = forum_songs.id
                    and forum_chart_posts.status in ('published', 'flagged')
            )
            or exists (
                select 1 from public.forum_chart_posts
                where forum_chart_posts.song_id = forum_songs.id
                    and forum_chart_posts.status = 'pending'
                    and forum_chart_posts.owner_id = (select auth.uid())
            )
            or (created_by = (select auth.uid()) and (select public.current_user_has_active_pro()))
        )
    );

alter policy "forum_chart_posts_select_active_pro_visible" on public.forum_chart_posts
    using (
        (select public.current_user_can_read_forum())
        and (
            status in ('published', 'flagged')
            or (status = 'pending' and owner_id = (select auth.uid()))
        )
        and not exists (
            select 1 from public.forum_user_blocks
            where forum_user_blocks.owner_id = (select auth.uid())
                and forum_user_blocks.blocked_owner_id = forum_chart_posts.owner_id
        )
    );

alter policy "forum_comments_select_active_pro_visible" on public.forum_comments
    using (
        (select public.current_user_can_read_forum())
        and status = 'visible'
        and not exists (
            select 1 from public.forum_user_blocks
            where forum_user_blocks.owner_id = (select auth.uid())
                and forum_user_blocks.blocked_owner_id = forum_comments.owner_id
        )
        and exists (
            select 1 from public.forum_chart_posts
            where forum_chart_posts.id = forum_comments.post_id
                and forum_chart_posts.status in ('published', 'flagged')
        )
    );

alter policy "forum_author_badges_select_active_pro" on public.forum_author_badges
    using ((select public.current_user_can_read_forum()));

alter policy "forum_reports_select_own_active_pro" on public.forum_reports
    using ((select auth.uid()) = owner_id and (select public.current_user_can_read_forum()));

alter policy "forum_reports_insert_active_pro_own" on public.forum_reports
    with check (
        (select auth.uid()) = owner_id and (select public.current_user_can_read_forum())
        and (
            (target_type = 'post' and exists (
                select 1 from public.forum_chart_posts
                where forum_chart_posts.id = forum_reports.post_id
                    and forum_chart_posts.status in ('published', 'flagged')
            ))
            or (target_type = 'comment' and exists (
                select 1 from public.forum_comments
                join public.forum_chart_posts on forum_chart_posts.id = forum_comments.post_id
                where forum_comments.id = forum_reports.comment_id
                    and forum_comments.status = 'visible'
                    and forum_chart_posts.status in ('published', 'flagged')
            ))
        )
    );

alter policy "forum_user_blocks_select_own" on public.forum_user_blocks
    using ((select auth.uid()) = owner_id and (select public.current_user_can_read_forum()));
alter policy "forum_user_blocks_insert_own" on public.forum_user_blocks
    with check ((select auth.uid()) = owner_id and owner_id <> blocked_owner_id
        and (select public.current_user_can_read_forum()));
alter policy "forum_user_blocks_delete_own" on public.forum_user_blocks
    using ((select auth.uid()) = owner_id and (select public.current_user_can_read_forum()));

create or replace function public.search_forum_home(
    search_query text,
    page_size integer default 20,
    after_updated_at timestamptz default null,
    after_song_id uuid default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
    normalized_query text;
    requested_size integer := least(coalesce(page_size, 20), 20);
    response jsonb;
begin
    if char_length(coalesce(search_query, '')) > 200 then
        raise exception 'Forum search is limited to 200 characters.' using errcode = '22023';
    end if;
    if requested_size < 1 then
        raise exception 'Forum search page size must be positive.' using errcode = '22023';
    end if;
    if (after_updated_at is null) <> (after_song_id is null)
        or (after_updated_at is not null and not isfinite(after_updated_at)) then
        raise exception 'Forum search requires a complete finite cursor.' using errcode = '22023';
    end if;

    normalized_query := pg_catalog.normalize(pg_catalog.lower(pg_catalog.btrim(
        pg_catalog.regexp_replace(coalesce(search_query, ''), '[[:space:]]+', ' ', 'g')
    )), 'NFC');

    -- No bypass: invoker SELECTs below keep table RLS and blocked-contributor
    -- policies authoritative. A stale signed-out request returns no data.
    if (select auth.uid()) is null or not (select public.current_user_can_read_forum()) then
        return pg_catalog.jsonb_build_object('songs', '[]'::jsonb, 'next_cursor', null);
    end if;

    with matching_songs as materialized (
        select songs.id, songs.song_title, songs.artist_name, songs.updated_at,
            matching_posts.posts
        from public.forum_songs songs
        cross join lateral (
            select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                    'id', ranked.id,
                    'song_id', ranked.song_id,
                    'owner_id', ranked.owner_id,
                    'chart_title', ranked.chart_title,
                    'arranger_credit', ranked.arranger_credit,
                    'creator_display_name', ranked.creator_display_name,
                    'tags', ranked.tags,
                    'version_note', ranked.version_note,
                    'layout_style', ranked.layout_style,
                    'pdf_storage_path', ranked.pdf_storage_path,
                    'status', ranked.status,
                    'vote_up_count', ranked.vote_up_count,
                    'vote_down_count', ranked.vote_down_count,
                    'report_count', ranked.report_count,
                    'ranking_score', ranked.ranking_score,
                    'published_at', ranked.published_at
                ) order by ranked.ranking_score desc, ranked.published_at desc, ranked.id desc
            ) as posts
            from (
                select posts.*
                from public.forum_chart_posts posts
                where posts.song_id = songs.id
                    and posts.status in ('published', 'flagged')
                    and (
                        normalized_query = ''
                        or pg_catalog.strpos((
                            select pg_catalog.string_agg(
                                pg_catalog.normalize(pg_catalog.lower(pg_catalog.btrim(
                                    pg_catalog.regexp_replace(parts.value, '[[:space:]]+', ' ', 'g')
                                )), 'NFC'),
                                ' ' order by parts.position
                            )
                            from pg_catalog.unnest(
                                array[songs.song_title, songs.artist_name, posts.chart_title,
                                    posts.arranger_credit, posts.creator_display_name] || posts.tags
                            ) with ordinality as parts(value, position)
                        ), normalized_query) > 0
                    )
                order by posts.ranking_score desc, posts.published_at desc, posts.id desc
                limit 3
            ) ranked
        ) matching_posts
        where matching_posts.posts is not null
            and (
                after_updated_at is null
                or (songs.updated_at, songs.id) < (after_updated_at, after_song_id)
            )
        order by songs.updated_at desc, songs.id desc
        limit requested_size + 1
    ), included_songs as materialized (
        select *
        from matching_songs
        order by updated_at desc, id desc
        limit requested_size
    )
    select pg_catalog.jsonb_build_object(
        'songs', coalesce((
            select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                    'song', pg_catalog.jsonb_build_object(
                        'id', included.id,
                        'song_title', included.song_title,
                        'artist_name', included.artist_name,
                        'updated_at', included.updated_at
                    ),
                    'posts', included.posts
                ) order by included.updated_at desc, included.id desc
            )
            from included_songs included
        ), '[]'::jsonb),
        'next_cursor', case when (select count(*) from matching_songs) > requested_size then (
            select pg_catalog.jsonb_build_object('updated_at', included.updated_at, 'id', included.id)
            from included_songs included
            order by included.updated_at asc, included.id asc
            limit 1
        ) else null end
    ) into response;

    return response;
end;
$$;

revoke all on function public.search_forum_home(text, integer, timestamptz, uuid)
    from public, anon, service_role;
grant execute on function public.search_forum_home(text, integer, timestamptz, uuid)
    to authenticated;

comment on function public.search_forum_home(text, integer, timestamptz, uuid) is
    'RLS-preserving literal forum search; at most 20 song groups and 3 matching posts per group, with a stable timestamp/UUID keyset cursor.';
