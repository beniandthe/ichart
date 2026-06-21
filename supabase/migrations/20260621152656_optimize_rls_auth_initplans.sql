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
