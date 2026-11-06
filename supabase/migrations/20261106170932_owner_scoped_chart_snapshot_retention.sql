-- Owner-scoped, archive-gated historical snapshot retention. No owner is seeded.
-- Operator must privately configure the one authorized UUID; all client grants
-- remain unchanged. No job/secret/bucket is created by this migration.
begin;
set local lock_timeout='5s';
-- Fail-safe deny overrides any broad permissive client Storage policy for this
-- new private archive bucket only. Other bucket rows evaluate TRUE unchanged.
create policy ichart_owner_archive_deny_clients on storage.objects as restrictive
 for all to anon,authenticated
 using(bucket_id is distinct from 'ichart-owner-snapshot-archives')
 with check(bucket_id is distinct from 'ichart-owner-snapshot-archives');
create schema ichart_snapshot_retention;
revoke all on schema ichart_snapshot_retention from public,anon,authenticated,service_role;
grant usage on schema ichart_snapshot_retention to service_role;
create table ichart_snapshot_retention.policy (
 singleton boolean primary key default true check(singleton),
 owner_id uuid not null unique references auth.users(id) on delete cascade,
 enabled boolean not null default false,
 deletion_requested_at timestamptz,
 check(deletion_requested_at is null or not enabled),
 bucket text not null check(bucket='ichart-owner-snapshot-archives'),
 max_batch_rows integer not null default 100 check(max_batch_rows between 1 and 500),
 max_batch_bytes bigint not null default 8388608 check(max_batch_bytes between 1024 and 33554432),
 daily_max_rows integer not null default 30000 check(daily_max_rows between 1 and 100000),
 initial_archive_cutoff_at timestamptz not null default clock_timestamp(),
 initial_restore_verified_at timestamptz,
 initial_restore_manifest_sha256 text check(initial_restore_manifest_sha256 ~ '^[0-9a-f]{64}$'),
 check((initial_restore_verified_at is null)=(initial_restore_manifest_sha256 is null))
);
create table ichart_snapshot_retention.archive_batches (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references ichart_snapshot_retention.policy(owner_id) on delete cascade,
 bucket text not null, object_key text not null unique,
 hash_version text not null default 'pg-jsonb-row-utc-v1' check(hash_version='pg-jsonb-row-utc-v1'),
 mode text not null check(mode in ('initial','retention')),
 state text not null default 'planned' check(state in ('planned','verified','completed','expired')),
 manifest_sha256 text not null check(manifest_sha256 ~ '^[0-9a-f]{64}$'),
 row_count integer not null check(row_count between 1 and 500), uncompressed_bytes bigint not null check(uncompressed_bytes between 1 and 33554432),
 archive_sha256 text check(archive_sha256 ~ '^[0-9a-f]{64}$'), archive_bytes bigint,
 created_at timestamptz not null default clock_timestamp(), lease_expires_at timestamptz,
 verified_at timestamptz, completed_at timestamptz,
 unique(id,owner_id),
 check((verified_at is null and archive_sha256 is null and archive_bytes is null)
  or (verified_at is not null and archive_sha256 is not null and archive_bytes>0))
);
create table ichart_snapshot_retention.archive_items (
 batch_id uuid not null, owner_id uuid not null, snapshot_id uuid not null,
 row_sha256 text not null check(row_sha256 ~ '^[0-9a-f]{64}$'), invalidated_at timestamptz,
 primary key(batch_id,snapshot_id),
 foreign key(batch_id,owner_id) references ichart_snapshot_retention.archive_batches(id,owner_id) on delete cascade
);
create index archive_items_snapshot_idx on ichart_snapshot_retention.archive_items(snapshot_id,owner_id);
create table ichart_snapshot_retention.initial_inventory (
 owner_id uuid not null references ichart_snapshot_retention.policy(owner_id) on delete cascade,
 snapshot_id uuid not null, primary key(owner_id,snapshot_id)
);
create table ichart_snapshot_retention.head_pins (
 snapshot_id uuid primary key references public.chart_snapshots(id) on delete cascade,
 owner_id uuid not null references ichart_snapshot_retention.policy(owner_id) on delete cascade,
 retain_until timestamptz not null
);
-- Explicitly undo default grants on ALL new objects. Policy fields remain
-- operator-only; service functions cannot change their own authorization scope.
revoke all on all tables in schema ichart_snapshot_retention from public,anon,authenticated,service_role;
alter table ichart_snapshot_retention.policy enable row level security;
alter table ichart_snapshot_retention.archive_batches enable row level security;
alter table ichart_snapshot_retention.archive_items enable row level security;
alter table ichart_snapshot_retention.head_pins enable row level security;
alter table ichart_snapshot_retention.initial_inventory enable row level security;
grant select on ichart_snapshot_retention.policy,ichart_snapshot_retention.initial_inventory to service_role;
grant select,insert,update on ichart_snapshot_retention.archive_batches,ichart_snapshot_retention.archive_items to service_role;
grant select on ichart_snapshot_retention.head_pins to service_role;

create function ichart_snapshot_retention.guard_service() returns void
language plpgsql security invoker set search_path=pg_catalog as $$ begin
 if current_user<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 if current_setting('transaction_isolation')<>'read committed' then
  raise exception 'Retention requires READ COMMITTED fresh statement snapshots'; end if;
 if (select array_agg(a.attname::text order by a.attnum) from pg_attribute a
  where a.attrelid='public.chart_snapshots'::regclass and a.attnum>0 and not a.attisdropped)
  is distinct from array['id','chart_id','owner_id','version','chart_json','client_updated_at','created_at']::text[] then
  raise exception 'Snapshot archive schema changed; review hash/restore format first'; end if;
end $$;
create function ichart_snapshot_retention.row_text(s public.chart_snapshots) returns text
language plpgsql volatile security invoker set search_path=pg_catalog set timezone='UTC'
as $$ begin
 if (s).owner_id is distinct from (select owner_id from ichart_snapshot_retention.policy where singleton) then
  raise exception 'Archive hashing is confined to configured owner'; end if;
 return to_jsonb(s)::text;
end $$;
create function ichart_snapshot_retention.row_sha256(s public.chart_snapshots) returns text
language sql volatile security invoker set search_path=pg_catalog set timezone='UTC'
as $$ select encode(extensions.digest(convert_to(ichart_snapshot_retention.row_text(s),'UTF8'),'sha256'),'hex') $$;

-- One job namespace, no ordinary account/writer uses this advisory lock.
-- Policy changes acquire the same lock before changing authorization/gates.
create function ichart_snapshot_retention.policy_guard() returns trigger
language plpgsql security definer set search_path=pg_catalog set timezone='UTC' as $$ begin
 -- Account/config deletion must not wait on the job lock while holding a
 -- parent FK row lock: let it win; an overlapping planner then fails its FK.
 if TG_OP='DELETE' then return OLD; end if;
 if TG_OP='INSERT' and NEW.initial_restore_verified_at is not null then
  raise exception 'Initial restore verification cannot be preseeded'; end if;
 if TG_OP='UPDATE' and (NEW.owner_id is distinct from OLD.owner_id
  or NEW.initial_archive_cutoff_at is distinct from OLD.initial_archive_cutoff_at) then
  raise exception 'Owner scope/bootstrap cutoff are immutable; create a separately reviewed migration'; end if;
 if TG_OP='UPDATE' and OLD.initial_restore_verified_at is not null
  and (NEW.initial_restore_verified_at is distinct from OLD.initial_restore_verified_at
   or NEW.initial_restore_manifest_sha256 is distinct from OLD.initial_restore_manifest_sha256) then
  raise exception 'Initial restore proof is immutable; disable policy instead'; end if;
 perform pg_advisory_xact_lock(1801675876,1);
 if TG_OP<>'DELETE' and NEW.initial_restore_verified_at is not null
  and (TG_OP='INSERT' or OLD.initial_restore_verified_at is null) then
  if exists(select 1 from ichart_snapshot_retention.initial_inventory inv where inv.owner_id=NEW.owner_id
    and not exists(select 1 from ichart_snapshot_retention.archive_items i
      join ichart_snapshot_retention.archive_batches b on b.id=i.batch_id
     where i.owner_id=NEW.owner_id and i.snapshot_id=inv.snapshot_id and i.invalidated_at is null
      and b.verified_at is not null)) then
   raise exception 'Initial owner snapshot archive is incomplete or changed'; end if;
 end if;
 if TG_OP='DELETE' then return OLD; end if;
 return NEW;
end $$;
create trigger owner_retention_policy_guard before insert or update or delete
 on ichart_snapshot_retention.policy for each row execute function ichart_snapshot_retention.policy_guard();
create function ichart_snapshot_retention.seed_heads() returns trigger
language plpgsql security definer set search_path=pg_catalog set timezone='UTC' as $$ begin
 insert into ichart_snapshot_retention.initial_inventory(owner_id,snapshot_id)
 select NEW.owner_id,s.id from public.chart_snapshots s where s.owner_id=NEW.owner_id
  and s.created_at<=NEW.initial_archive_cutoff_at;
 insert into ichart_snapshot_retention.head_pins(snapshot_id,owner_id,retain_until)
 select d.latest_snapshot_id,NEW.owner_id,clock_timestamp()+interval '24 hours'
 from public.chart_documents d join public.chart_snapshots s on s.id=d.latest_snapshot_id
 where d.owner_id=NEW.owner_id and s.owner_id=NEW.owner_id
 on conflict(snapshot_id) do update set retain_until=greatest(head_pins.retain_until,excluded.retain_until);
 return NEW;
end $$;
create trigger owner_retention_seed_heads after insert on ichart_snapshot_retention.policy
 for each row execute function ichart_snapshot_retention.seed_heads();
create function ichart_snapshot_retention.track_retired_head() returns trigger
language plpgsql security definer set search_path=pg_catalog set timezone='UTC' as $$ begin
 if OLD.latest_snapshot_id is not null and OLD.latest_snapshot_id is distinct from NEW.latest_snapshot_id
  and exists(select 1 from ichart_snapshot_retention.policy p where p.owner_id=OLD.owner_id) then
  insert into ichart_snapshot_retention.head_pins(snapshot_id,owner_id,retain_until)
   select s.id,OLD.owner_id,clock_timestamp()+interval '24 hours'
   from public.chart_snapshots s where s.id=OLD.latest_snapshot_id and s.owner_id=OLD.owner_id
  on conflict(snapshot_id) do update set retain_until=greatest(head_pins.retain_until,excluded.retain_until);
 end if;
 return NEW;
end $$;
create trigger owner_retention_retired_head after update of latest_snapshot_id on public.chart_documents
 for each row execute function ichart_snapshot_retention.track_retired_head();
create function ichart_snapshot_retention.invalidate_changed_receipts() returns trigger
language plpgsql security definer set search_path=pg_catalog set timezone='UTC' as $$
declare scoped_owner uuid;
begin
 select owner_id into scoped_owner from ichart_snapshot_retention.policy where singleton;
 if scoped_owner is null then return NEW; end if;
 if TG_OP='INSERT' then
  if NEW.owner_id=scoped_owner then
   update ichart_snapshot_retention.archive_items set invalidated_at=clock_timestamp()
    where owner_id=scoped_owner and snapshot_id=NEW.id and invalidated_at is null;
  end if;
  return NEW;
 end if;
 -- Decide scope from UUID metadata BEFORE reading any stored JSON payload.
 if OLD.owner_id=scoped_owner then
  if NEW.owner_id is distinct from OLD.owner_id then
   update ichart_snapshot_retention.archive_items set invalidated_at=clock_timestamp()
    where owner_id=scoped_owner and snapshot_id=OLD.id and invalidated_at is null;
  elsif to_jsonb(OLD) is distinct from to_jsonb(NEW) then
   update ichart_snapshot_retention.archive_items set invalidated_at=clock_timestamp()
    where owner_id=scoped_owner and snapshot_id=OLD.id and invalidated_at is null;
  end if;
 elsif NEW.owner_id=scoped_owner then
  update ichart_snapshot_retention.archive_items set invalidated_at=clock_timestamp()
   where owner_id=scoped_owner and snapshot_id=NEW.id and invalidated_at is null;
 end if;
 return NEW;
end $$;
create trigger owner_retention_invalidate_receipt after insert or update on public.chart_snapshots
 for each row execute function ichart_snapshot_retention.invalidate_changed_receipts();

create function ichart_snapshot_retention.keeper_ids(p_owner uuid,p_asof timestamptz)
returns setof uuid language plpgsql volatile security invoker set search_path=pg_catalog set timezone='UTC' as $$ begin
 if p_owner is distinct from (select owner_id from ichart_snapshot_retention.policy where singleton) then
  raise exception 'Retention metadata is confined to configured owner'; end if;
 return query with ranked as (
  select s.id,row_number() over(partition by s.chart_id order by s.version desc,s.id desc) rn
  from public.chart_snapshots s where s.owner_id=p_owner
 ), daily as (
  select s.id,row_number() over(partition by s.chart_id,(s.created_at at time zone 'UTC')::date
   order by s.created_at desc,s.version desc,s.id desc) rn
  from public.chart_snapshots s where s.owner_id=p_owner
   and s.created_at>=date_trunc('day',p_asof)-interval '29 days'
 ), fallback as (
  select distinct on(d.id) s.id from public.chart_documents d join public.chart_snapshots s
   on s.chart_id=d.id and s.owner_id=d.owner_id
  where d.owner_id=p_owner and d.deleted_at is null and d.latest_snapshot_id is null
  order by d.id,s.version desc,s.id desc
 )
 select latest_snapshot_id from public.chart_documents where latest_snapshot_id is not null
 union select id from ranked where rn<=10
 union select id from daily where rn=1
 union select id from fallback
 union select id from public.chart_snapshots where owner_id=p_owner and created_at>=p_asof-interval '24 hours'
 union select snapshot_id from ichart_snapshot_retention.head_pins where owner_id=p_owner and retain_until>=p_asof;
end $$;

create function public.owner_snapshot_retention_status() returns jsonb
language plpgsql security invoker set search_path=pg_catalog set timezone='UTC' as $$
declare p ichart_snapshot_retention.policy%rowtype; remaining bigint;
begin
 perform ichart_snapshot_retention.guard_service();
 select * into p from ichart_snapshot_retention.policy where singleton;
 if not found then return jsonb_build_object('enabled',false,'status','unconfigured'); end if;
 select count(*) into remaining from ichart_snapshot_retention.initial_inventory s where s.owner_id=p.owner_id
  and not exists(
   select 1 from ichart_snapshot_retention.archive_items i join ichart_snapshot_retention.archive_batches b on b.id=i.batch_id
   where i.snapshot_id=s.snapshot_id and i.owner_id=p.owner_id and i.invalidated_at is null and b.verified_at is not null);
 return jsonb_build_object('enabled',p.enabled,'owner_id',p.owner_id,'bucket',p.bucket,
  'max_batch_rows',p.max_batch_rows,'max_batch_bytes',p.max_batch_bytes,'daily_max_rows',p.daily_max_rows,
  'initial_archive_cutoff_at',p.initial_archive_cutoff_at,'initial_remaining_rows',remaining,
  'initial_restore_verified',p.initial_restore_verified_at is not null);
end $$;

create function public.plan_owner_snapshot_retention(p_limit integer default 100) returns jsonb
language plpgsql security invoker set search_path=pg_catalog set timezone='UTC' as $$
declare p ichart_snapshot_retention.policy%rowtype; b ichart_snapshot_retention.archive_batches%rowtype;
 v_now timestamptz:=clock_timestamp(); v_limit integer; v_used bigint; v_rows jsonb;
 v_count integer; v_bytes bigint; v_manifest text; v_id uuid:=gen_random_uuid(); v_mode text;
 v_snapshot public.chart_snapshots; v_text text; v_sha text; v_length bigint;
begin
 perform ichart_snapshot_retention.guard_service();
 perform pg_advisory_xact_lock(1801675876,1);
 select * into p from ichart_snapshot_retention.policy where singleton;
 if not found or not p.enabled then return jsonb_build_object('status','disabled'); end if;
 if p_limit is null or p_limit<1 or p_limit>500 then raise exception 'Invalid batch limit'; end if;
 update ichart_snapshot_retention.archive_batches set state='expired',lease_expires_at=null
  where owner_id=p.owner_id and state='planned' and lease_expires_at<=v_now;
 if exists(select 1 from ichart_snapshot_retention.archive_batches where owner_id=p.owner_id and lease_expires_at>v_now) then
  return jsonb_build_object('status','busy'); end if;
 -- A previously archived checkpoint can become eligible later. Reuse its
 -- immutable file, but the worker must GET+verify it again before finalizing.
 if p.initial_restore_verified_at is not null then
  select ab.* into b from ichart_snapshot_retention.archive_batches ab
  where ab.owner_id=p.owner_id and ab.verified_at is not null and exists(
   select 1 from ichart_snapshot_retention.archive_items i join public.chart_snapshots s on s.id=i.snapshot_id
   where i.batch_id=ab.id and i.invalidated_at is null and s.owner_id=p.owner_id
    and not exists(select 1 from ichart_snapshot_retention.keeper_ids(p.owner_id,v_now) k where k=s.id))
  order by ab.created_at,ab.id limit 1;
  if found then
   update ichart_snapshot_retention.archive_batches set lease_expires_at=v_now+interval '1 hour' where id=b.id;
   select jsonb_agg(jsonb_build_object('snapshot_id',i.snapshot_id,'row_sha256',i.row_sha256,'row_text',null) order by i.snapshot_id)
    into v_rows from ichart_snapshot_retention.archive_items i where i.batch_id=b.id;
   return jsonb_build_object('status','verified','batch_id',b.id,'owner_id',p.owner_id,'bucket',b.bucket,
    'object_key',b.object_key,'manifest_sha256',b.manifest_sha256,'row_count',b.row_count,
    'uncompressed_bytes',b.uncompressed_bytes,'rows',v_rows,'archive_sha256',b.archive_sha256,
    'archive_bytes',b.archive_bytes,'initial_restore_verified',true,'expires_at',v_now+interval '1 hour');
  end if;
 end if;
 select coalesce(sum(row_count),0) into v_used from ichart_snapshot_retention.archive_batches
  where owner_id=p.owner_id and created_at>=date_trunc('day',v_now);
 v_limit:=least(p_limit,p.max_batch_rows,greatest(p.daily_max_rows-v_used,0)::integer);
 if v_limit=0 then return jsonb_build_object('status','daily_limit'); end if;
 v_mode:=case when p.initial_restore_verified_at is null then 'initial' else 'retention' end;
 v_rows:='[]'::jsonb; v_count:=0; v_bytes:=0;
 -- Encode incrementally: do not detoast/serialize a whole large candidate page
 -- merely to discover that its accumulated response exceeds the byte budget.
 for v_snapshot in
  select s.* from public.chart_snapshots s join public.chart_documents d on d.id=s.chart_id and d.owner_id=s.owner_id
  where s.owner_id=p.owner_id
   and ((v_mode='initial' and exists(select 1 from ichart_snapshot_retention.initial_inventory inv
       where inv.owner_id=p.owner_id and inv.snapshot_id=s.id))
     or (v_mode='retention' and not exists(select 1 from ichart_snapshot_retention.keeper_ids(p.owner_id,v_now) k where k=s.id)))
   and not exists(select 1 from ichart_snapshot_retention.archive_items i
    join ichart_snapshot_retention.archive_batches ab on ab.id=i.batch_id
    where i.snapshot_id=s.id and i.owner_id=p.owner_id and i.invalidated_at is null and ab.verified_at is not null)
  order by s.id limit v_limit
 loop
  v_text:=ichart_snapshot_retention.row_text(v_snapshot);
  v_length:=octet_length(v_text)+1;
  if v_bytes+v_length>p.max_batch_bytes then
   if v_count=0 then raise exception 'Snapshot exceeds configured archive byte budget'
    using detail=jsonb_build_object('required_bytes',v_length,'byte_budget',p.max_batch_bytes)::text; end if;
   exit;
  end if;
  v_sha:=encode(extensions.digest(convert_to(v_text,'UTF8'),'sha256'),'hex');
  v_rows:=v_rows||jsonb_build_array(jsonb_build_object('snapshot_id',v_snapshot.id,'row_text',v_text,'row_sha256',v_sha));
  v_count:=v_count+1; v_bytes:=v_bytes+v_length;
 end loop;
 select encode(extensions.digest(convert_to(string_agg((r->>'snapshot_id')||':'||(r->>'row_sha256'),E'\n'
  order by (r->>'snapshot_id')::uuid),'UTF8'),'sha256'),'hex') into v_manifest from jsonb_array_elements(v_rows) r;
 if v_count=0 then
  if exists(select 1 from public.chart_snapshots s where s.owner_id=p.owner_id
    and ((v_mode='initial' and exists(select 1 from ichart_snapshot_retention.initial_inventory inv where inv.owner_id=p.owner_id and inv.snapshot_id=s.id))
     or (v_mode='retention' and not exists(select 1 from ichart_snapshot_retention.keeper_ids(p.owner_id,v_now) k where k=s.id)))
    and not exists(select 1 from ichart_snapshot_retention.archive_items i join ichart_snapshot_retention.archive_batches ab on ab.id=i.batch_id
     where i.snapshot_id=s.id and i.owner_id=p.owner_id and i.invalidated_at is null and ab.verified_at is not null)) then
   raise exception 'Candidate exceeds configured archive byte budget or has mismatched parent ownership';
  end if;
  if v_mode='initial' and exists(select 1 from ichart_snapshot_retention.initial_inventory inv where inv.owner_id=p.owner_id
   and not exists(select 1 from ichart_snapshot_retention.archive_items i join ichart_snapshot_retention.archive_batches ab on ab.id=i.batch_id
    where i.snapshot_id=inv.snapshot_id and i.owner_id=p.owner_id and i.invalidated_at is null and ab.verified_at is not null)) then
   raise exception 'Initial snapshot disappeared before verified archive; pruning remains disabled'; end if;
  return jsonb_build_object('status','empty','mode',v_mode);
 end if;
 insert into ichart_snapshot_retention.archive_batches(id,owner_id,bucket,object_key,mode,manifest_sha256,row_count,uncompressed_bytes,lease_expires_at)
 values(v_id,p.owner_id,p.bucket,p.owner_id::text||'/'||v_id::text||'.jsonl.gz',v_mode,v_manifest,v_count,v_bytes,v_now+interval '1 hour');
 insert into ichart_snapshot_retention.archive_items(batch_id,owner_id,snapshot_id,row_sha256)
 select v_id,p.owner_id,(r->>'snapshot_id')::uuid,r->>'row_sha256' from jsonb_array_elements(v_rows) r;
 return jsonb_build_object('status','planned','mode',v_mode,'batch_id',v_id,'owner_id',p.owner_id,'bucket',p.bucket,
  'object_key',p.owner_id::text||'/'||v_id::text||'.jsonl.gz','manifest_sha256',v_manifest,'row_count',v_count,
  'uncompressed_bytes',v_bytes,'rows',v_rows,'initial_restore_verified',p.initial_restore_verified_at is not null,
  'expires_at',v_now+interval '1 hour');
end $$;

create function public.finalize_owner_snapshot_archive(p_batch_id uuid,p_archive_sha256 text,p_archive_bytes bigint,
 p_restored_manifest_sha256 text,p_restored_row_count integer) returns jsonb
language plpgsql security invoker set search_path=pg_catalog set timezone='UTC' as $$
declare p ichart_snapshot_retention.policy%rowtype; b ichart_snapshot_retention.archive_batches%rowtype;
 v_now timestamptz:=clock_timestamp(); v_deleted integer:=0; v_protected integer:=0; v_invalid integer:=0;
 v_docs_before jsonb; v_docs_after jsonb; v_item_count integer; v_item_manifest text; v_locked_snapshot_ids uuid[];
 v_restore_snapshot_ids uuid[]; v_restore_before jsonb; v_restore_after jsonb;
begin
 perform ichart_snapshot_retention.guard_service();
 perform pg_advisory_xact_lock(1801675876,1);
 select * into p from ichart_snapshot_retention.policy where singleton;
 if not found or (not p.enabled and p.deletion_requested_at is null) then raise exception 'Owner retention is disabled'; end if;
 select * into b from ichart_snapshot_retention.archive_batches where id=p_batch_id and owner_id=p.owner_id for update;
 if not found then raise exception 'Archive batch outside configured owner scope'; end if;
 select count(*)::integer,encode(extensions.digest(convert_to(
  string_agg(snapshot_id::text||':'||row_sha256,E'\n' order by snapshot_id),'UTF8'),'sha256'),'hex')
 into v_item_count,v_item_manifest from ichart_snapshot_retention.archive_items where batch_id=b.id and owner_id=p.owner_id;
 if v_item_count is distinct from b.row_count or v_item_manifest is distinct from b.manifest_sha256 then
  raise exception 'Archive item manifest is inconsistent'; end if;
 if p_archive_sha256 is null or p_archive_sha256 !~ '^[0-9a-f]{64}$' or p_archive_bytes is null or p_archive_bytes<1
  or p_archive_bytes>b.uncompressed_bytes+1048576 or p_restored_manifest_sha256 is distinct from b.manifest_sha256
  or p_restored_row_count is distinct from b.row_count then raise exception 'Archive verification attestation mismatch'; end if;
 if b.verified_at is not null and (b.archive_sha256 is distinct from p_archive_sha256 or b.archive_bytes is distinct from p_archive_bytes) then
  raise exception 'Verified archive receipt is immutable'; end if;
 if b.verified_at is null and (b.state<>'planned' or b.lease_expires_at is null or b.lease_expires_at<v_now) then raise exception 'Archive batch lease expired'; end if;
 -- Separate statements and READ COMMITTED are deliberate: a waiter must see
 -- a head committed before it obtained these locks, not an older CTE snapshot.
 perform d.id from public.chart_documents d where d.owner_id=p.owner_id order by d.id for update;
 if p.initial_restore_verified_at is not null and p.deletion_requested_at is null then
  if exists(select 1 from public.chart_documents d left join public.chart_snapshots s on s.id=d.latest_snapshot_id
   where d.owner_id=p.owner_id and d.latest_snapshot_id is not null
    and (s.id is null or s.owner_id<>p.owner_id or s.chart_id<>d.id))
   or exists(select 1 from public.chart_documents d where d.owner_id=p.owner_id and d.deleted_at is null
    and d.latest_snapshot_id is null and not exists(select 1 from public.chart_snapshots s where s.owner_id=p.owner_id and s.chart_id=d.id)) then
   raise exception 'Owner restore head/fallback integrity failure'; end if;
  with restore_ids as (
   select d.latest_snapshot_id id from public.chart_documents d
    where d.owner_id=p.owner_id and d.latest_snapshot_id is not null
   union
   select f.id from public.chart_documents d cross join lateral (
    select s.id from public.chart_snapshots s where s.owner_id=p.owner_id and s.chart_id=d.id
     order by s.version desc,s.id desc limit 1
   ) f where d.owner_id=p.owner_id and d.deleted_at is null and d.latest_snapshot_id is null
  ) select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_restore_snapshot_ids from restore_ids;
  if cardinality(v_restore_snapshot_ids)>1024 then raise exception 'Owner head preservation budget exceeded'; end if;
  if exists(select 1 from unnest(v_restore_snapshot_ids) h(id) left join public.chart_snapshots s on s.id=h.id
   left join public.chart_documents d on d.id=s.chart_id
   where s.id is null or s.owner_id<>p.owner_id or d.owner_id<>p.owner_id) then
   raise exception 'Restore pointer owner/chart integrity failure'; end if;
  perform s.id from public.chart_snapshots s where s.owner_id=p.owner_id and s.id=any(v_restore_snapshot_ids)
   order by s.id for share;
  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'sha256',ichart_snapshot_retention.row_sha256(s)) order by s.id),'[]'::jsonb)
   into v_restore_before from public.chart_snapshots s where s.owner_id=p.owner_id and s.id=any(v_restore_snapshot_ids);
 end if;
 select coalesce(array_agg(locked.id),'{}'::uuid[]) into v_locked_snapshot_ids from (
  select s.id from public.chart_snapshots s join ichart_snapshot_retention.archive_items i on i.snapshot_id=s.id
  where i.batch_id=b.id and i.owner_id=p.owner_id and s.owner_id=p.owner_id order by s.id for update of s
 ) locked;
 select coalesce(jsonb_agg(to_jsonb(d) order by d.id),'[]'::jsonb) into v_docs_before
  from public.chart_documents d where d.owner_id=p.owner_id;
 update ichart_snapshot_retention.archive_items i set invalidated_at=v_now
  from public.chart_snapshots s where i.batch_id=b.id and i.snapshot_id=s.id and i.owner_id=p.owner_id
   and s.owner_id<>p.owner_id;
 get diagnostics v_invalid=row_count;
 update ichart_snapshot_retention.archive_items i set invalidated_at=v_now
  from public.chart_snapshots s where i.batch_id=b.id and i.snapshot_id=s.id and i.owner_id=p.owner_id
   and s.owner_id=p.owner_id and s.id=any(v_locked_snapshot_ids)
   and i.row_sha256 is distinct from ichart_snapshot_retention.row_sha256(s);
 select count(*) into v_invalid from ichart_snapshot_retention.archive_items where batch_id=b.id and invalidated_at=v_now;
 update ichart_snapshot_retention.archive_batches set state='verified',archive_sha256=p_archive_sha256,
  archive_bytes=p_archive_bytes,verified_at=coalesce(verified_at,v_now),lease_expires_at=null where id=b.id;
 if p.deletion_requested_at is not null then
  return jsonb_build_object('status','verified_waiting_account_deletion','batch_id',b.id,'owner_id',p.owner_id,
   'deleted_count',0,'protected_count',b.row_count);
 end if;
 if p.initial_restore_verified_at is null then
  return jsonb_build_object('status','verified_waiting_initial_restore','batch_id',b.id,'owner_id',p.owner_id,
   'deleted_count',0,'protected_count',b.row_count);
 end if;

 with deleted as (
  delete from public.chart_snapshots s using ichart_snapshot_retention.archive_items i
  where i.batch_id=b.id and i.snapshot_id=s.id and i.owner_id=p.owner_id and s.owner_id=p.owner_id
   and s.id=any(v_locked_snapshot_ids) and i.invalidated_at is null and i.row_sha256=ichart_snapshot_retention.row_sha256(s)
   and exists(select 1 from public.chart_documents d where d.id=s.chart_id and d.owner_id=p.owner_id)
   and not exists(select 1 from ichart_snapshot_retention.keeper_ids(p.owner_id,v_now) k where k=s.id)
   and not exists(select 1 from public.chart_documents d where d.latest_snapshot_id=s.id)
  returning s.id
 ) select count(*) into v_deleted from deleted;
 select count(*) into v_protected from public.chart_snapshots s join ichart_snapshot_retention.archive_items i on i.snapshot_id=s.id
  where i.batch_id=b.id and s.owner_id=p.owner_id;
 select coalesce(jsonb_agg(to_jsonb(d) order by d.id),'[]'::jsonb) into v_docs_after
  from public.chart_documents d where d.owner_id=p.owner_id;
 if v_docs_after is distinct from v_docs_before then raise exception 'Retention changed a protected document; rolling back'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'sha256',ichart_snapshot_retention.row_sha256(s)) order by s.id),'[]'::jsonb)
  into v_restore_after from public.chart_snapshots s where s.owner_id=p.owner_id and s.id=any(v_restore_snapshot_ids);
 if v_restore_after is distinct from v_restore_before then
  raise exception 'Retention changed a restore snapshot payload; rolling back'; end if;
 update ichart_snapshot_retention.archive_batches set state='completed',completed_at=v_now,lease_expires_at=null where id=b.id;
 return jsonb_build_object('status','pruned','batch_id',b.id,'owner_id',p.owner_id,'deleted_count',v_deleted,
  'protected_count',v_protected,'invalidated_count',v_invalid);
end $$;

create function public.list_owner_snapshot_archives(p_after uuid default null,p_limit integer default 100) returns jsonb
language plpgsql security invoker set search_path=pg_catalog set timezone='UTC' as $$
declare p ichart_snapshot_retention.policy%rowtype; result jsonb; next_id uuid;
begin
 perform ichart_snapshot_retention.guard_service();
 select * into p from ichart_snapshot_retention.policy where singleton;
 if not found then return jsonb_build_object('batches','[]'::jsonb,'next_cursor',null); end if;
 if p_limit is null or p_limit<1 or p_limit>100 then raise exception 'Invalid listing limit'; end if;
 with page as materialized (
  select id as batch_id,bucket,object_key,archive_sha256,archive_bytes,manifest_sha256,row_count,uncompressed_bytes,verified_at
  from ichart_snapshot_retention.archive_batches where owner_id=p.owner_id and verified_at is not null
   and (p_after is null or id>p_after) order by id limit p_limit+1
 ), included as (select * from page order by batch_id limit p_limit)
 select coalesce(jsonb_agg(to_jsonb(included) order by batch_id),'[]'::jsonb),
  case when (select count(*) from page)>p_limit then max(batch_id::text)::uuid else null end
 into result,next_id from included;
 return jsonb_build_object('owner_id',p.owner_id,'batches',result,'next_cursor',next_id);
end $$;

revoke all on all functions in schema ichart_snapshot_retention from public,anon,authenticated,service_role;
grant execute on function ichart_snapshot_retention.guard_service(),ichart_snapshot_retention.row_text(public.chart_snapshots),
 ichart_snapshot_retention.row_sha256(public.chart_snapshots),ichart_snapshot_retention.keeper_ids(uuid,timestamptz) to service_role;
revoke all on function public.owner_snapshot_retention_status(),public.plan_owner_snapshot_retention(integer),
 public.finalize_owner_snapshot_archive(uuid,text,bigint,text,integer),public.list_owner_snapshot_archives(uuid,integer)
 from public,anon,authenticated,service_role;
grant execute on function public.owner_snapshot_retention_status(),public.plan_owner_snapshot_retention(integer),
 public.finalize_owner_snapshot_archive(uuid,text,bigint,text,integer),public.list_owner_snapshot_archives(uuid,integer) to service_role;
-- Invoker functions rely only on preexisting backend table privileges; never
-- expand global client DELETE/UPDATE or regrant private-schema USAGE.
do $$ begin
 if not has_table_privilege('service_role','public.chart_documents','SELECT')
  or not has_table_privilege('service_role','public.chart_documents','UPDATE')
  or not has_table_privilege('service_role','public.chart_snapshots','SELECT')
  or not has_table_privilege('service_role','public.chart_snapshots','UPDATE')
  or not has_table_privilege('service_role','public.chart_snapshots','DELETE') then
  raise exception 'Required existing service table privileges missing; review before installation'; end if;
end $$;

-- Existing verified-account deletion freezes planning and discovers only its own archive prefix.
-- Disabled retention still needs cleanup. Missing/different scope returns before
-- changes. Active upload leases make readiness false until acknowledgement or expiry.
create function public.owner_snapshot_archive_deletion_scope(p_owner_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog set timezone='UTC' as $$
declare configured_owner uuid; is_ready boolean;
begin
 -- SECURITY DEFINER changes current_user. The protected role setting/session
 -- identity is authoritative; user-editable JWT metadata is never consulted.
 if current_setting('role',true) is distinct from 'service_role'
  and session_user is distinct from 'service_role' then
  raise exception 'Service role required' using errcode='42501'; end if;
 if p_owner_id is null then raise exception 'Verified owner is required' using errcode='22004'; end if;
 select owner_id into configured_owner from ichart_snapshot_retention.policy where singleton;
 if configured_owner is null or p_owner_id is distinct from configured_owner then
  return jsonb_build_object('applies',false);
 end if;
 perform pg_advisory_xact_lock(1801675876,1);
 -- Recheck after waiting; a concurrent account/config deletion must not create
 -- a stale prefix authorization. Owner identity itself is immutable.
 select owner_id into configured_owner from ichart_snapshot_retention.policy where singleton;
 if configured_owner is null or p_owner_id is distinct from configured_owner then
  return jsonb_build_object('applies',false);
 end if;
 update ichart_snapshot_retention.policy set enabled=false,
  deletion_requested_at=coalesce(deletion_requested_at,clock_timestamp()) where owner_id=configured_owner;
 select not exists(select 1 from ichart_snapshot_retention.archive_batches
  where owner_id=configured_owner and lease_expires_at>clock_timestamp()) into is_ready;
 return jsonb_build_object('applies',true,'ready',is_ready,'owner_id',configured_owner,
  'bucket','ichart-owner-snapshot-archives','prefix',configured_owner::text||'/');
end $$;
revoke all on function public.owner_snapshot_archive_deletion_scope(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.owner_snapshot_archive_deletion_scope(uuid) to service_role;
commit;
