-- Setlist snapshots and their PDFs are private to one verified paid owner.
-- Paid-through cancellation still grants access; grace and beta-only access do not.
create table private.pdf_setlist_deletion_fences (
    owner_id uuid primary key references auth.users(id) on delete cascade,
    requested_at timestamptz not null default now()
);
alter table private.pdf_setlist_deletion_fences enable row level security;
revoke all on table private.pdf_setlist_deletion_fences from public, anon, authenticated, service_role;

create function private.current_user_has_paid_setlist_cloud()
returns boolean language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from auth.users users
        join public.subscriptions subscription on subscription.owner_id = users.id
        where users.id = (select auth.uid())
            and users.deleted_at is null and users.is_anonymous is not true
            and (users.banned_until is null or users.banned_until <= now())
            and (users.email_confirmed_at is not null or users.phone_confirmed_at is not null)
            and subscription.provider = 'storekit'
            and subscription.plan = 'studioSubscription' and subscription.status = 'active'
            and subscription.app_store_status = 'active'
            and subscription.entitlement_expires_at > now()
            and subscription.revoked_at is null and subscription.last_verified_at is not null
            and not exists (select 1 from private.pdf_setlist_deletion_fences fence where fence.owner_id = users.id)
    );
$$;
revoke all on function private.current_user_has_paid_setlist_cloud() from public, anon, authenticated, service_role;
grant execute on function private.current_user_has_paid_setlist_cloud() to anon, authenticated;
create function public.current_user_has_paid_setlist_cloud()
returns boolean language sql stable security invoker set search_path = ''
begin atomic
    select private.current_user_has_paid_setlist_cloud();
end;
revoke all on function public.current_user_has_paid_setlist_cloud() from public, anon, service_role;
grant execute on function public.current_user_has_paid_setlist_cloud() to anon, authenticated;

-- Hold shared authorization until the storage transaction finishes. Account
-- deletion takes the exclusive owner lock before inventorying PDF objects.
create function private.authorize_pdf_setlist_storage()
returns boolean language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_owner uuid := auth.uid();
begin
    if v_owner is null then return false; end if;
    perform pg_advisory_xact_lock_shared(hashtextextended('pdf-setlist:' || v_owner::text, 0));
    return private.current_user_has_paid_setlist_cloud();
end;
$$;
revoke all on function private.authorize_pdf_setlist_storage() from public, anon, authenticated, service_role;
grant execute on function private.authorize_pdf_setlist_storage() to anon, authenticated;
create function public.authorize_pdf_setlist_storage()
returns boolean language sql volatile security invoker set search_path = ''
begin atomic
    select private.authorize_pdf_setlist_storage();
end;
revoke all on function public.authorize_pdf_setlist_storage() from public, anon, service_role;
grant execute on function public.authorize_pdf_setlist_storage() to anon, authenticated;

create table private.pdf_setlist_backups (
    owner_id uuid primary key references auth.users(id) on delete cascade,
    version bigint not null check (version > 0),
    manifest jsonb not null check (octet_length(manifest::text) <= 10485760),
    updated_at timestamptz not null default now()
);
alter table private.pdf_setlist_backups enable row level security;
revoke all on table private.pdf_setlist_backups from public, anon, authenticated, service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('setlist-pdfs', 'setlist-pdfs', false, 52428800, array['application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- A restrictive boundary also applies if another bucket has a permissive policy.
create policy setlist_pdf_owner_boundary on storage.objects as restrictive for all to public
using (bucket_id <> 'setlist-pdfs' or (
    (select public.authorize_pdf_setlist_storage())
    and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f]{64}\.pdf$')
))
with check (bucket_id <> 'setlist-pdfs' or (
    (select public.authorize_pdf_setlist_storage())
    and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f]{64}\.pdf$')
));
create policy setlist_pdf_read_own on storage.objects for select to authenticated
using (bucket_id = 'setlist-pdfs' and (select public.authorize_pdf_setlist_storage())
    and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f]{64}\.pdf$'));
create policy setlist_pdf_insert_own on storage.objects for insert to authenticated
with check (bucket_id = 'setlist-pdfs' and (select public.authorize_pdf_setlist_storage())
    and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f]{64}\.pdf$'));
-- Content paths are immutable. A client conflict cannot replace or delete prior PDFs.
create policy setlist_pdf_no_update on storage.objects as restrictive for update to public
using (bucket_id <> 'setlist-pdfs') with check (bucket_id <> 'setlist-pdfs');
create policy setlist_pdf_no_delete on storage.objects as restrictive for delete to public
using (bucket_id <> 'setlist-pdfs');

create function private.get_pdf_setlist_backup(expected_owner_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
    v_owner uuid := auth.uid();
    current_snapshot private.pdf_setlist_backups%rowtype;
begin
    if v_owner is null or v_owner is distinct from expected_owner_id
        or not public.current_user_has_paid_setlist_cloud() then
        raise exception 'Verified paid Pro access is required for setlist cloud backup.' using errcode = '42501';
    end if;
    select * into current_snapshot from private.pdf_setlist_backups where owner_id = v_owner;
    return jsonb_build_object('version', coalesce(current_snapshot.version, 0),
        'manifest', current_snapshot.manifest);
end;
$$;
revoke all on function private.get_pdf_setlist_backup(uuid) from public, anon, authenticated, service_role;
grant execute on function private.get_pdf_setlist_backup(uuid) to authenticated;

create function private.commit_pdf_setlist_backup(expected_owner_id uuid, expected_version bigint, manifest jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
    v_owner uuid := auth.uid();
    current_snapshot private.pdf_setlist_backups%rowtype;
    pdf jsonb;
    list jsonb;
    entry jsonb;
    pdf_id text;
    content_digest text;
    byte_count numeric;
    next_version bigint;
begin
    if v_owner is null or v_owner is distinct from expected_owner_id
        or not public.current_user_has_paid_setlist_cloud() then
        raise exception 'Verified paid Pro access is required for setlist cloud backup.' using errcode = '42501';
    end if;
    if expected_version is null or expected_version < 0 or expected_version >= 9223372036854775807 then
        raise exception 'A valid base version is required.' using errcode = '22023';
    end if;
    if manifest is null or jsonb_typeof(manifest) <> 'object'
        or manifest->'schema_version' is distinct from '1'::jsonb
        or jsonb_typeof(manifest->'setlists') is distinct from 'array'
        or jsonb_typeof(manifest->'pdfs') is distinct from 'array'
        or octet_length(manifest::text) > 10485760 then
        raise exception 'Invalid setlist backup manifest.' using errcode = '22023';
    end if;
    if exists (select 1 from jsonb_array_elements(manifest->'pdfs') p
        group by lower(p->>'id') having count(*) > 1) then
        raise exception 'PDF identifiers must be unique.' using errcode = '22023';
    end if;
    for pdf in select value from jsonb_array_elements(manifest->'pdfs') loop
        pdf_id := pdf->>'id';
        content_digest := pdf->>'content_sha256';
        if jsonb_typeof(pdf) <> 'object'
            or coalesce(pdf_id, '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            or coalesce(content_digest, '') !~ '^[0-9a-f]{64}$'
            or jsonb_typeof(pdf->'file_size_bytes') is distinct from 'number'
            or coalesce(pdf->>'file_size_bytes', '') !~ '^[0-9]+$'
            or jsonb_typeof(pdf->'item') is distinct from 'object'
            or lower(coalesce(pdf->'item'->>'id', '')) <> lower(pdf_id) then
            raise exception 'Invalid PDF manifest record.' using errcode = '22023';
        end if;
        byte_count := (pdf->>'file_size_bytes')::numeric;
        if byte_count < 1 or byte_count > 52428800 or not exists (
            select 1 from storage.objects objects
            where objects.bucket_id = 'setlist-pdfs'
                and objects.name = v_owner::text || '/' || content_digest || '.pdf'
                and objects.metadata->>'mimetype' = 'application/pdf'
                and coalesce(objects.metadata->>'size', '') ~ '^[0-9]+$'
                and (objects.metadata->>'size')::numeric = byte_count
        ) then
            raise exception 'Upload the complete PDF before saving its setlist.' using errcode = '22023';
        end if;
    end loop;
    if exists (select 1 from jsonb_array_elements(manifest->'setlists') s
        group by lower(s->>'id') having count(*) > 1) then
        raise exception 'Setlist identifiers must be unique.' using errcode = '22023';
    end if;
    for list in select value from jsonb_array_elements(manifest->'setlists') loop
        if jsonb_typeof(list) <> 'object'
            or coalesce(list->>'id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            or jsonb_typeof(list->'entries') is distinct from 'array' then
            raise exception 'Invalid setlist record.' using errcode = '22023';
        end if;
        for entry in select value from jsonb_array_elements(list->'entries') loop
            if jsonb_typeof(entry) <> 'object' or not exists (
                select 1 from jsonb_array_elements(manifest->'pdfs') p
                where lower(p->>'id') = lower(entry->>'pdfItemID')
            ) then
                raise exception 'A setlist references an unavailable PDF.' using errcode = '22023';
            end if;
        end loop;
    end loop;
    -- Serialize first creation and subsequent CAS commits for this owner only.
    perform pg_advisory_xact_lock(hashtextextended('pdf-setlist:' || v_owner::text, 0));
    if not public.current_user_has_paid_setlist_cloud() then
        raise exception 'Setlist cloud backup is unavailable for this account.' using errcode = '42501';
    end if;
    select * into current_snapshot from private.pdf_setlist_backups where owner_id = v_owner;
    if current_snapshot.manifest = manifest then
        return jsonb_build_object('version', current_snapshot.version, 'manifest', current_snapshot.manifest);
    end if;
    if coalesce(current_snapshot.version, 0) <> expected_version then
        raise exception 'The cloud setlist backup changed. Review both copies before retrying.' using errcode = '40001';
    end if;
    next_version := expected_version + 1;
    insert into private.pdf_setlist_backups(owner_id, version, manifest, updated_at)
    values (v_owner, next_version, manifest, now())
    on conflict (owner_id) do update set version = excluded.version, manifest = excluded.manifest,
        updated_at = excluded.updated_at;
    return jsonb_build_object('version', next_version, 'manifest', manifest);
end;
$$;
revoke all on function private.commit_pdf_setlist_backup(uuid, bigint, jsonb) from public, anon, authenticated, service_role;
grant execute on function private.commit_pdf_setlist_backup(uuid, bigint, jsonb) to authenticated;

-- Parse SQL bodies when created. The public invoker wrappers hold resolved
-- references to private functions without granting private-schema USAGE.
create function public.get_pdf_setlist_backup(expected_owner_id uuid)
returns jsonb language sql security invoker set search_path = ''
begin atomic
    select private.get_pdf_setlist_backup(expected_owner_id);
end;
revoke all on function public.get_pdf_setlist_backup(uuid) from public, anon, service_role;
grant execute on function public.get_pdf_setlist_backup(uuid) to authenticated;

create function public.commit_pdf_setlist_backup(expected_owner_id uuid, expected_version bigint, manifest jsonb)
returns jsonb language sql security invoker set search_path = ''
begin atomic
    select private.commit_pdf_setlist_backup(expected_owner_id, expected_version, manifest);
end;
revoke all on function public.commit_pdf_setlist_backup(uuid, bigint, jsonb) from public, anon, service_role;
grant execute on function public.commit_pdf_setlist_backup(uuid, bigint, jsonb) to authenticated;

create function private.begin_pdf_setlist_account_deletion(target_owner_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
    if target_owner_id is null or not exists (select 1 from auth.users where id = target_owner_id) then
        raise exception 'A current owner is required.' using errcode = '22023';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('pdf-setlist:' || target_owner_id::text, 0));
    insert into private.pdf_setlist_deletion_fences(owner_id) values (target_owner_id) on conflict do nothing;
    return jsonb_build_object('owner_id', target_owner_id, 'bucket', 'setlist-pdfs',
        'prefix', target_owner_id::text || '/');
end;
$$;
revoke all on function private.begin_pdf_setlist_account_deletion(uuid) from public, anon, authenticated, service_role;
grant execute on function private.begin_pdf_setlist_account_deletion(uuid) to service_role;

create function public.begin_pdf_setlist_account_deletion(target_owner_id uuid)
returns jsonb language sql security invoker set search_path = ''
begin atomic
    select private.begin_pdf_setlist_account_deletion(target_owner_id);
end;
revoke all on function public.begin_pdf_setlist_account_deletion(uuid) from public, anon, authenticated, service_role;
grant execute on function public.begin_pdf_setlist_account_deletion(uuid) to service_role;
