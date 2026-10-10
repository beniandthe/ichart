-- Proposed telemetry-only privacy closeout. Apply only after approval of the
-- 180-day daily cutoff and deletion of linked events on account deletion.
-- This migration never invokes the purge or deletes an account. Its Cron job
-- becomes active when applied; old received events are deleted on later runs.
begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $$
begin
    if to_regprocedure('cron.schedule(text,text,text)') is null then
        raise exception 'pg_cron must be available before telemetry retention is configured';
    end if;
end;
$$;

-- Atomic owner-scoped erasure. Anonymous events and events linked to another
-- account are not removed by this foreign key, even on a shared installation.
-- Historical events already unlinked by the old SET NULL rule cannot be
-- reconstructed by this change; they remain subject to age-based retention.
alter table public.telemetry_events
    drop constraint telemetry_events_owner_id_fkey;
alter table public.telemetry_events
    add constraint telemetry_events_owner_id_fkey
    foreign key (owner_id) references auth.users(id) on delete cascade
    not valid;
alter table public.telemetry_events
    validate constraint telemetry_events_owner_id_fkey;

create or replace function private.purge_old_telemetry_events(retain_days integer default 180)
returns integer
language plpgsql
security definer
set search_path = private
as $$
declare
    deleted_count integer;
begin
    if retain_days is null then
        raise exception 'retain_days must not be null';
    end if;
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

-- Stable name makes reapplication update this same scheduling user's job.
-- The cutoff uses server received_at, not a client-provided event timestamp.
-- A daily cutoff is not an exact maximum age: expired rows wait until the next
-- successful run. Monitor cron.job_run_details and investigate failures.
select cron.schedule(
    'ichart-telemetry-retention-180d',
    '15 3 * * *',
    'select private.purge_old_telemetry_events(180);'
);

commit;
