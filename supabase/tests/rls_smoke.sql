begin;

select no_plan();

insert into auth.users (id, email, raw_user_meta_data)
values
    (
        '00000000-0000-0000-0000-000000000001',
        'owner@example.com',
        '{"first_name":"Beni","last_name":"Rossman"}'::jsonb
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'other@example.com',
        '{"first_name":"Other","last_name":"Player"}'::jsonb
    )
on conflict (id) do nothing;

update public.profiles
set first_name = 'Beni',
    last_name = 'Rossman'
where id = '00000000-0000-0000-0000-000000000001';

update public.profiles
set first_name = 'Other',
    last_name = 'Player'
where id = '00000000-0000-0000-0000-000000000002';

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

select throws_ok(
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
    '42501',
    null,
    'inactive Basic user cannot insert own cloud chart document'
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
    'active Pro can insert own cloud chart document'
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
    'manual:none',
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
    update public.profiles
    set first_name = 'Changed',
        last_name = 'Name'
    where id = '00000000-0000-0000-0000-000000000001'
    $$,
    '42501',
    null,
    'client cannot update locked profile name fields'
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
        storekit_product_id = 'com.ichart.app.pro.monthly',
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
    'active Pro can submit forum chart post metadata for review'
);

select is(
    (
        select status
        from public.forum_chart_posts
        where id = '40000000-0000-0000-0000-000000000001'
    ),
    'pending',
    'new forum chart posts start pending review'
);

select is(
    (
        select creator_display_name
        from public.forum_chart_posts
        where id = '40000000-0000-0000-0000-000000000001'
    ),
    'Beni Rossman',
    'forum chart post attribution is derived from locked profile name'
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
        '40000000-0000-0000-0000-000000000002',
        '30000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001',
        'Blue Bossa Spoof Attempt',
        'Beni Rossman',
        'Fake Name',
        array['standard'],
        null,
        'simpleChordSheet',
        '00000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000002.pdf'
    )
    $$,
    'server accepts own forum post while overriding spoofed attribution'
);

select is(
    (
        select creator_display_name
        from public.forum_chart_posts
        where id = '40000000-0000-0000-0000-000000000002'
    ),
    'Beni Rossman',
    'spoofed forum attribution is overwritten by locked profile name'
);

select is(
    (select count(*)::integer from public.forum_songs),
    1,
    'active Pro can read visible forum song metadata'
);

select is(
    (select count(*)::integer from public.forum_chart_posts),
    2,
    'active Pro can read own pending forum chart posts'
);

reset role;

update public.subscriptions
set plan = 'studioSubscription',
    status = 'active',
    provider = 'manual',
    entitlement_expires_at = now() + interval '30 days',
    revoked_at = null
where owner_id = '00000000-0000-0000-0000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);

select is(
    (
        select count(*)::integer
        from public.forum_chart_posts
        where id = '40000000-0000-0000-0000-000000000001'
    ),
    0,
    'another active Pro cannot read pending forum chart posts'
);

select is(
    (
        select count(*)::integer
        from public.forum_songs
        where id = '30000000-0000-0000-0000-000000000001'
    ),
    0,
    'another active Pro cannot read song metadata that only has pending posts'
);

reset role;

update public.forum_chart_posts
set status = 'published'
where id = '40000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

select lives_ok(
    $$
    insert into storage.objects (
        id,
        bucket_id,
        name,
        owner,
        metadata
    ) values (
        '80000000-0000-0000-0000-000000000001',
        'forum_chart_pdfs',
        '00000000-0000-0000-0000-000000000001/orphan.pdf',
        '00000000-0000-0000-0000-000000000001',
        '{"mimetype":"application/pdf"}'::jsonb
    )
    $$,
    'active Pro can upload forum PDF metadata in own folder'
);

set local storage.allow_delete_query = 'true';

select lives_ok(
    $$
    delete from storage.objects
    where bucket_id = 'forum_chart_pdfs'
        and name = '00000000-0000-0000-0000-000000000001/orphan.pdf'
    $$,
    'active Pro can delete unattached forum PDF metadata for publish rollback'
);

select is(
    (
        select count(*)::integer
        from storage.objects
        where bucket_id = 'forum_chart_pdfs'
            and name = '00000000-0000-0000-0000-000000000001/orphan.pdf'
    ),
    0,
    'unattached forum PDF metadata is removed by publish rollback'
);

select lives_ok(
    $$
    insert into storage.objects (
        id,
        bucket_id,
        name,
        owner,
        metadata
    ) values (
        '80000000-0000-0000-0000-000000000002',
        'forum_chart_pdfs',
        '00000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001.pdf',
        '00000000-0000-0000-0000-000000000001',
        '{"mimetype":"application/pdf"}'::jsonb
    )
    $$,
    'active Pro can upload forum PDF metadata for published post'
);

select is(
    (
        select count(*)::integer
        from storage.objects
        where bucket_id = 'forum_chart_pdfs'
            and name = '00000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001.pdf'
    ),
    0,
    'unvalidated forum PDF metadata is not downloadable even when the post is published'
);

reset role;

select private.finalize_forum_chart_post_pdf('40000000-0000-0000-0000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local storage.allow_delete_query = 'true';

select is(
    (
        select count(*)::integer
        from storage.objects
        where bucket_id = 'forum_chart_pdfs'
            and name = '00000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001.pdf'
    ),
    1,
    'validated forum PDF metadata is downloadable for a published post'
);

select lives_ok(
    $$
    delete from storage.objects
    where bucket_id = 'forum_chart_pdfs'
        and name = '00000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001.pdf'
    $$,
    'active Pro delete attempt against attached forum PDF metadata does not error'
);

select is(
    (
        select count(*)::integer
        from storage.objects
        where bucket_id = 'forum_chart_pdfs'
            and name = '00000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001.pdf'
    ),
    1,
    'attached forum PDF metadata remains frozen after delete attempt'
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
        id,
        song_id,
        owner_id,
        chart_title,
        arranger_credit,
        creator_display_name,
        layout_style,
        pdf_storage_path
    ) values (
        '40000000-0000-0000-0000-000000000003',
        '30000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000002',
        'Cross Owner Chart',
        'Other',
        'Other',
        'simpleChordSheet',
        '00000000-0000-0000-0000-000000000002/40000000-0000-0000-0000-000000000003.pdf'
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

reset role;

update public.forum_chart_posts
set status = 'hidden'
where id = '40000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

select is(
    (
        select count(*)::integer
        from public.forum_chart_posts
        where id = '40000000-0000-0000-0000-000000000001'
    ),
    0,
    'active Pro cannot read hidden forum posts'
);

select lives_ok(
    $$
    update public.forum_votes
    set vote_value = 1
    where id = '50000000-0000-0000-0000-000000000001'
    $$,
    'vote update against hidden forum post is filtered without error'
);

reset role;

select is(
    (
        select vote_value::integer
        from public.forum_votes
        where id = '50000000-0000-0000-0000-000000000001'
    ),
    -1,
    'hidden forum post keeps existing vote value frozen'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

select lives_ok(
    $$
    delete from public.forum_votes
    where id = '50000000-0000-0000-0000-000000000001'
    $$,
    'vote delete against hidden forum post is filtered without error'
);

reset role;

select is(
    (
        select count(*)::integer
        from public.forum_votes
        where id = '50000000-0000-0000-0000-000000000001'
    ),
    1,
    'hidden forum post keeps existing vote row frozen'
);

select * from finish();

rollback;
