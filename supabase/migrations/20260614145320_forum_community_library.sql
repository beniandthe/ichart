create schema if not exists private;
revoke all on schema private from public;

create or replace function public.current_user_has_active_pro()
returns boolean
language sql
stable
set search_path = public, auth, pg_temp
as $$
    select exists (
        select 1
        from public.subscriptions
        where owner_id = auth.uid()
            and plan = 'studioSubscription'
            and status = 'active'
            and (
                entitlement_expires_at is null
                or entitlement_expires_at > now()
            )
            and revoked_at is null
    );
$$;

create table public.forum_songs (
    id uuid primary key default gen_random_uuid(),
    song_title text not null,
    artist_name text not null,
    normalized_song_title text not null,
    normalized_artist_name text not null,
    created_by uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (btrim(song_title) <> ''),
    check (btrim(artist_name) <> ''),
    check (normalized_song_title = lower(btrim(song_title))),
    check (normalized_artist_name = lower(btrim(artist_name)))
);

create table public.forum_chart_posts (
    id uuid primary key default gen_random_uuid(),
    song_id uuid not null references public.forum_songs(id) on delete restrict,
    owner_id uuid not null references auth.users(id) on delete cascade,
    local_chart_id uuid,
    chart_title text not null,
    arranger_credit text not null,
    creator_display_name text not null,
    tags text[] not null default '{}',
    version_note text,
    layout_style text not null check (layout_style in ('simpleChordSheet', 'rhythmSectionSheet', 'leadSheet')),
    pdf_storage_bucket text not null default 'forum_chart_pdfs',
    pdf_storage_path text not null unique,
    status text not null default 'published' check (status in ('published', 'flagged', 'hidden', 'removed')),
    vote_up_count integer not null default 0 check (vote_up_count >= 0),
    vote_down_count integer not null default 0 check (vote_down_count >= 0),
    report_count integer not null default 0 check (report_count >= 0),
    ranking_score numeric not null default 0,
    published_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (btrim(chart_title) <> ''),
    check (btrim(arranger_credit) <> ''),
    check (btrim(creator_display_name) <> ''),
    check (pdf_storage_bucket = 'forum_chart_pdfs'),
    check (pdf_storage_path like owner_id::text || '/%.pdf')
);

create table public.forum_comments (
    id uuid primary key default gen_random_uuid(),
    post_id uuid not null references public.forum_chart_posts(id) on delete cascade,
    owner_id uuid not null references auth.users(id) on delete cascade,
    body text not null,
    status text not null default 'visible' check (status in ('visible', 'hidden', 'removed')),
    report_count integer not null default 0 check (report_count >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (btrim(body) <> '')
);

create table public.forum_votes (
    id uuid primary key default gen_random_uuid(),
    post_id uuid not null references public.forum_chart_posts(id) on delete cascade,
    owner_id uuid not null references auth.users(id) on delete cascade,
    vote_value smallint not null check (vote_value in (-1, 1)),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (post_id, owner_id)
);

create table public.forum_reports (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    target_type text not null check (target_type in ('post', 'comment')),
    post_id uuid references public.forum_chart_posts(id) on delete cascade,
    comment_id uuid references public.forum_comments(id) on delete cascade,
    reason text not null check (
        reason in (
            'wrongChords',
            'wrongForm',
            'badFormatting',
            'spam',
            'abuse',
            'copyrightConcern',
            'other'
        )
    ),
    detail text,
    created_at timestamptz not null default now(),
    check (
        (target_type = 'post' and post_id is not null and comment_id is null)
        or (target_type = 'comment' and comment_id is not null and post_id is null)
    )
);

create table public.forum_author_badges (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    badge_type text not null check (
        badge_type in (
            'verifiedContributor',
            'trustedArranger',
            'communityExpert'
        )
    ),
    awarded_by uuid references auth.users(id) on delete set null,
    awarded_at timestamptz not null default now(),
    note text,
    unique (owner_id, badge_type)
);

create unique index forum_songs_normalized_title_artist_idx
    on public.forum_songs(normalized_song_title, normalized_artist_name);
create index forum_songs_search_idx
    on public.forum_songs using gin (
        to_tsvector('simple', song_title || ' ' || artist_name)
    );
create index forum_chart_posts_song_ranking_idx
    on public.forum_chart_posts(song_id, status, ranking_score desc, published_at desc);
create index forum_chart_posts_owner_idx
    on public.forum_chart_posts(owner_id, published_at desc);
create index forum_chart_posts_tags_idx
    on public.forum_chart_posts using gin(tags);
create index forum_comments_post_idx
    on public.forum_comments(post_id, created_at);
create index forum_votes_owner_idx
    on public.forum_votes(owner_id, post_id);
create unique index forum_reports_post_once_idx
    on public.forum_reports(owner_id, post_id)
    where post_id is not null;
create unique index forum_reports_comment_once_idx
    on public.forum_reports(owner_id, comment_id)
    where comment_id is not null;
create index forum_author_badges_owner_idx
    on public.forum_author_badges(owner_id);

alter table public.forum_songs enable row level security;
alter table public.forum_chart_posts enable row level security;
alter table public.forum_comments enable row level security;
alter table public.forum_votes enable row level security;
alter table public.forum_reports enable row level security;
alter table public.forum_author_badges enable row level security;

revoke all on table public.forum_songs from anon, authenticated;
revoke all on table public.forum_chart_posts from anon, authenticated;
revoke all on table public.forum_comments from anon, authenticated;
revoke all on table public.forum_votes from anon, authenticated;
revoke all on table public.forum_reports from anon, authenticated;
revoke all on table public.forum_author_badges from anon, authenticated;

grant select, insert on table public.forum_songs to authenticated;
grant select on table public.forum_chart_posts to authenticated;
grant insert (
    id,
    song_id,
    owner_id,
    local_chart_id,
    chart_title,
    arranger_credit,
    creator_display_name,
    tags,
    version_note,
    layout_style,
    pdf_storage_bucket,
    pdf_storage_path
) on table public.forum_chart_posts to authenticated;
grant select, insert on table public.forum_comments to authenticated;
grant select, insert, update (vote_value), delete on table public.forum_votes to authenticated;
grant select, insert on table public.forum_reports to authenticated;
grant select on table public.forum_author_badges to authenticated;

create policy "forum_songs_select_active_pro"
    on public.forum_songs
    for select
    to authenticated
    using (public.current_user_has_active_pro());

create policy "forum_songs_insert_active_pro"
    on public.forum_songs
    for insert
    to authenticated
    with check (
        auth.uid() = created_by
        and public.current_user_has_active_pro()
    );

create policy "forum_chart_posts_select_active_pro_visible"
    on public.forum_chart_posts
    for select
    to authenticated
    using (
        public.current_user_has_active_pro()
        and status in ('published', 'flagged')
    );

create policy "forum_chart_posts_insert_active_pro_own"
    on public.forum_chart_posts
    for insert
    to authenticated
    with check (
        auth.uid() = owner_id
        and public.current_user_has_active_pro()
        and status = 'published'
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

create policy "forum_comments_select_active_pro_visible"
    on public.forum_comments
    for select
    to authenticated
    using (
        public.current_user_has_active_pro()
        and status = 'visible'
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.id = forum_comments.post_id
                and forum_chart_posts.status in ('published', 'flagged')
        )
    );

create policy "forum_comments_insert_active_pro_own"
    on public.forum_comments
    for insert
    to authenticated
    with check (
        auth.uid() = owner_id
        and public.current_user_has_active_pro()
        and status = 'visible'
        and report_count = 0
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.id = forum_comments.post_id
                and forum_chart_posts.status in ('published', 'flagged')
        )
    );

create policy "forum_votes_select_own_active_pro"
    on public.forum_votes
    for select
    to authenticated
    using (
        auth.uid() = owner_id
        and public.current_user_has_active_pro()
    );

create policy "forum_votes_insert_active_pro_own"
    on public.forum_votes
    for insert
    to authenticated
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

create policy "forum_votes_update_active_pro_own"
    on public.forum_votes
    for update
    to authenticated
    using (
        auth.uid() = owner_id
        and public.current_user_has_active_pro()
    )
    with check (
        auth.uid() = owner_id
        and public.current_user_has_active_pro()
    );

create policy "forum_votes_delete_active_pro_own"
    on public.forum_votes
    for delete
    to authenticated
    using (
        auth.uid() = owner_id
        and public.current_user_has_active_pro()
    );

create policy "forum_reports_select_own_active_pro"
    on public.forum_reports
    for select
    to authenticated
    using (
        auth.uid() = owner_id
        and public.current_user_has_active_pro()
    );

create policy "forum_reports_insert_active_pro_own"
    on public.forum_reports
    for insert
    to authenticated
    with check (
        auth.uid() = owner_id
        and public.current_user_has_active_pro()
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

create policy "forum_author_badges_select_active_pro"
    on public.forum_author_badges
    for select
    to authenticated
    using (public.current_user_has_active_pro());

create trigger forum_songs_set_updated_at
    before update on public.forum_songs
    for each row execute function public.set_updated_at();

create trigger forum_chart_posts_set_updated_at
    before update on public.forum_chart_posts
    for each row execute function public.set_updated_at();

create trigger forum_comments_set_updated_at
    before update on public.forum_comments
    for each row execute function public.set_updated_at();

create trigger forum_votes_set_updated_at
    before update on public.forum_votes
    for each row execute function public.set_updated_at();

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
        when status in ('hidden', 'removed') then status
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

create or replace function private.forum_votes_refresh_post()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    perform private.refresh_forum_chart_post_quality(coalesce(new.post_id, old.post_id));
    return coalesce(new, old);
end;
$$;

create or replace function private.forum_reports_refresh_target()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    target_post_id uuid;
begin
    if new.target_type = 'comment' then
        update public.forum_comments
        set report_count = (
            select count(*)::integer
            from public.forum_reports
            where comment_id = new.comment_id
        )
        where id = new.comment_id
        returning post_id into target_post_id;
    else
        target_post_id := new.post_id;
    end if;

    perform private.refresh_forum_chart_post_quality(target_post_id);
    return new;
end;
$$;

create trigger forum_votes_refresh_post_after_insert
    after insert on public.forum_votes
    for each row execute function private.forum_votes_refresh_post();

create trigger forum_votes_refresh_post_after_update
    after update on public.forum_votes
    for each row execute function private.forum_votes_refresh_post();

create trigger forum_votes_refresh_post_after_delete
    after delete on public.forum_votes
    for each row execute function private.forum_votes_refresh_post();

create trigger forum_reports_refresh_target_after_insert
    after insert on public.forum_reports
    for each row execute function private.forum_reports_refresh_target();

insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
) values (
    'forum_chart_pdfs',
    'forum_chart_pdfs',
    false,
    10485760,
    array['application/pdf']
) on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "forum_chart_pdfs_insert_active_pro_owner_folder"
    on storage.objects
    for insert
    to authenticated
    with check (
        bucket_id = 'forum_chart_pdfs'
        and public.current_user_has_active_pro()
        and (storage.foldername(name))[1] = auth.uid()::text
        and storage.extension(name) = 'pdf'
    );

create policy "forum_chart_pdfs_select_active_pro_visible_post"
    on storage.objects
    for select
    to authenticated
    using (
        bucket_id = 'forum_chart_pdfs'
        and public.current_user_has_active_pro()
        and exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.pdf_storage_path = storage.objects.name
                and forum_chart_posts.status in ('published', 'flagged')
        )
    );
