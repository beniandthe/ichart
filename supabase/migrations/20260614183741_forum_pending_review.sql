alter table public.forum_chart_posts
    drop constraint if exists forum_chart_posts_status_check;

alter table public.forum_chart_posts
    alter column status set default 'pending',
    add constraint forum_chart_posts_status_check
        check (status in ('pending', 'published', 'flagged', 'hidden', 'removed'));

grant insert (status) on table public.forum_chart_posts to authenticated;

drop policy if exists "forum_chart_posts_select_active_pro_visible" on public.forum_chart_posts;
drop policy if exists "forum_chart_posts_insert_active_pro_own" on public.forum_chart_posts;

create policy "forum_chart_posts_select_active_pro_visible"
    on public.forum_chart_posts
    for select
    to authenticated
    using (
        public.current_user_has_active_pro()
        and (
            status in ('published', 'flagged')
            or (
                status = 'pending'
                and owner_id = auth.uid()
            )
        )
    );

create policy "forum_chart_posts_insert_active_pro_own"
    on public.forum_chart_posts
    for insert
    to authenticated
    with check (
        auth.uid() = owner_id
        and public.current_user_has_active_pro()
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

create or replace function private.refresh_forum_chart_post_quality(target_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    up_votes integer;
    down_votes integer;
    reports integer;
    total_votes integer;
    positive_ratio numeric;
    confidence_score numeric;
    next_status text;
begin
    select
        count(*) filter (where vote_value = 1)::integer,
        count(*) filter (where vote_value = -1)::integer
    into up_votes, down_votes
    from public.forum_votes
    where post_id = target_post_id;

    select count(*)::integer
    into reports
    from public.forum_reports
    where post_id = target_post_id;

    total_votes := up_votes + down_votes;
    positive_ratio := case
        when total_votes = 0 then 0
        else up_votes::numeric / total_votes::numeric
    end;
    confidence_score := case
        when total_votes = 0 then 0
        else (positive_ratio * ln(total_votes + 1)) - (down_votes::numeric * 0.18) - (reports::numeric * 0.35)
    end;

    select case
        when status in ('pending', 'hidden', 'removed') then status
        when reports >= 3 then 'flagged'
        when total_votes >= 5 and down_votes::numeric / total_votes::numeric >= 0.70 then 'flagged'
        else 'published'
    end
    into next_status
    from public.forum_chart_posts
    where id = target_post_id;

    update public.forum_chart_posts
    set vote_up_count = up_votes,
        vote_down_count = down_votes,
        report_count = reports,
        ranking_score = confidence_score,
        status = coalesce(next_status, status)
    where id = target_post_id;
end;
$$;
