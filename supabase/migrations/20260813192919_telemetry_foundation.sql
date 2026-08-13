create schema if not exists private;
revoke all on schema private from public;

create table public.telemetry_events (
    id uuid primary key default gen_random_uuid(),
    client_event_id uuid not null unique,
    owner_id uuid references auth.users(id) on delete set null,
    installation_id uuid not null,
    session_id uuid not null,
    source text not null default 'ios' check (source in ('ios')),
    event_name text not null check (
        event_name ~ '^[a-z][a-z0-9_\\.]{2,95}$'
    ),
    occurred_at timestamptz not null,
    received_at timestamptz not null default now(),
    app_version text not null check (length(app_version) between 1 and 32),
    build_number text not null check (length(build_number) between 1 and 32),
    platform text not null check (length(platform) between 1 and 32),
    os_version text not null check (length(os_version) between 1 and 64),
    device_model text not null check (length(device_model) between 1 and 80),
    locale_language text not null check (length(locale_language) between 1 and 32),
    time_zone_offset_minutes integer not null check (
        time_zone_offset_minutes between -840 and 840
    ),
    properties jsonb not null default '{}'::jsonb check (
        jsonb_typeof(properties) = 'object'
    )
);

alter table public.telemetry_events enable row level security;

revoke all on table public.telemetry_events from public, anon, authenticated;
grant usage on schema private to service_role;
grant select, insert, delete on table public.telemetry_events to service_role;

create index telemetry_events_received_at_idx
    on public.telemetry_events (received_at desc);

create index telemetry_events_event_received_idx
    on public.telemetry_events (event_name, received_at desc);

create index telemetry_events_owner_received_idx
    on public.telemetry_events (owner_id, received_at desc)
    where owner_id is not null;

create index telemetry_events_installation_received_idx
    on public.telemetry_events (installation_id, received_at desc);

create index telemetry_events_properties_gin_idx
    on public.telemetry_events using gin (properties jsonb_path_ops);

create or replace view private.telemetry_daily_event_counts as
select
    date_trunc('day', received_at)::date as event_day,
    event_name,
    app_version,
    build_number,
    count(*)::bigint as event_count,
    count(distinct owner_id)::bigint as signed_in_user_count,
    count(distinct installation_id)::bigint as installation_count,
    count(distinct session_id)::bigint as session_count
from public.telemetry_events
group by 1, 2, 3, 4;

create or replace view private.telemetry_daily_feature_usage as
select
    date_trunc('day', received_at)::date as event_day,
    case
        when event_name like 'auth.%' then 'auth'
        when event_name like 'library.%' then 'library'
        when event_name like 'editor.%' then 'editor'
        when event_name like 'ink.%' then 'ink'
        when event_name like 'chord.%' then 'chord'
        when event_name like 'rhythm.%' then 'rhythm'
        when event_name like 'pdf.%' then 'pdf'
        when event_name like 'cloud.%' then 'cloud'
        when event_name like 'subscription.%' then 'subscription'
        when event_name like 'forum.%' then 'forum'
        else 'app'
    end as feature_area,
    app_version,
    build_number,
    count(*)::bigint as event_count,
    count(distinct owner_id)::bigint as signed_in_user_count,
    count(distinct installation_id)::bigint as installation_count,
    count(distinct session_id)::bigint as session_count
from public.telemetry_events
group by 1, 2, 3, 4;

create or replace view private.telemetry_recent_ink_diagnostics as
select
    received_at,
    owner_id,
    installation_id,
    app_version,
    build_number,
    os_version,
    device_model,
    event_name,
    properties ->> 'scope' as scope,
    properties ->> 'stroke_count' as stroke_count,
    properties ->> 'point_count' as point_count,
    properties ->> 'light_stroke_count' as light_stroke_count,
    properties ->> 'min_opacity' as min_opacity,
    properties ->> 'median_opacity' as median_opacity,
    properties ->> 'max_opacity' as max_opacity,
    properties ->> 'min_width' as min_width,
    properties ->> 'median_width' as median_width,
    properties ->> 'max_width' as max_width,
    properties ->> 'has_mask' as has_mask,
    properties ->> 'normalization_needed' as normalization_needed,
    properties ->> 'normalized_before_save' as normalized_before_save
from public.telemetry_events
where event_name in ('ink.persisted', 'ink.normalization_applied', 'ink.visibility_probe');

grant select on private.telemetry_daily_event_counts to service_role;
grant select on private.telemetry_daily_feature_usage to service_role;
grant select on private.telemetry_recent_ink_diagnostics to service_role;

create or replace function private.purge_old_telemetry_events(retain_days integer default 180)
returns integer
language plpgsql
security definer
set search_path = private
as $$
declare
    deleted_count integer;
begin
    if retain_days < 30 then
        raise exception 'retain_days must be at least 30';
    end if;

    delete from public.telemetry_events
    where received_at < now() - make_interval(days => retain_days);

    get diagnostics deleted_count = row_count;
    return deleted_count;
end;
$$;

revoke all on function private.purge_old_telemetry_events(integer)
    from public, anon, authenticated;
grant execute on function private.purge_old_telemetry_events(integer)
    to service_role;
