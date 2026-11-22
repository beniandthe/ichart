-- A stale expected_version is a deterministic application conflict. Raising
-- serialization_failure (40001) makes hosted PostgREST 14 retry indefinitely.
-- PT409 returns HTTP 409 once. Genuine StoreKit serialization races are separate.
-- Keep the applied 1720 migration immutable, and retain this function's OID,
-- signature, SECURITY DEFINER, fixed search_path and existing EXECUTE grants.

create or replace function private.commit_pdf_setlist_backup(expected_owner_id uuid, expected_version bigint, manifest jsonb)
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
        raise exception 'The cloud setlist backup changed. Review both copies before retrying.' using errcode = 'PT409';
    end if;
    next_version := expected_version + 1;
    insert into private.pdf_setlist_backups(owner_id, version, manifest, updated_at)
    values (v_owner, next_version, manifest, now())
    on conflict (owner_id) do update set version = excluded.version, manifest = excluded.manifest,
        updated_at = excluded.updated_at;
    return jsonb_build_object('version', next_version, 'manifest', manifest);
end;
$$;
