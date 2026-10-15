begin;
select no_plan();

-- Synthetic users only; rollback preserves the installed policy and all data.
insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
values
    ('71000000-0000-4000-8000-000000000001', 'free-owner@example.test', now(),
        '{"first_name":"Free","last_name":"Owner"}'),
    ('71000000-0000-4000-8000-000000000002', 'free-other@example.test', now(),
        '{"first_name":"Free","last_name":"Other"}');

set local role authenticated;
select set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);
select is(public.current_user_has_free_pro_access(), true, 'verified Basic account has free access');
select is(public.current_user_has_active_pro(), true, 'legacy RLS helper permits free feature access');
select is((select plan from public.subscriptions), 'free', 'feature access does not fabricate paid plan');
select is((select provider from public.subscriptions), 'none', 'feature access does not fabricate paid provider');
select lives_ok($$
    insert into public.chart_documents(id, owner_id, title, layout_style)
    values ('72000000-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000001',
        'Free retained chart', 'simpleChordSheet')
$$, 'free account can back up own chart');
select throws_ok($$
    insert into public.chart_documents(owner_id, title, layout_style)
    values ('71000000-0000-4000-8000-000000000002', 'Not owned', 'simpleChordSheet')
$$, '42501', null, 'free access does not allow another owner chart');
select throws_ok($$update public.subscriptions set plan='studioSubscription'$$,
    '42501', null, 'free account cannot modify billing authority');
select throws_ok($$delete from private.ichart_free_access_policy$$,
    '42501', null, 'free account cannot end free phase');

select set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000002', true);
select is((select count(*)::integer from public.chart_documents), 0, 'other free account cannot read owner backup');
reset role;

update public.subscriptions
set provider='storekit', app_store_status='refunded', status='inactive', plan='free',
    entitlement_expires_at=now()-interval '2 days', revoked_at=now()-interval '1 day',
    cloud_retention_deadline=now()-interval '1 day'
where owner_id='71000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);
select is(public.current_user_has_free_pro_access(), true, 'refund does not remove separate free access');
select is((select app_store_status from public.subscriptions), 'refunded', 'actual refund evidence stays truthful');
reset role;

insert into private.subscription_retention_events(owner_id, event_type, recipient_email, subject, body, dedupe_key)
values ('71000000-0000-4000-8000-000000000001', 'expiration_warning', 'free-owner@example.test',
    'Synthetic old warning', 'Must never dispatch', 'free-pro-synthetic-queued');
set local role service_role;
select is((public.run_subscription_retention_jobs()->>'cloud_deleted_events')::integer, 0,
    'free period performs no subscription-triggered deletion');
select is((select count(*)::integer from public.claim_subscription_retention_events()), 0,
    'free period claims no queued access-loss mail');
select throws_ok($$select private.run_subscription_retention_jobs_paid_parked()$$,
    '42501', null, 'service role cannot bypass guard via parked destructive implementation');
select throws_ok($$delete from private.ichart_free_access_policy$$,
    '42501', null, 'service role cannot silently end free phase');
reset role;
select is((select count(*)::integer from public.chart_documents
    where id='72000000-0000-4000-8000-000000000001'), 1, 'refunded account backup is preserved');
select ok((select suppressed_at is not null and sent_at is null and dispatch_attempt_count=0
    from private.subscription_retention_events where dedupe_key='free-pro-synthetic-queued'),
    'queued warning suppressed without claiming it was sent');

update auth.users set banned_until=now()+interval '1 day'
where id='71000000-0000-4000-8000-000000000001';
set local role authenticated;
select is(public.current_user_has_free_pro_access(), false, 'ban remains authoritative during free access');
select is(public.current_user_has_active_pro(), false, 'legacy helper also rejects banned account');
reset role;
update auth.users set banned_until=null, email_confirmed_at=null
where id='71000000-0000-4000-8000-000000000001';
set local role authenticated;
select is(public.current_user_has_free_pro_access(), false, 'unverified account is not upgraded by free policy');
reset role;

select * from finish();
rollback;
