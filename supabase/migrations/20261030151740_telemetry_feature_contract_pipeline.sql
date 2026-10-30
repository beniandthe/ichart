-- Content-free feature contracts -> durable evaluation -> categorized work queue.
-- Applying this migration activates a five-minute server-side worker. No chart,
-- ink, recognition result, account or raw telemetry record is modified.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create table private.telemetry_contract_definitions (
    contract_id text primary key,
    contract_version integer not null check (contract_version > 0),
    category text not null,
    severity text not null check (severity in ('critical','high','medium','low')),
    evidence_kind text not null check (evidence_kind in ('contract_violation','operation_failure')),
    title text not null,
    allowed_reasons text[] not null
);
insert into private.telemetry_contract_definitions values
('chart.save',1,'disk_persistence','high','operation_failure','Chart could not be saved',array['save_failed']),
('chart.load',1,'disk_persistence','high','operation_failure','Chart library could not be loaded',array['load_failed']),
('chart.save_readback',1,'disk_persistence','critical','contract_violation','Saved chart did not match readback',array['readback_failed','readback_mismatch']),
('ink.reopen_preservation',1,'data_preservation','critical','contract_violation','Source ink changed across reopening',array['reopen_mismatch']),
('ink.render_preservation',1,'render_transaction','critical','contract_violation','Source ink changed during rendering',array['render_source_missing','render_rejected_mutated','render_canvas_not_cleared']),
('ink.rotation_preservation',1,'ink_geometry_visibility','high','contract_violation','Ink preservation check failed during rotation',array['rotation_stroke_count_changed','rotation_point_count_changed','rotation_nonfinite_geometry']),
('chart.export',1,'render_transaction','medium','operation_failure','Chart export failed',array['export_failed']);

create table private.telemetry_evaluation_outbox (
    raw_event_id uuid primary key references public.telemetry_events(id) on delete cascade,
    enqueued_at timestamptz not null default now(),
    next_attempt_at timestamptz not null default now(),
    attempts integer not null default 0 check (attempts >= 0),
    processed_at timestamptz,
    dead_letter_at timestamptz,
    evaluation_result text check (evaluation_result in ('matched','ignored','rejected')),
    last_error_code text
);
create index telemetry_evaluation_pending_idx
    on private.telemetry_evaluation_outbox(next_attempt_at,enqueued_at)
    where processed_at is null and dead_letter_at is null;

create table private.telemetry_incidents (
    incident_id uuid primary key default gen_random_uuid(),
    fingerprint text not null unique,
    rule_id text not null,
    rule_version integer not null check (rule_version > 0),
    category text not null,
    severity text not null check (severity in ('critical','high','medium','low')),
    evidence_kind text not null check (evidence_kind in ('contract_violation','operation_failure','investigation','friction')),
    build_source text not null check (build_source in ('debug_build','release_build','unknown')),
    title text not null,
    status text not null default 'new' check (status in ('new','triaged','in_progress','verifying','resolved','ignored')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    fixed_build_number text,
    verification_ref text check (length(verification_ref) between 1 and 500),
    resolved_at timestamptz,
    reopened_count integer not null default 0
);
create table private.telemetry_incident_events (
    raw_event_id uuid not null references public.telemetry_events(id) on delete cascade,
    rule_id text not null,
    rule_version integer not null,
    incident_id uuid not null references private.telemetry_incidents(incident_id) on delete cascade,
    detected_at timestamptz not null default now(),
    primary key (raw_event_id,rule_id,rule_version)
);
create index telemetry_incident_events_incident_idx on private.telemetry_incident_events(incident_id);
create table private.telemetry_incident_history (
    history_id bigint generated always as identity primary key,
    incident_id uuid not null references private.telemetry_incidents(incident_id) on delete cascade,
    from_status text,
    to_status text not null,
    changed_at timestamptz not null default now(),
    change_reason text not null check (change_reason in ('created','operator_transition','verified_fix_recurrence'))
);
create table private.telemetry_evaluation_runs (
    run_id bigint generated always as identity primary key,
    started_at timestamptz not null default now(),
    finished_at timestamptz,
    processed_count integer not null default 0,
    matched_count integer not null default 0,
    failed_count integer not null default 0
);

-- Use a label recorded on this event first. Legacy launch joins are a bounded
-- fallback, and missing provenance stays unknown. Release is not customer proof.
create function private.telemetry_event_build_source(event_row public.telemetry_events)
returns text language sql stable security invoker set search_path = '' as $$
    select case
      when event_row.properties->>'build_source' in ('debug_build','release_build')
        then event_row.properties->>'build_source'
      else coalesce((select l.properties->>'source'
        from public.telemetry_events l
        where l.installation_id=event_row.installation_id and l.session_id=event_row.session_id
          and l.event_name='app.launched'
          and l.properties->>'source' in ('debug_build','release_build')
        order by l.received_at,l.id limit 1),'unknown') end;
$$;

create function private.enqueue_telemetry_evaluation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if new.event_name in ('feature.contract_checked','cloud.push_failed','cloud.restore_failed','chord.rendered_correction_applied') then
        insert into private.telemetry_evaluation_outbox(raw_event_id) values(new.id)
        on conflict do nothing;
    end if;
    return new;
end;
$$;
create trigger telemetry_event_evaluation_outbox after insert on public.telemetry_events
    for each row execute function private.enqueue_telemetry_evaluation();

-- This classifier is deliberately deterministic. Uncertainty, masks, canvas
-- transitions, coordinate conversion and safe rejection are never loss labels.
create function private.classify_telemetry_event(event_row public.telemetry_events)
returns table(rule_id text,rule_version integer,category text,severity text,evidence_kind text,title text)
language plpgsql stable security invoker set search_path = '' as $$
declare definition private.telemetry_contract_definitions%rowtype;
reason text := event_row.properties->>'reason';
error_code text := event_row.properties->>'error_code';
expected_count numeric;
actual_count numeric;
expected_bytes numeric;
actual_bytes numeric;
expected_point_count numeric;
actual_point_count numeric;
content_mismatch boolean := event_row.properties->'content_matches'='false'::jsonb;
begin
    if event_row.platform not in ('iPadOS','iOS') then return; end if;
    if event_row.event_name='feature.contract_checked' then
        if (event_row.properties->>'outcome' is distinct from 'violated'
            and not coalesce(event_row.properties->>'contract_id'='chart.save_readback'
              and event_row.properties->>'outcome'='unknown' and reason='readback_failed',false))
           or event_row.properties->'contract_version' is distinct from '1'::jsonb
           or coalesce(event_row.properties->>'operation_id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
        then return; end if;
        select * into definition from private.telemetry_contract_definitions d
          where d.contract_id=event_row.properties->>'contract_id' and d.contract_version=1;
        if not found or reason is null or not (reason=any(definition.allowed_reasons)) then return; end if;
        -- Require bounded typed observations for comparisons. Missing evidence
        -- is rejected, never interpreted as a measured zero or contract failure.
        if jsonb_typeof(event_row.properties->'expected_count')='number'
           and (event_row.properties->>'expected_count') ~ '^[0-9]{1,12}$' then
            expected_count:=(event_row.properties->>'expected_count')::numeric; end if;
        if jsonb_typeof(event_row.properties->'actual_count')='number'
           and (event_row.properties->>'actual_count') ~ '^[0-9]{1,12}$' then
            actual_count:=(event_row.properties->>'actual_count')::numeric; end if;
        if jsonb_typeof(event_row.properties->'expected_bytes')='number'
           and (event_row.properties->>'expected_bytes') ~ '^[0-9]{1,12}$' then
            expected_bytes:=(event_row.properties->>'expected_bytes')::numeric; end if;
        if jsonb_typeof(event_row.properties->'actual_bytes')='number'
           and (event_row.properties->>'actual_bytes') ~ '^[0-9]{1,12}$' then
            actual_bytes:=(event_row.properties->>'actual_bytes')::numeric; end if;
        if jsonb_typeof(event_row.properties->'expected_point_count')='number'
           and (event_row.properties->>'expected_point_count') ~ '^[0-9]{1,12}$' then
            expected_point_count:=(event_row.properties->>'expected_point_count')::numeric; end if;
        if jsonb_typeof(event_row.properties->'actual_point_count')='number'
           and (event_row.properties->>'actual_point_count') ~ '^[0-9]{1,12}$' then
            actual_point_count:=(event_row.properties->>'actual_point_count')::numeric; end if;
        if reason in ('readback_mismatch','reopen_mismatch','rotation_nonfinite_geometry')
           and content_mismatch is distinct from true then return; end if;
        if reason='rotation_stroke_count_changed'
           and (expected_count is null or actual_count is null or expected_count=actual_count) then return; end if;
        if reason='rotation_point_count_changed'
           and (expected_point_count is null or actual_point_count is null or expected_point_count=actual_point_count) then return; end if;
        if reason='render_source_missing' and not coalesce(content_mismatch or expected_count>actual_count,false) then return; end if;
        if reason='render_rejected_mutated' and not coalesce(content_mismatch or expected_count<>actual_count or expected_bytes<>actual_bytes,false) then return; end if;
        if reason='render_canvas_not_cleared' and (expected_count is distinct from 0 or actual_count is null or actual_count<=0) then return; end if;
        return query select 'contract.'||definition.contract_id||'.'||reason,1,
            definition.category,
            case when reason='render_canvas_not_cleared' then 'medium'
                 when reason='readback_failed' then 'high' else definition.severity end,
            case when reason='readback_failed' then 'operation_failure' else definition.evidence_kind end,
            case when reason='readback_failed' then 'Saved chart could not be read back'
                 when reason='render_canvas_not_cleared' then 'Rendered ink canvas did not clear'
                 else definition.title end;
    elsif event_row.event_name in ('cloud.push_failed','cloud.restore_failed') then
        if error_code is null or error_code not in ('server','authentication','timeout','sync_error') then return; end if;
        return query select 'legacy.'||event_row.event_name||'.'||error_code,1,
            'cloud_backup_restore','medium','investigation',
            case when event_row.event_name='cloud.restore_failed' then 'Investigate chart restore failures'
                 else 'Investigate chart backup failures' end;
    elsif event_row.event_name='chord.rendered_correction_applied' then
        if coalesce(event_row.properties->>'decision','') not in ('outside_candidates','candidate_replacement') then return; end if;
        return query select 'legacy.chord.rendered_correction',1,
            'recognition_workflow','low','friction','Review manual chord correction effort';
    end if;
end;
$$;

create function private.validate_telemetry_incident_transition()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    new.updated_at:=now();
    if new.status='resolved' then
        if coalesce(new.fixed_build_number,'') !~ '^[0-9]{1,12}$'
           or nullif(btrim(new.verification_ref),'') is null then
            raise exception 'Resolution requires a numeric fixed build and verification reference';
        end if;
        if old.status is distinct from 'resolved' then new.resolved_at:=now(); end if;
    elsif new.status<>'resolved' then new.resolved_at:=null;
    end if;
    return new;
end;
$$;
create trigger telemetry_incident_transition before update on private.telemetry_incidents
    for each row execute function private.validate_telemetry_incident_transition();

create function private.record_telemetry_incident_history()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if tg_op='INSERT' then
        insert into private.telemetry_incident_history(incident_id,to_status,change_reason)
        values(new.incident_id,new.status,'created');
    elsif old.status is distinct from new.status then
        insert into private.telemetry_incident_history(incident_id,from_status,to_status,change_reason)
        values(new.incident_id,old.status,new.status,
          case when new.reopened_count>old.reopened_count then 'verified_fix_recurrence' else 'operator_transition' end);
    end if;
    return new;
end;
$$;
create trigger telemetry_incident_history after insert or update on private.telemetry_incidents
    for each row execute function private.record_telemetry_incident_history();

create function private.process_telemetry_evaluations(batch_limit integer default 250)
returns integer language plpgsql security definer set search_path = '' as $$
declare queued record;
event_row public.telemetry_events%rowtype;
classification record;
incident private.telemetry_incidents%rowtype;
cohort text;
inserted_count integer;
processed integer:=0;
matches integer:=0;
failures integer:=0;
run_key bigint;
matched boolean;
begin
    if batch_limit is null or batch_limit<1 or batch_limit>1000 then
        raise exception 'batch_limit must be between 1 and 1000';
    end if;
    -- Concurrent Cron/manual runs safely skip locked events, with evidence PKs
    -- protecting retries. No timestamp high-watermark can skip a late arrival.
    insert into private.telemetry_evaluation_runs default values returning run_id into run_key;
    for queued in select o.* from private.telemetry_evaluation_outbox o
      where o.processed_at is null and o.dead_letter_at is null and o.next_attempt_at<=now()
      order by o.enqueued_at,o.raw_event_id for update skip locked limit batch_limit
    loop
      begin
        select * into strict event_row from public.telemetry_events where id=queued.raw_event_id;
        cohort:=private.telemetry_event_build_source(event_row);
        matched:=false;
        for classification in select * from private.classify_telemetry_event(event_row) loop
            insert into private.telemetry_incidents as current_incident
              (fingerprint,rule_id,rule_version,category,severity,evidence_kind,build_source,title)
            values(classification.rule_id||':v'||classification.rule_version||':'||cohort,
              classification.rule_id,classification.rule_version,classification.category,
              classification.severity,classification.evidence_kind,cohort,classification.title)
            on conflict(fingerprint) do update set updated_at=now()
            returning * into incident;
            insert into private.telemetry_incident_events(raw_event_id,rule_id,rule_version,incident_id)
            values(event_row.id,classification.rule_id,classification.rule_version,incident.incident_id)
            on conflict do nothing;
            get diagnostics inserted_count=row_count;
            if inserted_count>0 and incident.status='resolved'
              and event_row.occurred_at>incident.resolved_at
              and (case when event_row.build_number ~ '^[0-9]{1,12}$'
                  then event_row.build_number::numeric>=incident.fixed_build_number::numeric else false end) then
                update private.telemetry_incidents set status='new',reopened_count=reopened_count+1
                  where incident_id=incident.incident_id;
            end if;
            matched:=true;
        end loop;
        update private.telemetry_evaluation_outbox set processed_at=now(),attempts=attempts+1,
          evaluation_result=case when matched then 'matched'
            when event_row.event_name='feature.contract_checked' and event_row.properties->>'outcome'='violated'
              then 'rejected' else 'ignored' end,
          last_error_code=null where raw_event_id=queued.raw_event_id;
        processed:=processed+1;
        if matched then matches:=matches+1; end if;
      exception when others then
        -- Per-event subtransactions rollback partial incidents/evidence. Store a
        -- fixed error code only; database error text can contain private values.
        update private.telemetry_evaluation_outbox set attempts=attempts+1,
          last_error_code='evaluation_failed',
          next_attempt_at=now()+make_interval(secs=>least(3600,60*(2^least(attempts,6))::integer)),
          dead_letter_at=case when attempts+1>=5 then now() else null end
          where raw_event_id=queued.raw_event_id;
        failures:=failures+1;
      end;
    end loop;
    update private.telemetry_evaluation_runs set finished_at=now(),processed_count=processed,
      matched_count=matches,failed_count=failures where run_id=run_key;
    -- Worker bookkeeping contains no identifiers or content and is bounded.
    delete from private.telemetry_evaluation_runs where started_at<now()-interval '30 days';
    return processed;
end;
$$;

-- Counts are derived from surviving raw evidence, so account erasure and the
-- approved raw-event retention cascade to this queue's evidence and metrics.
create view private.telemetry_work_queue with (security_invoker=true) as
select i.incident_id,i.rule_id,i.rule_version,i.category,i.severity,i.evidence_kind,
  i.build_source,i.status,i.title,min(e.received_at) as first_seen_at,max(e.received_at) as last_seen_at,
  count(e.id)::bigint as event_count,count(distinct e.installation_id)::bigint as installation_count,
  (count(distinct (e.installation_id,e.session_id)) filter(where e.id is not null))::bigint as session_count,
  nullif(count(distinct (e.installation_id,e.session_id,lower(e.properties->>'operation_id')))
    filter(where e.properties->>'operation_id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'),0)::bigint as operation_count,
  nullif(count(distinct (e.installation_id,lower(e.properties->>'chart_reference')))
    filter(where e.properties->>'chart_reference' ~ '^[0-9a-fA-F]{64}$'),0)::bigint as affected_chart_count,
  (count(*) filter(where e.properties->>'operation_id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'))::bigint as operation_linked_event_count,
  (count(*) filter(where e.properties->>'chart_reference' ~ '^[0-9a-fA-F]{64}$'))::bigint as chart_linked_event_count,
  coalesce(array_agg(distinct e.app_version order by e.app_version) filter(where e.id is not null),array[]::text[]) as app_versions,
  coalesce(array_agg(distinct e.build_number order by e.build_number) filter(where e.id is not null),array[]::text[]) as build_numbers,
  (array_agg(e.id order by e.received_at desc,e.id desc))[1] as latest_event_id,
  count(e.id)>0 as evidence_available,
  i.fixed_build_number,i.verification_ref,i.resolved_at,i.reopened_count,
  case i.severity when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end as priority_rank
from private.telemetry_incidents i left join private.telemetry_incident_events d using(incident_id)
left join public.telemetry_events e on e.id=d.raw_event_id
group by i.incident_id;

create view private.telemetry_contract_outcomes with (security_invoker=true) as
select e.properties->>'contract_id' as contract_id,e.app_version,e.build_number,
  private.telemetry_event_build_source(e) as build_source,e.properties->>'outcome' as outcome,
  count(*)::bigint as observation_count,
  count(distinct e.installation_id)::bigint as installation_count,
  count(distinct (e.installation_id,e.session_id))::bigint as session_count,
  min(e.received_at) as first_received_at,max(e.received_at) as last_received_at
from public.telemetry_events e where e.event_name='feature.contract_checked'
  and e.platform in ('iPadOS','iOS') and e.properties->'contract_version'='1'::jsonb
  and e.properties->>'outcome' in ('passed','violated','unknown','protected_rejection')
  and exists(select 1 from private.telemetry_contract_definitions d where d.contract_id=e.properties->>'contract_id' and d.contract_version=1)
group by 1,2,3,4,5;

-- Cumulative delivery counters are snapshots: choose one latest valid report
-- per installation, then sum. Repeated launch reports are never added together.
create view private.telemetry_delivery_health with (security_invoker=true) as
with latest as (
  select distinct on (e.installation_id) e.installation_id,e.received_at,e.properties
  from public.telemetry_events e where e.event_name='app.launched'
    and e.properties ?& array['queue_overflow_count','queue_rejected_count',
      'queue_quarantine_overflow_count','queue_unacknowledged_batch_count']
    and not exists(select 1 from unnest(array['queue_overflow_count','queue_rejected_count',
      'queue_quarantine_overflow_count','queue_unacknowledged_batch_count']) as fields(key)
      where jsonb_typeof(e.properties->key) is distinct from 'number'
        or (e.properties->>key) !~ '^[0-9]{1,12}$')
  order by e.installation_id,e.occurred_at desc,e.received_at desc,e.id desc
)
select count(*)::bigint as delivery_reporting_installation_count,
  max(received_at) as last_delivery_reported_at,
  sum((properties->>'queue_overflow_count')::bigint)::bigint as queue_overflow_count,
  sum((properties->>'queue_rejected_count')::bigint)::bigint as queue_rejected_count,
  sum((properties->>'queue_quarantine_overflow_count')::bigint)::bigint as queue_quarantine_overflow_count,
  sum((properties->>'queue_unacknowledged_batch_count')::bigint)::bigint as queue_unacknowledged_batch_count
from latest;

create view private.telemetry_pipeline_health with (security_invoker=true) as
select o.*,
  (select max(finished_at) from private.telemetry_evaluation_runs) as last_run_at,
  (select processed_count from private.telemetry_evaluation_runs order by run_id desc limit 1) as last_run_processed,
  (select failed_count from private.telemetry_evaluation_runs order by run_id desc limit 1) as last_run_failed,
  d.delivery_reporting_installation_count,d.last_delivery_reported_at,
  d.queue_overflow_count,d.queue_rejected_count,d.queue_quarantine_overflow_count,d.queue_unacknowledged_batch_count
from (select count(*) filter(where processed_at is null and dead_letter_at is null)::bigint as pending_count,
  count(*) filter(where dead_letter_at is not null)::bigint as dead_letter_count,
  count(*) filter(where evaluation_result='rejected')::bigint as rejected_count,
  min(enqueued_at) filter(where processed_at is null and dead_letter_at is null) as oldest_pending_at
  from private.telemetry_evaluation_outbox) o cross join private.telemetry_delivery_health d;

revoke all on private.telemetry_contract_definitions,private.telemetry_evaluation_outbox,
  private.telemetry_incidents,private.telemetry_incident_events,private.telemetry_incident_history,
  private.telemetry_evaluation_runs,private.telemetry_work_queue,private.telemetry_contract_outcomes,
  private.telemetry_pipeline_health,private.telemetry_delivery_health from public,anon,authenticated;
revoke all on function private.telemetry_event_build_source(public.telemetry_events) from public,anon,authenticated;
revoke all on function private.enqueue_telemetry_evaluation() from public,anon,authenticated;
revoke all on function private.classify_telemetry_event(public.telemetry_events) from public,anon,authenticated;
revoke all on function private.validate_telemetry_incident_transition() from public,anon,authenticated;
revoke all on function private.record_telemetry_incident_history() from public,anon,authenticated;
revoke all on function private.process_telemetry_evaluations(integer) from public,anon,authenticated;
grant select on private.telemetry_contract_definitions,private.telemetry_evaluation_outbox,
  private.telemetry_incidents,private.telemetry_incident_events,private.telemetry_incident_history,
  private.telemetry_evaluation_runs,private.telemetry_work_queue,private.telemetry_contract_outcomes,
  private.telemetry_pipeline_health,private.telemetry_delivery_health to service_role;
grant update(status,fixed_build_number,verification_ref) on private.telemetry_incidents to service_role;
grant execute on function private.process_telemetry_evaluations(integer) to service_role;
grant execute on function private.telemetry_event_build_source(public.telemetry_events) to service_role;

-- Bounded historical leads: legacy failures/corrections become investigations
-- or friction, never historical ink-loss or accuracy claims.
insert into private.telemetry_evaluation_outbox(raw_event_id)
select id from public.telemetry_events where received_at>=now()-interval '30 days'
  and event_name in ('cloud.push_failed','cloud.restore_failed','chord.rendered_correction_applied')
order by received_at desc,id limit 25000 on conflict do nothing;

do $$ begin
    if to_regprocedure('cron.schedule(text,text,text)') is null then
        raise exception 'pg_cron must be available before the telemetry evaluator is configured';
    end if;
end; $$;
select cron.schedule('ichart-telemetry-feature-contracts','*/5 * * * *',
    'select private.process_telemetry_evaluations(250);');
commit;
