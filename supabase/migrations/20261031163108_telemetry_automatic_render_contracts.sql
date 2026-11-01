-- Extend the existing telemetry pipeline for selective automatic rendering.
-- Only bounded local comparison results and refusal reasons reach this schema;
-- no raw ink, chord text, chart content, permissions or scheduling changes.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

alter table private.telemetry_contract_definitions
  drop constraint telemetry_contract_definitions_evidence_kind_check;
alter table private.telemetry_contract_definitions
  add constraint telemetry_contract_definitions_evidence_kind_check
  check (evidence_kind in ('contract_violation','operation_failure','friction'));

update private.telemetry_contract_definitions
set allowed_reasons=allowed_reasons||array['render_retained_source_changed','render_consumed_source_remaining']
where contract_id='ink.render_preservation' and contract_version=1;

insert into private.telemetry_contract_definitions values
('ink.automatic_render_completion',1,'recognition_workflow','medium','friction',
 'Automatic rendering required intervention',array['automatic_no_read','automatic_recognition_review',
 'automatic_needs_space','automatic_placement_unavailable','automatic_unrepresented_ink','automatic_adjacent_writing']);

create or replace function private.classify_telemetry_event(event_row public.telemetry_events)
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
block_duration_ms numeric;
content_mismatch boolean := event_row.properties->'content_matches'='false'::jsonb;
begin
    if event_row.platform not in ('iPadOS','iOS') then return; end if;
    if event_row.event_name='feature.contract_checked' then
        -- A safe refusal is workflow friction, never an ink-loss or accuracy
        -- claim. Every automatic-completion event returns from this branch, so
        -- changing its outcome to 'violated' cannot bypass the dwell/evidence gate.
        if event_row.properties->>'contract_id'='ink.automatic_render_completion' then
            if event_row.properties->'contract_version' is distinct from '1'::jsonb
               or coalesce(event_row.properties->>'operation_id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
               or event_row.properties->>'outcome' is distinct from 'protected_rejection'
               or event_row.properties->>'operation' is distinct from 'render'
               or coalesce(event_row.properties->>'render_mode','') not in ('automatic','reviewed_automatic')
            then return; end if;
            select * into definition from private.telemetry_contract_definitions d
              where d.contract_id='ink.automatic_render_completion' and d.contract_version=1;
            if not found or reason is null or not (reason=any(definition.allowed_reasons)) then return; end if;
            if jsonb_typeof(event_row.properties->'actual_count')='number'
               and (event_row.properties->>'actual_count') ~ '^[0-9]{1,13}$' then
                actual_count:=(event_row.properties->>'actual_count')::numeric; end if;
            -- JSONB numbers are finite PostgreSQL numeric values. Admit native
            -- Double precision without a decimal-format/fraction-length filter;
            -- the numeric bounds below reject negative and excessive durations.
            if jsonb_typeof(event_row.properties->'duration_ms')='number' then
                block_duration_ms:=(event_row.properties->>'duration_ms')::numeric; end if;
            if actual_count is null or actual_count<=0 or actual_count>1000000000000
               or block_duration_ms is null or block_duration_ms<3000 or block_duration_ms>86400000 then return; end if;
            return query select 'contract.'||definition.contract_id||'.'||reason,1,
              definition.category,definition.severity,definition.evidence_kind,
              case reason
                when 'automatic_no_read' then 'Automatic rendering needs a readable result'
                when 'automatic_recognition_review' then 'Automatic rendering requires chord review after settling'
                when 'automatic_needs_space' then 'Automatic rendering is blocked by a placement collision'
                when 'automatic_placement_unavailable' then 'Automatic rendering could not find safe placement'
                when 'automatic_unrepresented_ink' then 'Automatic rendering left ungrouped source ink'
                when 'automatic_adjacent_writing' then 'Automatic rendering could not separate adjacent writing'
                else definition.title end;
            return;
        end if;
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
        if reason in ('render_retained_source_changed','render_consumed_source_remaining')
           and content_mismatch is distinct from true then return; end if;
        if reason='render_source_missing' and not coalesce(content_mismatch or expected_count>actual_count,false) then return; end if;
        if reason='render_rejected_mutated' and not coalesce(content_mismatch or expected_count<>actual_count or expected_bytes<>actual_bytes,false) then return; end if;
        if reason='render_canvas_not_cleared' and (expected_count is distinct from 0 or actual_count is null or actual_count<=0) then return; end if;
        return query select 'contract.'||definition.contract_id||'.'||reason,1,
            definition.category,
            case when reason in ('render_canvas_not_cleared','render_consumed_source_remaining') then 'medium'
                 when reason='readback_failed' then 'high' else definition.severity end,
            case when reason='readback_failed' then 'operation_failure' else definition.evidence_kind end,
            case when reason='readback_failed' then 'Saved chart could not be read back'
                 when reason='render_canvas_not_cleared' then 'Rendered ink canvas did not clear'
                 when reason='render_retained_source_changed' then 'Automatic rendering changed source ink that should remain'
                 when reason='render_consumed_source_remaining' then 'Automatic rendering left already-consumed source ink'
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

commit;
