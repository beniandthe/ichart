-- Synthetic PostgreSQL17 fixture only. The harness initializes its own private
-- Unix-socket cluster with TCP disabled, without accessing any existing stack.
do $$
begin
  if current_database() !~ '^ichart_retention_test_[a-z0-9_]+$' then
    raise exception 'Owner-retention fixture requires its own new test database';
  end if;
  if current_setting('server_version_num')::integer not between 170000 and 179999 then
    raise exception 'Owner-retention fixture requires PostgreSQL17';
  end if;
  if to_regnamespace('auth') is not null or to_regclass('public.chart_snapshots') is not null then
    raise exception 'Owner-retention fixture requires an empty database';
  end if;
  if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
  if exists(select 1 from pg_roles where rolname in ('anon','authenticated') and (rolsuper or rolbypassrls)) then
    raise exception 'Fixture client roles must not bypass RLS';
  end if;
end; $$;
set timezone='UTC';
create schema extensions;
create extension pgcrypto with schema extensions;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; $$;
grant usage on schema public,auth,extensions to anon,authenticated,service_role;

-- Exact snapshot/document columns and FK actions from the real initial schema.
create table public.chart_documents (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'Untitled Chart',
  layout_style text not null check(layout_style in ('simpleChordSheet','rhythmSectionSheet','leadSheet')),
  latest_snapshot_id uuid,
  deleted_at timestamptz,
  remote_revision bigint not null default 0,
  client_updated_at timestamptz,
  last_snapshot_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.chart_snapshots (
  id uuid primary key default gen_random_uuid(),
  chart_id uuid not null references public.chart_documents(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  version bigint not null check(version>0),
  chart_json jsonb not null,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  unique(chart_id,version)
);
alter table public.chart_documents add constraint chart_documents_latest_snapshot_id_fkey
  foreign key(latest_snapshot_id) references public.chart_snapshots(id) on delete set null;
create index chart_snapshots_chart_id_version_idx on public.chart_snapshots(chart_id,version desc);
create index chart_snapshots_owner_id_idx on public.chart_snapshots(owner_id);
alter table public.chart_documents enable row level security;
alter table public.chart_snapshots enable row level security;
revoke all on public.chart_documents,public.chart_snapshots from public,anon,authenticated;
grant select,insert,update,delete on public.chart_documents to authenticated;
grant select,insert on public.chart_snapshots to authenticated;
-- Supabase service privileges are a prerequisite, not a client expansion.
grant select,insert,update,delete on public.chart_documents,public.chart_snapshots to service_role;
create policy fixture_docs_select_own on public.chart_documents for select to authenticated
  using(owner_id=(select auth.uid()));
create policy fixture_docs_update_own on public.chart_documents for update to authenticated
  using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
create policy fixture_snapshots_select_own on public.chart_snapshots for select to authenticated
  using(owner_id=(select auth.uid()));
create policy fixture_snapshots_insert_own on public.chart_snapshots for insert to authenticated
  with check(owner_id=(select auth.uid()) and exists(select 1 from public.chart_documents d
    where d.id=chart_id and d.owner_id=(select auth.uid())));

-- Platform-only adapters; no scheduler runs and no Storage HTTP/object service.
create schema storage;
create table storage.buckets(id text primary key,name text,public boolean default false,
  file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),name text,owner uuid,owner_id text,
  metadata jsonb default '{}',created_at timestamptz default now(),updated_at timestamptz default now());
alter table storage.objects enable row level security;
grant usage on schema storage to service_role;
grant select on storage.buckets,storage.objects to service_role;
-- Deliberately permissive TEST-ONLY client policy proves the new archive-bucket
-- restrictive policy wins without changing access to any other bucket.
grant usage on schema storage to anon,authenticated;
grant select on storage.buckets to anon,authenticated;
grant select,insert,update,delete on storage.objects to anon,authenticated;
create policy fixture_broad_storage_access on storage.objects for all to anon,authenticated
  using(true) with check(true);
insert into storage.buckets(id,name,public) values
  ('ichart-owner-snapshot-archives','ichart-owner-snapshot-archives',false),
  ('fixture-other-bucket','fixture-other-bucket',false);
create schema cron;
create table cron.job(jobid bigint generated always as identity primary key,
  jobname text unique not null,schedule text not null,command text not null,active boolean default true);
create function cron.schedule(text,text,text) returns bigint language plpgsql as $$
declare result bigint;
begin
  insert into cron.job(jobname,schedule,command) values($1,$2,$3)
  on conflict(jobname) do update set schedule=excluded.schedule,command=excluded.command
  returning jobid into result;
  return result;
end; $$;

create schema fixture;
create function fixture.id(n bigint) returns uuid language sql immutable as $$
  select ('30000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create function fixture.seed_history(p_owner uuid,p_chart uuid,p_base bigint,p_count integer)
returns void language plpgsql as $$
begin
  insert into public.chart_documents(id,owner_id,title,layout_style)
    values(p_chart,p_owner,'Synthetic chart','simpleChordSheet');
  insert into public.chart_snapshots(id,chart_id,owner_id,version,chart_json,client_updated_at,created_at)
  select fixture.id(p_base+n),p_chart,p_owner,n,
    jsonb_build_object('id',p_chart,'title','Synthetic revision '||n,
      'pageHandwrittenChordData','AQIDBA==',
      'cloudBackupStatus',jsonb_build_object('ownerID',p_owner,'intent','included')),
    (date_trunc('day',clock_timestamp() at time zone 'UTC') at time zone 'UTC') - interval '4 days' + interval '12 hours' + n*interval '1 second',
    (date_trunc('day',clock_timestamp() at time zone 'UTC') at time zone 'UTC') - interval '4 days' + interval '12 hours' + n*interval '1 second'
  from generate_series(1,p_count) n;
  update public.chart_documents set latest_snapshot_id=fixture.id(p_base+p_count) where id=p_chart;
end; $$;
insert into auth.users(id) values
  ('10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000002');
