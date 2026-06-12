begin;

select plan(18);

insert into auth.users (id, email)
values
    ('00000000-0000-0000-0000-000000000001', 'owner@example.com'),
    ('00000000-0000-0000-0000-000000000002', 'other@example.com')
on conflict (id) do nothing;

insert into public.chart_documents (
    id,
    owner_id,
    title,
    layout_style,
    remote_revision
) values (
    '10000000-0000-0000-0000-000000000099',
    '00000000-0000-0000-0000-000000000002',
    'Hidden Other Chart',
    'simpleChordSheet',
    1
) on conflict (id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

select lives_ok(
    $$
    insert into public.chart_documents (
        id,
        owner_id,
        title,
        layout_style,
        remote_revision
    ) values (
        '10000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        'Owner Chart',
        'simpleChordSheet',
        1
    )
    $$,
    'owner can insert own chart document'
);

select throws_ok(
    $$
    insert into public.chart_documents (
        id,
        owner_id,
        title,
        layout_style,
        remote_revision
    ) values (
        '10000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000002',
        'Other Chart',
        'simpleChordSheet',
        1
    )
    $$,
    '42501',
    null,
    'owner cannot insert another user chart document'
);

select lives_ok(
    $$
    insert into public.chart_snapshots (
        id,
        chart_id,
        owner_id,
        version,
        chart_json
    ) values (
        '20000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        1,
        '{"id":"10000000-0000-0000-0000-000000000001"}'::jsonb
    )
    $$,
    'owner can insert snapshot for own chart'
);

select lives_ok(
    $$
    update public.chart_documents
    set latest_snapshot_id = '20000000-0000-0000-0000-000000000001'
    where id = '10000000-0000-0000-0000-000000000001'
    $$,
    'owner can point latest snapshot to own chart snapshot'
);

select throws_ok(
    $$
    insert into public.chart_snapshots (
        chart_id,
        owner_id,
        version,
        chart_json
    ) values (
        '10000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000002',
        2,
        '{}'::jsonb
    )
    $$,
    '42501',
    null,
    'owner cannot insert snapshot owned by another user'
);

select is(
    (select count(*)::integer from public.chart_documents),
    1,
    'owner only sees own chart document'
);

select is(
    (select count(*)::integer from public.chart_snapshots),
    1,
    'owner only sees own chart snapshot'
);

select is(
    (select count(*)::integer from public.subscriptions),
    1,
    'owner can read own subscription row created by trigger'
);

select is(
    (
        select provider || ':' || coalesce(app_store_status, 'none')
        from public.subscriptions
        where owner_id = '00000000-0000-0000-0000-000000000001'
    ),
    'none:none',
    'owner can read server-owned subscription authority fields'
);

select lives_ok(
    $$
    update public.profiles
    set payment_summary = 'Processor reference only'
    where id = '00000000-0000-0000-0000-000000000001'
    $$,
    'owner can update client-writable profile fields'
);

select throws_ok(
    $$
    update public.profiles
    set stripe_customer_id = 'cus_client_controlled'
    where id = '00000000-0000-0000-0000-000000000001'
    $$,
    '42501',
    null,
    'client cannot update stripe customer id on profile'
);

select throws_ok(
    $$
    insert into public.subscriptions (
        owner_id,
        plan,
        status
    ) values (
        '00000000-0000-0000-0000-000000000001',
        'studioSubscription',
        'active'
    )
    $$,
    '42501',
    null,
    'client cannot insert subscription rows'
);

select throws_ok(
    $$
    update public.subscriptions
    set plan = 'studioSubscription'
    $$,
    '42501',
    null,
    'client cannot update subscription rows'
);

select throws_ok(
    $$
    update public.subscriptions
    set provider = 'storekit',
        storekit_product_id = 'com.smartchart.app.pro.monthly',
        storekit_original_transaction_id = '1000000000000001',
        app_store_status = 'active',
        last_verified_at = now()
    $$,
    '42501',
    null,
    'client cannot update app store subscription authority fields'
);

select throws_ok(
    $$
    delete from public.subscriptions
    $$,
    '42501',
    null,
    'client cannot delete subscription rows'
);

select lives_ok(
    $$
    update public.chart_documents
    set deleted_at = now(),
        latest_snapshot_id = null,
        remote_revision = 2
    where id = '10000000-0000-0000-0000-000000000001'
    $$,
    'owner can tombstone own chart document'
);

select is(
    (
        select deleted_at is not null
        from public.chart_documents
        where id = '10000000-0000-0000-0000-000000000001'
    ),
    true,
    'tombstoned chart keeps deletion metadata'
);

select throws_ok(
    $$
    update public.chart_documents
    set latest_snapshot_id = gen_random_uuid()
    where id = '10000000-0000-0000-0000-000000000001'
    $$,
    '42501',
    null,
    'latest snapshot pointer cannot reference a missing snapshot'
);

select * from finish();

rollback;
