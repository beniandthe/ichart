create table if not exists public.forum_user_blocks (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    blocked_owner_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    check (owner_id <> blocked_owner_id),
    unique (owner_id, blocked_owner_id)
);

create index if not exists forum_user_blocks_owner_idx
    on public.forum_user_blocks(owner_id, blocked_owner_id);

alter table public.forum_user_blocks enable row level security;

revoke all on table public.forum_user_blocks from anon, authenticated;
grant select, insert, delete on table public.forum_user_blocks to authenticated;

create policy "forum_user_blocks_select_own"
    on public.forum_user_blocks
    for select
    to authenticated
    using (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
    );

create policy "forum_user_blocks_insert_own"
    on public.forum_user_blocks
    for insert
    to authenticated
    with check (
        (select auth.uid()) = owner_id
        and owner_id <> blocked_owner_id
        and (select public.current_user_has_active_pro())
    );

create policy "forum_user_blocks_delete_own"
    on public.forum_user_blocks
    for delete
    to authenticated
    using (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
    );

alter policy "forum_chart_posts_select_active_pro_visible"
    on public.forum_chart_posts
    using (
        (select public.current_user_has_active_pro())
        and (
            status in ('published', 'flagged')
            or (status = 'pending' and owner_id = (select auth.uid()))
        )
        and not exists (
            select 1
            from public.forum_user_blocks
            where forum_user_blocks.owner_id = (select auth.uid())
                and forum_user_blocks.blocked_owner_id = forum_chart_posts.owner_id
        )
    );

alter policy "forum_comments_select_active_pro_visible"
    on public.forum_comments
    using (
        (select public.current_user_has_active_pro())
        and status = 'visible'
        and not exists (
            select 1
            from public.forum_user_blocks
            where forum_user_blocks.owner_id = (select auth.uid())
                and forum_user_blocks.blocked_owner_id = forum_comments.owner_id
        )
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.id = forum_comments.post_id
                and forum_chart_posts.status in ('published', 'flagged')
                and not exists (
                    select 1
                    from public.forum_user_blocks
                    where forum_user_blocks.owner_id = (select auth.uid())
                        and forum_user_blocks.blocked_owner_id = forum_chart_posts.owner_id
                )
        )
    );
