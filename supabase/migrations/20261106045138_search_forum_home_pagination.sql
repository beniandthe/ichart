-- Search visible forum metadata before applying response limits. The existing
-- full-text expression index does not implement the client's literal substring
-- semantics; do not replace this predicate with raw tsquery/PostgREST syntax.
-- Caller/session statement_timeout remains the execution-budget authority:
-- setting it inside a running function would not bound its outer statement.
create function public.search_forum_home(
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
    -- policies authoritative. A stale signed-out/Basic request returns no data.
    if (select auth.uid()) is null or not (select public.current_user_has_active_pro()) then
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
