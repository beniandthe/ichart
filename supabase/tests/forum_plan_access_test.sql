begin;
set local statement_timeout = '5s';
select no_plan();

-- Synthetic rollback-only forum access matrix. Never target a linked project.
insert into auth.users(id, email, email_confirmed_at, phone_confirmed_at, banned_until,
    deleted_at, is_anonymous, raw_user_meta_data)
select ('96000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
    'forum-plan-' || n || '@example.test',
    case when n not in (3,7) then now() end,
    case when n = 7 then now() end,
    case when n = 4 then now() + interval '1 day' end,
    case when n = 6 then now() end,
    n = 5, '{"first_name":"Plan","last_name":"Fixture"}'::jsonb
from generate_series(1,9) n;
insert into private.free_pro_beta_memberships(owner_id, participating)
select ('96000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid, false
from generate_series(1,7) n;
update public.subscriptions set plan='studioSubscription', status='active',
    provider='storekit', app_store_status='active', entitlement_expires_at=now()+interval '1 day',
    last_verified_at=now()
where owner_id='96000000-0000-4000-8000-000000000002';

insert into public.forum_songs(id, song_title, artist_name, normalized_song_title,
    normalized_artist_name, created_by)
select ('96100000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
    'Plan Song '||n, 'Fixture Artist', lower('Plan Song '||n), 'fixture artist',
    '96000000-0000-4000-8000-000000000002'
from generate_series(1,8) n;

insert into public.forum_chart_posts(id, song_id, owner_id, chart_title, arranger_credit,
    creator_display_name, layout_style, pdf_storage_path, status)
select ('96200000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
    ('96100000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
    owner_id, 'Plan Chart '||n, 'Fixture Arranger', 'Plan F.',
    case when n % 2=0 then 'rhythmSectionSheet' else 'simpleChordSheet' end,
    owner_id::text||'/96200000-0000-4000-8000-'||lpad(n::text,12,'0')||'.pdf', status
from (values
    (1,'96000000-0000-4000-8000-000000000002'::uuid,'published'),
    (2,'96000000-0000-4000-8000-000000000002'::uuid,'flagged'),
    (3,'96000000-0000-4000-8000-000000000002'::uuid,'hidden'),
    (4,'96000000-0000-4000-8000-000000000002'::uuid,'removed'),
    (5,'96000000-0000-4000-8000-000000000001'::uuid,'pending'),
    (6,'96000000-0000-4000-8000-000000000002'::uuid,'pending'),
    (7,'96000000-0000-4000-8000-000000000009'::uuid,'published'),
    (8,'96000000-0000-4000-8000-000000000008'::uuid,'pending')
) fixture(n,owner_id,status);

insert into public.forum_comments(id,post_id,owner_id,body,status)
select ('96300000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
    post_id,owner_id,'Plan comment fixture',status
from (values
    (1,'96200000-0000-4000-8000-000000000001'::uuid,'96000000-0000-4000-8000-000000000002'::uuid,'visible'),
    (2,'96200000-0000-4000-8000-000000000001'::uuid,'96000000-0000-4000-8000-000000000002'::uuid,'hidden'),
    (3,'96200000-0000-4000-8000-000000000003'::uuid,'96000000-0000-4000-8000-000000000002'::uuid,'visible'),
    (4,'96200000-0000-4000-8000-000000000001'::uuid,'96000000-0000-4000-8000-000000000009'::uuid,'visible')
) fixture(n,post_id,owner_id,status);
insert into public.forum_author_badges(owner_id,badge_type)
values ('96000000-0000-4000-8000-000000000002','trustedArranger');

insert into storage.objects(id,bucket_id,name,owner,metadata)
values ('96400000-0000-4000-8000-000000000001','forum_chart_pdfs',
    '96000000-0000-4000-8000-000000000002/96200000-0000-4000-8000-000000000001.pdf',
    '96000000-0000-4000-8000-000000000002', '{"size":128,"mimetype":"application/pdf"}');
select public.finalize_forum_chart_post_pdf('96200000-0000-4000-8000-000000000001',128,repeat('a',64));

select is((select enabled from private.ichart_paid_feature_policy),false,
    'migration preserves beta until the explicit server rollout');
select ok(not has_function_privilege('anon','public.current_user_can_read_forum()','execute'),
    'anonymous cannot invoke the verified forum helper');
select ok(not has_function_privilege('service_role','public.current_user_can_read_forum()','execute'),
    'forum read helper has only its intended authenticated grant');
select ok(not has_table_privilege('authenticated','private.ichart_paid_feature_policy','update'),
    'clients cannot change the paid rollout');
select ok(not has_table_privilege('service_role','private.ichart_paid_feature_policy','update'),
    'service clients cannot change the paid rollout');

set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000008',true);
select is(public.current_user_has_active_pro(),true,'default beta account retains existing Pro access');
reset role;

-- This changes only this transaction's synthetic rollout state.
update private.ichart_paid_feature_policy set enabled=true where singleton;
set local role authenticated;
select is(public.current_user_has_free_pro_access(),false,'paid phase ends beta feature authority');
select is((public.free_pro_beta_status()->>'participating')::boolean,true,
    'paid phase retains truthful beta membership record');
select is((public.free_pro_beta_status()->>'beta_available')::boolean,false,
    'beta status reports the paid rollout');
select throws_ok($$select public.set_free_pro_beta_participation(true,
    '96000000-0000-4000-8000-000000000008')$$,'55000',null,
    'beta rejoin cannot bypass the paid rollout');
select is(public.current_user_has_active_pro(),false,'paid phase rejects beta-only publishing access');

select is(public.current_user_can_read_forum(),true,'beta-only account retains verified browsing in paid phase');
select throws_ok($$insert into public.forum_votes(post_id,owner_id,vote_value)
    values('96200000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000008',1)$$,
    '42501',null,'beta-only account cannot vote in paid phase');
reset role;
set local role service_role;
select throws_ok($$select public.publish_forum_chart_post('96200000-0000-4000-8000-000000000008',
    '96000000-0000-4000-8000-000000000008',128,repeat('a',64))$$,
    '42501',null,'atomic publisher rechecks paid authority despite privileged Edge access');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000001',true);
select is(public.current_user_has_active_pro(),false,'verified Basic account has no paid authoring access');
select is(public.current_user_can_read_forum(),true,'verified Basic account can browse');
select is((select count(*)::integer from public.forum_chart_posts where id::text like '96200000%'),4,
    'Basic sees published flagged and own pending metadata only');
select is((select count(*)::integer from public.forum_songs where id::text like '96100000%'),4,
    'Basic song visibility matches published and own pending metadata');
select is((select count(*)::integer from public.forum_comments where id::text like '96300000%'),2,
    'Basic sees visible comments only on visible posts');
select is((select count(*)::integer from public.forum_author_badges
    where owner_id='96000000-0000-4000-8000-000000000002'),1,
    'Basic can read contributor badges');
select is(jsonb_array_length(public.search_forum_home('Plan Song')->'songs'),3,
    'Basic search includes published and flagged songs without pending songs');
select is((select count(*)::integer from public.forum_votes),0,'Basic vote detail returns an empty result');
select is((select count(*)::integer from storage.objects where id='96400000-0000-4000-8000-000000000001'),0,
    'Basic cannot read a validated forum PDF storage object');

select throws_ok($$insert into public.forum_songs(song_title,artist_name,
    normalized_song_title,normalized_artist_name,created_by)
    values('New Song','Fixture','new song','fixture','96000000-0000-4000-8000-000000000001')$$,
    '42501',null,'Basic cannot create forum song metadata');
select throws_ok($$insert into public.forum_chart_posts(id,song_id,owner_id,chart_title,arranger_credit,
    creator_display_name,layout_style,pdf_storage_path)
    values('96200000-0000-4000-8000-000000000099','96100000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000001',
    'Basic Chart','Fixture','Plan F.','simpleChordSheet',
    '96000000-0000-4000-8000-000000000001/96200000-0000-4000-8000-000000000099.pdf')$$,
    '42501',null,'Basic cannot submit new chart metadata');
select throws_ok($$insert into public.forum_comments(post_id,owner_id,body)
    values('96200000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000001','New comment')$$,
    '42501',null,'Basic cannot add a comment');
select throws_ok($$insert into public.forum_votes(post_id,owner_id,vote_value)
    values('96200000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000001',1)$$,
    '42501',null,'Basic cannot vote');
select throws_ok($$insert into storage.objects(bucket_id,name,owner)
    values('forum_chart_pdfs','96000000-0000-4000-8000-000000000001/new.pdf',
    '96000000-0000-4000-8000-000000000001')$$,
    '42501',null,'Basic cannot upload a new forum PDF');
select lives_ok($$insert into public.forum_reports(owner_id,target_type,post_id,reason)
    values('96000000-0000-4000-8000-000000000001','post','96200000-0000-4000-8000-000000000001','abuse')$$,
    'Basic can report a visible post');
select lives_ok($$insert into public.forum_reports(owner_id,target_type,comment_id,reason)
    values('96000000-0000-4000-8000-000000000001','comment','96300000-0000-4000-8000-000000000001','abuse')$$,
    'Basic can report a visible comment');
select throws_ok($$insert into public.forum_reports(owner_id,target_type,post_id,reason)
    values('96000000-0000-4000-8000-000000000002','post','96200000-0000-4000-8000-000000000001','abuse')$$,
    '42501',null,'Basic cannot impersonate another reporter');
select throws_ok($$insert into public.forum_reports(owner_id,target_type,post_id,reason)
    values('96000000-0000-4000-8000-000000000001','post','96200000-0000-4000-8000-000000000003','abuse')$$,
    '42501',null,'Basic cannot report hidden content through a guessed id');
select lives_ok($$insert into public.forum_user_blocks(owner_id,blocked_owner_id)
    values('96000000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000009')$$,
    'Basic can block a contributor');
select is((select count(*)::integer from public.forum_chart_posts where id::text like '96200000%'),3,
    'blocked author post is hidden from Basic detail');
select is((select count(*)::integer from public.forum_comments where id::text like '96300000%'),1,
    'blocked author comments are hidden from Basic detail');
select is(jsonb_array_length(public.search_forum_home('Plan Song')->'songs'),2,
    'blocked author metadata is excluded from Basic search');
select lives_ok($$delete from public.forum_user_blocks
    where owner_id='96000000-0000-4000-8000-000000000001'$$,'Basic can unblock a contributor');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000002',true);
select is(public.current_user_has_active_pro(),true,'paid author works even after declining beta');
select is((select count(*)::integer from storage.objects where id='96400000-0000-4000-8000-000000000001'),1,
    'paid author can read proven published PDF');
select is((select count(*)::integer from public.forum_reports where owner_id='96000000-0000-4000-8000-000000000001'),0,
    'report ownership stays private');
select lives_ok($$insert into public.forum_comments(post_id,owner_id,body)
    values('96200000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000002','Paid comment')$$,
    'paid author can comment');
select lives_ok($$insert into public.forum_votes(post_id,owner_id,vote_value)
    values('96200000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000002',1)$$,
    'paid author can vote');

reset role;
update public.subscriptions set app_store_status='grace'
where owner_id='96000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000002',true);
select is(public.current_user_has_active_pro(),false,'paid forum participation pauses during grace');
select is(public.current_user_can_read_forum(),true,'grace keeps verified browsing');
select is((select count(*)::integer from storage.objects where id='96400000-0000-4000-8000-000000000001'),0,
    'grace cannot download new forum PDFs');
reset role;
update public.subscriptions set app_store_status='active', entitlement_expires_at=now()-interval '1 minute'
where owner_id='96000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(public.current_user_has_active_pro(),false,'expired paid-through date denies forum participation');
reset role;
update public.subscriptions set entitlement_expires_at=now()+interval '1 day', revoked_at=now()
where owner_id='96000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(public.current_user_has_active_pro(),false,'revoked subscription denies forum participation');
reset role;
update public.subscriptions set revoked_at=null,last_verified_at=null
where owner_id='96000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(public.current_user_has_active_pro(),false,'unverified paid record cannot grant forum participation');
reset role;
update public.subscriptions set last_verified_at=now()
where owner_id='96000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(public.current_user_has_active_pro(),true,'paid-through cancellation remains active without auto-renew requirement');
reset role;
set local role service_role;
select is((public.run_subscription_retention_jobs()->>'cloud_deleted_events')::integer,0,
    'paid rollout keeps subscription-triggered deletion paused');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000007',true);
select is(public.current_user_can_read_forum(),true,'verified phone account can browse without paid access');

select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000003',true);
select is(public.current_user_can_read_forum(),false,'unverified account is denied browsing');
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000004',true);
select is(public.current_user_can_read_forum(),false,'banned account is denied browsing');
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000005',true);
select is(public.current_user_can_read_forum(),false,'anonymous auth account is denied browsing');
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000006',true);
select is(public.current_user_can_read_forum(),false,'deleted account is denied browsing');
select is(jsonb_array_length(public.search_forum_home('Plan Song')->'songs'),0,
    'deleted account cannot search published metadata');
select throws_ok($$insert into public.forum_reports(owner_id,target_type,post_id,reason)
    values('96000000-0000-4000-8000-000000000006','post','96200000-0000-4000-8000-000000000001','abuse')$$,
    '42501',null,'deleted account cannot submit safety actions');
select set_config('request.jwt.claim.sub','',true);
select is(public.current_user_can_read_forum(),false,'stale authenticated role is denied browsing');
select is(jsonb_array_length(public.search_forum_home('Plan Song')->'songs'),0,
    'stale authenticated role has no search results');
reset role;
select * from finish();
rollback;
