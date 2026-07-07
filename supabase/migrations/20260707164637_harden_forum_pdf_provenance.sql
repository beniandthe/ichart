create table if not exists private.forum_chart_pdf_provenance (
    post_id uuid primary key references public.forum_chart_posts(id) on delete cascade,
    storage_object_id uuid not null unique,
    storage_path text not null unique,
    owner_id uuid not null references auth.users(id) on delete cascade,
    byte_size bigint not null check (byte_size > 0 and byte_size <= 10485760),
    sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
    validated_at timestamptz not null default now(),
    validated_by text not null default 'service_role',
    check (storage_path = owner_id::text || '/' || post_id::text || '.pdf')
);

revoke all on table private.forum_chart_pdf_provenance from public, anon, authenticated;
grant usage on schema private to service_role;
grant select, insert, update, delete on table private.forum_chart_pdf_provenance to service_role;

create or replace function private.forum_pdf_has_valid_provenance(
    target_post_id uuid,
    target_storage_object_id uuid,
    target_storage_path text,
    target_owner_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = private, public, pg_temp
as $$
    select exists (
        select 1
        from private.forum_chart_pdf_provenance provenance
        where provenance.post_id = target_post_id
            and provenance.storage_object_id = target_storage_object_id
            and provenance.storage_path = target_storage_path
            and provenance.owner_id = target_owner_id
    );
$$;

revoke all on function private.forum_pdf_has_valid_provenance(uuid, uuid, text, uuid)
    from public, anon, authenticated;
grant execute on function private.forum_pdf_has_valid_provenance(uuid, uuid, text, uuid)
    to authenticated;

create or replace function private.current_user_unattached_forum_pdf_upload_count()
returns integer
language sql
stable
security definer
set search_path = public, storage, private, pg_temp
as $$
    select count(*)::integer
    from storage.objects existing_object
    where existing_object.bucket_id = 'forum_chart_pdfs'
        and (storage.foldername(existing_object.name))[1] = (select auth.uid())::text
        and not exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.pdf_storage_path = existing_object.name
        );
$$;

revoke all on function private.current_user_unattached_forum_pdf_upload_count()
    from public, anon, authenticated;
grant execute on function private.current_user_unattached_forum_pdf_upload_count()
    to authenticated;

alter policy "forum_chart_pdfs_insert_active_pro_owner_folder"
    on storage.objects
    with check (
        bucket_id = 'forum_chart_pdfs'
        and (select public.current_user_has_active_pro())
        and (storage.foldername(name))[1] = (select auth.uid())::text
        and storage.extension(name) = 'pdf'
        and (
            exists (
                select 1
                from public.forum_chart_posts
                where forum_chart_posts.pdf_storage_path = storage.objects.name
                    and forum_chart_posts.owner_id = (select auth.uid())
                    and forum_chart_posts.status = 'pending'
            )
            -- INSERT policy checks can see the candidate row, so <= 3 permits
            -- at most three unattached rollback-buffer PDFs for the owner.
            or private.current_user_unattached_forum_pdf_upload_count() <= 3
        )
    );

drop function if exists private.finalize_forum_chart_post_pdf(uuid);

create or replace function private.finalize_forum_chart_post_pdf(
    target_post_id uuid,
    target_byte_size bigint,
    target_sha256 text
)
returns void
language plpgsql
security definer
set search_path = public, storage, private, pg_temp
as $$
declare
    post_record public.forum_chart_posts%rowtype;
    storage_object_id uuid;
    normalized_sha256 text;
begin
    normalized_sha256 := lower(btrim(coalesce(target_sha256, '')));

    if target_byte_size is null or target_byte_size <= 0 or target_byte_size > 10485760 then
        raise exception 'Forum PDF finalization requires a valid byte size.';
    end if;

    if normalized_sha256 !~ '^[a-f0-9]{64}$' then
        raise exception 'Forum PDF finalization requires a SHA-256 provenance digest.';
    end if;

    select *
    into post_record
    from public.forum_chart_posts
    where id = target_post_id
    for update;

    if not found then
        raise exception 'Forum post does not exist.';
    end if;

    select id
    into storage_object_id
    from storage.objects
    where bucket_id = 'forum_chart_pdfs'
        and name = post_record.pdf_storage_path
        and storage.extension(name) = 'pdf';

    if not found then
        raise exception 'Forum PDF storage object does not match the submitted post.';
    end if;

    insert into private.forum_chart_pdf_provenance (
        post_id,
        storage_object_id,
        storage_path,
        owner_id,
        byte_size,
        sha256,
        validated_at,
        validated_by
    ) values (
        post_record.id,
        storage_object_id,
        post_record.pdf_storage_path,
        post_record.owner_id,
        target_byte_size,
        normalized_sha256,
        now(),
        'service_role'
    )
    on conflict (post_id) do update
    set storage_object_id = excluded.storage_object_id,
        storage_path = excluded.storage_path,
        owner_id = excluded.owner_id,
        byte_size = excluded.byte_size,
        sha256 = excluded.sha256,
        validated_at = excluded.validated_at,
        validated_by = excluded.validated_by;

    update public.forum_chart_posts
    set pdf_provenance_status = 'validated',
        pdf_validated_at = now()
    where id = post_record.id
        and pdf_storage_path = post_record.pdf_storage_path;
end;
$$;

revoke all on function private.finalize_forum_chart_post_pdf(uuid, bigint, text)
    from public, anon, authenticated;
grant execute on function private.finalize_forum_chart_post_pdf(uuid, bigint, text)
    to service_role;

create or replace function public.finalize_forum_chart_post_pdf(
    target_post_id uuid,
    target_byte_size bigint,
    target_sha256 text
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
    perform private.finalize_forum_chart_post_pdf(
        target_post_id,
        target_byte_size,
        target_sha256
    );
end;
$$;

revoke all on function public.finalize_forum_chart_post_pdf(uuid, bigint, text)
    from public, anon, authenticated;
grant execute on function public.finalize_forum_chart_post_pdf(uuid, bigint, text)
    to service_role;

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
                and private.forum_pdf_has_valid_provenance(
                    forum_chart_posts.id,
                    storage.objects.id,
                    storage.objects.name,
                    forum_chart_posts.owner_id
                )
        )
    );
