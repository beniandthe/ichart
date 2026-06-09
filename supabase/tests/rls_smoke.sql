begin;

select plan(12);

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

select is_empty(
    $$
    update public.subscriptions
    set plan = 'studioSubscription'
    returning id
    $$,
    'client cannot update subscription rows'
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
