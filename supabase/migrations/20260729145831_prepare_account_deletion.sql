create or replace function public.prepare_account_deletion(target_owner_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    reassigned_song_count integer := 0;
    deleted_post_count integer := 0;
    deleted_song_count integer := 0;
begin
    if target_owner_id is null then
        raise exception 'target_owner_id is required';
    end if;

    with replacement as (
        select distinct on (posts.song_id)
            posts.song_id,
            posts.owner_id as replacement_owner_id
        from public.forum_chart_posts posts
        join public.forum_songs songs
            on songs.id = posts.song_id
        where songs.created_by = target_owner_id
            and posts.owner_id <> target_owner_id
        order by posts.song_id, posts.created_at asc, posts.owner_id
    )
    update public.forum_songs songs
    set created_by = replacement.replacement_owner_id,
        updated_at = now()
    from replacement
    where songs.id = replacement.song_id
        and songs.created_by = target_owner_id;

    get diagnostics reassigned_song_count = row_count;

    delete from public.forum_chart_posts posts
    where posts.owner_id = target_owner_id;

    get diagnostics deleted_post_count = row_count;

    delete from public.forum_songs songs
    where songs.created_by = target_owner_id
        and not exists (
            select 1
            from public.forum_chart_posts posts
            where posts.song_id = songs.id
        );

    get diagnostics deleted_song_count = row_count;

    return jsonb_build_object(
        'reassigned_forum_songs', reassigned_song_count,
        'deleted_forum_posts', deleted_post_count,
        'deleted_orphan_forum_songs', deleted_song_count
    );
end;
$$;

revoke all on function public.prepare_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.prepare_account_deletion(uuid) to service_role;
