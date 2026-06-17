drop policy if exists "forum_votes_update_active_pro_own" on public.forum_votes;
drop policy if exists "forum_votes_delete_active_pro_own" on public.forum_votes;

create policy "forum_votes_update_active_pro_own"
    on public.forum_votes
    for update
    to authenticated
    using (
        auth.uid() = owner_id
        and public.current_user_has_active_pro()
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.id = forum_votes.post_id
                and forum_chart_posts.status in ('published', 'flagged')
        )
    )
    with check (
        auth.uid() = owner_id
        and public.current_user_has_active_pro()
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.id = forum_votes.post_id
                and forum_chart_posts.status in ('published', 'flagged')
        )
    );

create policy "forum_votes_delete_active_pro_own"
    on public.forum_votes
    for delete
    to authenticated
    using (
        auth.uid() = owner_id
        and public.current_user_has_active_pro()
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.id = forum_votes.post_id
                and forum_chart_posts.status in ('published', 'flagged')
        )
    );
