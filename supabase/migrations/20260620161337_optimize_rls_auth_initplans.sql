create or replace function public.current_user_has_active_pro()
returns boolean
language sql
stable
set search_path = public, auth, pg_temp
as $$
    select exists (
        select 1
        from public.subscriptions
        where owner_id = (select auth.uid())
            and plan = 'studioSubscription'
            and status = 'active'
            and (
                entitlement_expires_at is null
                or entitlement_expires_at > now()
            )
            and revoked_at is null
    );
$$;

alter policy "profiles_select_own"
    on public.profiles
    using ((select auth.uid()) = id);

alter policy "profiles_insert_own"
    on public.profiles
    with check ((select auth.uid()) = id);

alter policy "profiles_update_own"
    on public.profiles
    using ((select auth.uid()) = id)
    with check ((select auth.uid()) = id);

alter policy "chart_documents_select_own"
    on public.chart_documents
    using ((select auth.uid()) = owner_id);

alter policy "chart_documents_insert_own"
    on public.chart_documents
    with check (
        (select auth.uid()) = owner_id
        and (
            latest_snapshot_id is null
            or exists (
                select 1
                from public.chart_snapshots
                where chart_snapshots.id = chart_documents.latest_snapshot_id
                    and chart_snapshots.chart_id = chart_documents.id
                    and chart_snapshots.owner_id = (select auth.uid())
            )
        )
    );

alter policy "chart_documents_update_own"
    on public.chart_documents
    using ((select auth.uid()) = owner_id)
    with check (
        (select auth.uid()) = owner_id
        and (
            latest_snapshot_id is null
            or exists (
                select 1
                from public.chart_snapshots
                where chart_snapshots.id = chart_documents.latest_snapshot_id
                    and chart_snapshots.chart_id = chart_documents.id
                    and chart_snapshots.owner_id = (select auth.uid())
            )
        )
    );

alter policy "chart_documents_delete_own"
    on public.chart_documents
    using ((select auth.uid()) = owner_id);

alter policy "chart_snapshots_select_own"
    on public.chart_snapshots
    using ((select auth.uid()) = owner_id);

alter policy "chart_snapshots_insert_own"
    on public.chart_snapshots
    with check (
        (select auth.uid()) = owner_id
        and exists (
            select 1
            from public.chart_documents
            where chart_documents.id = chart_snapshots.chart_id
                and chart_documents.owner_id = (select auth.uid())
        )
    );

alter policy "subscriptions_select_own"
    on public.subscriptions
    using ((select auth.uid()) = owner_id);

alter policy "devices_select_own"
    on public.devices
    using ((select auth.uid()) = owner_id);

alter policy "devices_insert_own"
    on public.devices
    with check ((select auth.uid()) = owner_id);

alter policy "devices_update_own"
    on public.devices
    using ((select auth.uid()) = owner_id)
    with check ((select auth.uid()) = owner_id);

alter policy "devices_delete_own"
    on public.devices
    using ((select auth.uid()) = owner_id);

alter policy "forum_songs_select_active_pro"
    on public.forum_songs
    using ((select public.current_user_has_active_pro()));

alter policy "forum_songs_insert_active_pro"
    on public.forum_songs
    with check (
        (select auth.uid()) = created_by
        and (select public.current_user_has_active_pro())
    );

alter policy "forum_chart_posts_select_active_pro_visible"
    on public.forum_chart_posts
    using (
        (select public.current_user_has_active_pro())
        and (
            status in ('published', 'flagged')
            or (
                status = 'pending'
                and owner_id = (select auth.uid())
            )
        )
    );

alter policy "forum_chart_posts_insert_active_pro_own"
    on public.forum_chart_posts
    with check (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
        and status = 'pending'
        and vote_up_count = 0
        and vote_down_count = 0
        and report_count = 0
        and ranking_score = 0
        and exists (
            select 1
            from public.forum_songs
            where forum_songs.id = forum_chart_posts.song_id
        )
    );

alter policy "forum_comments_select_active_pro_visible"
    on public.forum_comments
    using (
        (select public.current_user_has_active_pro())
        and status = 'visible'
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.id = forum_comments.post_id
                and forum_chart_posts.status in ('published', 'flagged')
        )
    );

alter policy "forum_comments_insert_active_pro_own"
    on public.forum_comments
    with check (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
        and status = 'visible'
        and report_count = 0
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.id = forum_comments.post_id
                and forum_chart_posts.status in ('published', 'flagged')
        )
    );

alter policy "forum_votes_select_own_active_pro"
    on public.forum_votes
    using (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
    );

alter policy "forum_votes_insert_active_pro_own"
    on public.forum_votes
    with check (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.id = forum_votes.post_id
                and forum_chart_posts.status in ('published', 'flagged')
        )
    );

alter policy "forum_votes_update_active_pro_own"
    on public.forum_votes
    using (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.id = forum_votes.post_id
                and forum_chart_posts.status in ('published', 'flagged')
        )
    )
    with check (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.id = forum_votes.post_id
                and forum_chart_posts.status in ('published', 'flagged')
        )
    );

alter policy "forum_votes_delete_active_pro_own"
    on public.forum_votes
    using (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.id = forum_votes.post_id
                and forum_chart_posts.status in ('published', 'flagged')
        )
    );

alter policy "forum_reports_select_own_active_pro"
    on public.forum_reports
    using (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
    );

alter policy "forum_reports_insert_active_pro_own"
    on public.forum_reports
    with check (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
        and (
            (
                target_type = 'post'
                and exists (
                    select 1
                    from public.forum_chart_posts
                    where forum_chart_posts.id = forum_reports.post_id
                        and forum_chart_posts.status in ('published', 'flagged')
                )
            )
            or (
                target_type = 'comment'
                and exists (
                    select 1
                    from public.forum_comments
                    join public.forum_chart_posts
                        on forum_chart_posts.id = forum_comments.post_id
                    where forum_comments.id = forum_reports.comment_id
                        and forum_comments.status = 'visible'
                        and forum_chart_posts.status in ('published', 'flagged')
                )
            )
        )
    );

alter policy "forum_author_badges_select_active_pro"
    on public.forum_author_badges
    using ((select public.current_user_has_active_pro()));

alter policy "forum_chart_pdfs_insert_active_pro_owner_folder"
    on storage.objects
    with check (
        bucket_id = 'forum_chart_pdfs'
        and (select public.current_user_has_active_pro())
        and (storage.foldername(name))[1] = (select auth.uid())::text
        and storage.extension(name) = 'pdf'
    );

alter policy "forum_chart_pdfs_select_active_pro_visible_post"
    on storage.objects
    using (
        bucket_id = 'forum_chart_pdfs'
        and (select public.current_user_has_active_pro())
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.pdf_storage_path = storage.objects.name
                and forum_chart_posts.status in ('published', 'flagged')
        )
    );

alter policy "forum_chart_pdfs_delete_unattached_owner_upload"
    on storage.objects
    using (
        bucket_id = 'forum_chart_pdfs'
        and (select public.current_user_has_active_pro())
        and (storage.foldername(name))[1] = (select auth.uid())::text
        and not exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.pdf_storage_path = storage.objects.name
        )
    );
