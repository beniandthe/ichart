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

alter table public.subscriptions
    add column if not exists storekit_app_account_token uuid,
    add column if not exists app_store_signed_at timestamptz,
    add column if not exists app_store_notification_uuid text;

create index if not exists subscriptions_storekit_app_account_token_idx
    on public.subscriptions(storekit_app_account_token)
    where storekit_app_account_token is not null;

create index if not exists subscriptions_app_store_signed_at_idx
    on public.subscriptions(app_store_signed_at desc)
    where app_store_signed_at is not null;

create table if not exists public.app_store_notification_events (
    notification_uuid text primary key,
    original_transaction_id text not null,
    signed_at timestamptz,
    received_at timestamptz not null default now(),
    check (btrim(notification_uuid) <> ''),
    check (btrim(original_transaction_id) <> '')
);

revoke all on table public.app_store_notification_events from anon, authenticated;
alter table public.app_store_notification_events enable row level security;

alter policy "chart_documents_select_own"
    on public.chart_documents
    using (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
    );

alter policy "chart_documents_insert_own"
    on public.chart_documents
    with check (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
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
    using (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
    )
    with check (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
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
    using (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
    );

alter policy "chart_snapshots_select_own"
    on public.chart_snapshots
    using (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
    );

alter policy "chart_snapshots_insert_own"
    on public.chart_snapshots
    with check (
        (select auth.uid()) = owner_id
        and (select public.current_user_has_active_pro())
        and exists (
            select 1
            from public.chart_documents
            where chart_documents.id = chart_snapshots.chart_id
                and chart_documents.owner_id = (select auth.uid())
        )
    );

alter table public.forum_chart_posts
    add column if not exists pdf_provenance_status text not null default 'pending',
    add column if not exists pdf_validated_at timestamptz;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'forum_chart_posts_pdf_provenance_status_check'
    ) then
        alter table public.forum_chart_posts
            add constraint forum_chart_posts_pdf_provenance_status_check
            check (pdf_provenance_status in ('pending', 'validated'));
    end if;
end;
$$;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'forum_chart_posts_pdf_post_path_check'
    ) then
        alter table public.forum_chart_posts
            add constraint forum_chart_posts_pdf_post_path_check
            check (pdf_storage_path = owner_id::text || '/' || id::text || '.pdf');
    end if;
end;
$$;

create or replace function private.profile_display_name(target_user_id uuid)
returns text
language sql
security definer
set search_path = public, pg_temp
as $$
    select nullif(
        btrim(
            concat_ws(
                ' ',
                nullif(btrim(first_name), ''),
                nullif(btrim(last_name), '')
            )
        ),
        ''
    )
    from public.profiles
    where id = target_user_id;
$$;

revoke all on function private.profile_display_name(uuid) from public, anon, authenticated;

create or replace function private.forum_song_exists(target_song_id uuid)
returns boolean
language sql
security definer
set search_path = public, pg_temp
as $$
    select exists (
        select 1
        from public.forum_songs
        where id = target_song_id
    );
$$;

revoke all on function private.forum_song_exists(uuid) from public, anon, authenticated;
grant execute on function private.forum_song_exists(uuid) to authenticated;

create or replace function private.apply_forum_chart_post_server_fields()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
    profile_display_name text;
    expected_pdf_path text;
begin
    profile_display_name := private.profile_display_name(new.owner_id);
    if profile_display_name is null then
        raise exception 'Forum submissions require a locked account name.';
    end if;

    expected_pdf_path := new.owner_id::text || '/' || new.id::text || '.pdf';
    if new.pdf_storage_path is distinct from expected_pdf_path then
        raise exception 'Forum PDF path must match the submitted post.';
    end if;

    new.creator_display_name := profile_display_name;
    new.pdf_provenance_status := 'pending';
    new.pdf_validated_at := null;
    return new;
end;
$$;

revoke all on function private.apply_forum_chart_post_server_fields() from public, anon, authenticated;

drop trigger if exists forum_chart_posts_apply_server_fields on public.forum_chart_posts;
create trigger forum_chart_posts_apply_server_fields
    before insert on public.forum_chart_posts
    for each row
    execute function private.apply_forum_chart_post_server_fields();

create or replace function private.finalize_forum_chart_post_pdf(target_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public, storage, private, pg_temp
as $$
begin
    update public.forum_chart_posts
    set pdf_provenance_status = 'validated',
        pdf_validated_at = now()
    where id = target_post_id
        and exists (
            select 1
            from storage.objects
            where bucket_id = 'forum_chart_pdfs'
                and name = forum_chart_posts.pdf_storage_path
                and storage.extension(name) = 'pdf'
        );
end;
$$;

revoke all on function private.finalize_forum_chart_post_pdf(uuid) from public, anon, authenticated;

alter policy "forum_songs_select_active_pro"
    on public.forum_songs
    using (
        (select public.current_user_has_active_pro())
        and (
            created_by = (select auth.uid())
            or exists (
                select 1
                from public.forum_chart_posts
                where forum_chart_posts.song_id = forum_songs.id
                    and forum_chart_posts.status in ('published', 'flagged')
            )
            or exists (
                select 1
                from public.forum_chart_posts
                where forum_chart_posts.song_id = forum_songs.id
                    and forum_chart_posts.status = 'pending'
                    and forum_chart_posts.owner_id = (select auth.uid())
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
        and pdf_provenance_status = 'pending'
        and pdf_validated_at is null
        and pdf_storage_path = owner_id::text || '/' || id::text || '.pdf'
        and private.forum_song_exists(forum_chart_posts.song_id)
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
                and forum_chart_posts.pdf_provenance_status = 'validated'
        )
    );
