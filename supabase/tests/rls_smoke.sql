begin;

select plan(38);

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

reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);

select throws_ok(
    $$
    insert into public.forum_songs (
        id,
        song_title,
        artist_name,
        normalized_song_title,
        normalized_artist_name,
        created_by
    ) values (
        '30000000-0000-0000-0000-000000000002',
        'Hidden Tune',
        'Other Artist',
        'hidden tune',
        'other artist',
        '00000000-0000-0000-0000-000000000002'
    )
    $$,
    '42501',
    null,
    'inactive Basic user cannot insert forum songs'
);

select is(
    (select count(*)::integer from public.forum_songs),
    0,
    'inactive Basic user cannot read forum songs'
);

reset role;

update public.subscriptions
set plan = 'studioSubscription',
    status = 'active',
    provider = 'manual',
    entitlement_expires_at = now() + interval '30 days',
    revoked_at = null
where owner_id = '00000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

select lives_ok(
    $$
    insert into public.forum_songs (
        id,
        song_title,
        artist_name,
        normalized_song_title,
        normalized_artist_name,
        created_by
    ) values (
        '30000000-0000-0000-0000-000000000001',
        'Blue Bossa',
        'Kenny Dorham',
        'blue bossa',
        'kenny dorham',
        '00000000-0000-0000-0000-000000000001'
    )
    $$,
    'active Pro can insert forum song metadata'
);

select lives_ok(
    $$
    insert into public.forum_chart_posts (
        id,
        song_id,
        owner_id,
        local_chart_id,
        chart_title,
        arranger_credit,
        creator_display_name,
        tags,
        version_note,
        layout_style,
        pdf_storage_path
    ) values (
        '40000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001',
        'Blue Bossa Rhythm Chart',
        'Beni Rossman',
        'Beni Rossman',
        array['rhythm section', 'standard'],
        'Studio form',
        'rhythmSectionSheet',
        '00000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001.pdf'
    )
    $$,
    'active Pro can publish forum chart post metadata'
);

select is(
    (select count(*)::integer from public.forum_songs),
    1,
    'active Pro can read visible forum song metadata'
);

select is(
    (select count(*)::integer from public.forum_chart_posts),
    1,
    'active Pro can read visible forum chart posts'
);

select lives_ok(
    $$
    insert into public.forum_votes (
        id,
        post_id,
        owner_id,
        vote_value
    ) values (
        '50000000-0000-0000-0000-000000000001',
        '40000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        1
    )
    $$,
    'active Pro can vote on visible forum post'
);

select is(
    (
        select vote_up_count
        from public.forum_chart_posts
        where id = '40000000-0000-0000-0000-000000000001'
    ),
    1,
    'forum vote trigger updates upvote aggregate'
);

select lives_ok(
    $$
    update public.forum_votes
    set vote_value = -1
    where id = '50000000-0000-0000-0000-000000000001'
    $$,
    'active Pro can change own vote'
);

select is(
    (
        select vote_down_count
        from public.forum_chart_posts
        where id = '40000000-0000-0000-0000-000000000001'
    ),
    1,
    'forum vote trigger updates downvote aggregate'
);

select throws_ok(
    $$
    insert into public.forum_votes (
        post_id,
        owner_id,
        vote_value
    ) values (
        '40000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        1
    )
    $$,
    '23505',
    null,
    'one user cannot create duplicate votes on one forum post'
);

select lives_ok(
    $$
    insert into public.forum_comments (
        id,
        post_id,
        owner_id,
        body
    ) values (
        '60000000-0000-0000-0000-000000000001',
        '40000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        'Clean form and readable hits.'
    )
    $$,
    'active Pro can comment on visible forum post'
);

select lives_ok(
    $$
    insert into public.forum_reports (
        id,
        owner_id,
        target_type,
        post_id,
        reason,
        detail
    ) values (
        '70000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        'post',
        '40000000-0000-0000-0000-000000000001',
        'wrongChords',
        'Needs one turnaround correction.'
    )
    $$,
    'active Pro can report a visible forum post'
);

select is(
    (
        select report_count
        from public.forum_chart_posts
        where id = '40000000-0000-0000-0000-000000000001'
    ),
    1,
    'forum report trigger updates post report aggregate'
);

select throws_ok(
    $$
    update public.forum_chart_posts
    set status = 'hidden'
    where id = '40000000-0000-0000-0000-000000000001'
    $$,
    '42501',
    null,
    'client cannot update forum moderation status'
);

select throws_ok(
    $$
    update public.forum_chart_posts
    set vote_up_count = 99
    where id = '40000000-0000-0000-0000-000000000001'
    $$,
    '42501',
    null,
    'client cannot update forum aggregate counters'
);

select throws_ok(
    $$
    insert into public.forum_author_badges (
        owner_id,
        badge_type
    ) values (
        '00000000-0000-0000-0000-000000000001',
        'communityExpert'
    )
    $$,
    '42501',
    null,
    'client cannot self-award forum badges'
);

select throws_ok(
    $$
    insert into public.forum_chart_posts (
        song_id,
        owner_id,
        chart_title,
        arranger_credit,
        creator_display_name,
        layout_style,
        pdf_storage_path
    ) values (
        '30000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000002',
        'Cross Owner Chart',
        'Other',
        'Other',
        'simpleChordSheet',
        '00000000-0000-0000-0000-000000000002/cross-owner.pdf'
    )
    $$,
    '42501',
    null,
    'active Pro cannot publish forum post for another owner'
);

select lives_ok(
    $$
    insert into public.forum_reports (
        id,
        owner_id,
        target_type,
        comment_id,
        reason
    ) values (
        '70000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000001',
        'comment',
        '60000000-0000-0000-0000-000000000001',
        'other'
    )
    $$,
    'active Pro can report a visible forum comment'
);

select is(
    (
        select report_count
        from public.forum_comments
        where id = '60000000-0000-0000-0000-000000000001'
    ),
    1,
    'forum report trigger updates comment report aggregate'
);

select * from finish();

rollback;
