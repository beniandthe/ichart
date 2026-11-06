begin;
set local statement_timeout = '5s';
select no_plan();

-- Synthetic, rollback-only fixtures. Never run this against production.
insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
values
    ('85000000-0000-4000-8000-000000000001', 'forum-search-caller@example.test', now(),
        '{"first_name":"Search","last_name":"Caller"}'),
    ('85000000-0000-4000-8000-000000000002', 'forum-search-author@example.test', now(),
        '{"first_name":"Search","last_name":"Author"}'),
    ('85000000-0000-4000-8000-000000000003', 'forum-search-blocked@example.test', now(),
        '{"first_name":"Blocked","last_name":"Author"}');

insert into public.forum_songs(
    id, song_title, artist_name, normalized_song_title, normalized_artist_name,
    created_by, updated_at
)
select
    ('86000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
    'Audit Keyset Paging ' || n, 'Synthetic Ensemble',
    lower('Audit Keyset Paging ' || n), 'synthetic ensemble',
    '85000000-0000-4000-8000-000000000001'::uuid,
    case when n = 1 then '2026-01-01T10:00:00.123456+00'::timestamptz
        else '2026-11-01T10:00:00.123456+00'::timestamptz end
from generate_series(1, 86) n;

insert into public.forum_chart_posts(
    id, song_id, owner_id, chart_title, arranger_credit, creator_display_name,
    tags, layout_style, pdf_storage_path, status, ranking_score, published_at
)
select
    ('87000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
    ('86000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
    '85000000-0000-4000-8000-000000000002'::uuid,
    case when n = 1 then 'old-window-needle'
        when n = 86 then 'global-window-needle' else 'Synthetic Chart ' || n end,
    'Synthetic Arranger', 'Synthetic Author', '{}'::text[],
    case when n % 2 = 0 then 'simpleChordSheet' else 'rhythmSectionSheet' end,
    '85000000-0000-4000-8000-000000000002/87000000-0000-4000-8000-'
        || lpad(n::text, 12, '0') || '.pdf',
    'published', case when n = 86 then -9999 else n end,
    '2026-11-01T10:00:00.123456+00'::timestamptz
from generate_series(1, 86) n;

-- These globally higher-ranked posts push the unique target outside a
-- hypothetical 160-post prefilter. None contain either unique search needle.
insert into public.forum_chart_posts(
    id, song_id, owner_id, chart_title, arranger_credit, creator_display_name,
    layout_style, pdf_storage_path, status, ranking_score, published_at
)
select
    ('88000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
    '86000000-0000-4000-8000-000000000002'::uuid,
    '85000000-0000-4000-8000-000000000002'::uuid,
    'Ranking Filler ' || n, 'Synthetic Arranger', 'Synthetic Author',
    'simpleChordSheet',
    '85000000-0000-4000-8000-000000000002/88000000-0000-4000-8000-'
        || lpad(n::text, 12, '0') || '.pdf',
    'published', 1000 + n, '2026-11-01T10:00:00.123456+00'::timestamptz
from generate_series(1, 170) n;

-- Matching happens before the per-song top-three ranking cutoff.
insert into public.forum_chart_posts(
    id, song_id, owner_id, chart_title, arranger_credit, creator_display_name,
    layout_style, pdf_storage_path, status, ranking_score, published_at
)
select
    ('89000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
    '86000000-0000-4000-8000-000000000085'::uuid,
    '85000000-0000-4000-8000-000000000002'::uuid,
    'Arrangement ' || n,
    case when n = 4 then 'fourth-arrangement-needle' else 'Other Arranger' end,
    'Synthetic Author', 'rhythmSectionSheet',
    '85000000-0000-4000-8000-000000000002/89000000-0000-4000-8000-'
        || lpad(n::text, 12, '0') || '.pdf',
    'published', 900 - n, '2026-11-01T10:00:00.123456+00'::timestamptz
from generate_series(1, 4) n;

insert into public.forum_songs(
    id, song_title, artist_name, normalized_song_title, normalized_artist_name, created_by
)
values (
    '86000000-0000-4000-8000-000000000087', 'Visibility Probe', 'Synthetic Ensemble',
    'visibility probe', 'synthetic ensemble', '85000000-0000-4000-8000-000000000001'
), (
    '86000000-0000-4000-8000-000000000088', 'Literal 100% _ Punctuation', 'Synthetic Ensemble',
    'literal 100% _ punctuation', 'synthetic ensemble', '85000000-0000-4000-8000-000000000001'
), (
    '86000000-0000-4000-8000-000000000089', U&'Accent Cafe\0301', 'Synthetic Ensemble',
    lower(U&'Accent Cafe\0301'), 'synthetic ensemble', '85000000-0000-4000-8000-000000000001'
), (
    '86000000-0000-4000-8000-000000000090', U&'\0130STANBUL \039F\03A3', 'Synthetic Ensemble',
    lower(U&'\0130STANBUL \039F\03A3'), 'synthetic ensemble', '85000000-0000-4000-8000-000000000001'
);

insert into public.forum_chart_posts(
    id, song_id, owner_id, chart_title, arranger_credit, creator_display_name,
    tags, layout_style, pdf_storage_path, status, ranking_score, published_at
)
select
    ('90000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
    '86000000-0000-4000-8000-000000000087'::uuid,
    owner_id, 'Visibility Chart ' || n, 'visibility-only-needle', 'Synthetic Author',
    '{}'::text[], case when n = 2 then 'leadSheet' else 'simpleChordSheet' end,
    owner_id::text || '/90000000-0000-4000-8000-' || lpad(n::text, 12, '0') || '.pdf',
    status, n, '2026-11-01T10:00:00.123456+00'::timestamptz
from (values
    (1, '85000000-0000-4000-8000-000000000002'::uuid, 'published'),
    (2, '85000000-0000-4000-8000-000000000002'::uuid, 'flagged'),
    (3, '85000000-0000-4000-8000-000000000001'::uuid, 'pending'),
    (4, '85000000-0000-4000-8000-000000000002'::uuid, 'hidden'),
    (5, '85000000-0000-4000-8000-000000000002'::uuid, 'removed'),
    (6, '85000000-0000-4000-8000-000000000003'::uuid, 'published')
) fixtures(n, owner_id, status);

insert into public.forum_chart_posts(
    id, song_id, owner_id, chart_title, arranger_credit, creator_display_name,
    tags, layout_style, pdf_storage_path, status
)
values (
    '90000000-0000-4000-8000-000000000088',
    '86000000-0000-4000-8000-000000000088', '85000000-0000-4000-8000-000000000002',
    'Literal Chart', 'Synthetic Arranger', 'Synthetic Author', array[$q$') OR true --$q$],
    'simpleChordSheet', '85000000-0000-4000-8000-000000000002/90000000-0000-4000-8000-000000000088.pdf',
    'published'
), (
    '90000000-0000-4000-8000-000000000089',
    '86000000-0000-4000-8000-000000000089', '85000000-0000-4000-8000-000000000002',
    'Accent Chart', 'Synthetic Arranger', 'Synthetic Author', '{}'::text[],
    'rhythmSectionSheet', '85000000-0000-4000-8000-000000000002/90000000-0000-4000-8000-000000000089.pdf',
    'published'
), (
    '90000000-0000-4000-8000-000000000090',
    '86000000-0000-4000-8000-000000000090', '85000000-0000-4000-8000-000000000002',
    'Unicode Case Chart', 'Synthetic Arranger', 'Synthetic Author', '{}'::text[],
    'simpleChordSheet', '85000000-0000-4000-8000-000000000002/90000000-0000-4000-8000-000000000090.pdf',
    'published'
);

insert into public.forum_user_blocks(owner_id, blocked_owner_id)
values ('85000000-0000-4000-8000-000000000001', '85000000-0000-4000-8000-000000000003');

create temporary table forum_search_test_pages(page integer, payload jsonb);
grant select, insert on forum_search_test_pages to authenticated;

select ok(not has_function_privilege('anon',
    'public.search_forum_home(text,integer,timestamptz,uuid)', 'EXECUTE'),
    'anonymous clients cannot execute forum search');
select ok(not has_function_privilege('service_role',
    'public.search_forum_home(text,integer,timestamptz,uuid)', 'EXECUTE'),
    'forum search grants only the intended client role');
select ok((select not prosecdef and provolatile = 's' from pg_proc
    where oid = 'public.search_forum_home(text,integer,timestamptz,uuid)'::regprocedure),
    'forum search is stable and security invoker');

set local role authenticated;
select set_config('request.jwt.claim.sub', '85000000-0000-4000-8000-000000000001', true);

select is((public.search_forum_home('old-window-needle')->'songs'->0->'song'->>'id'),
    '86000000-0000-4000-8000-000000000001', 'search reaches a song older than the latest eighty');
select is((public.search_forum_home('global-window-needle')->'songs'->0->'posts'->0->>'id'),
    '87000000-0000-4000-8000-000000000086', 'search reaches a post below the global top160');
select is((public.search_forum_home('fourth-arrangement-needle')->'songs'->0->'posts'->0->>'id'),
    '89000000-0000-4000-8000-000000000004', 'post matching precedes the per-song topthree cutoff');
select is(jsonb_array_length(public.search_forum_home('fourth-arrangement-needle')->'songs'->0->'posts'),
    1, 'post-only search excludes unrelated higher-ranked arrangements');
select is(jsonb_array_length(public.search_forum_home('Audit Keyset Paging 85')->'songs'->0->'posts'),
    3, 'song metadata match still returns its topthree ranked visible posts');
select is((public.search_forum_home('Audit Keyset Paging 85')->'songs'->0->'posts'->0->>'id'),
    '89000000-0000-4000-8000-000000000001', 'matching posts keep score ordering');
select is(jsonb_array_length(public.search_forum_home('100% _')->'songs'), 1,
    'percent and underscore are literal substrings, not wildcard operators');
select is(jsonb_array_length(public.search_forum_home($q$') OR true --$q$)->'songs'), 1,
    'query punctuation remains data rather than SQL/PostgREST syntax');
select is((public.search_forum_home(U&'  ACCENT\0009CAF\00c9  ')->'songs'->0->'song'->>'id'),
    '86000000-0000-4000-8000-000000000089', 'whitespace case and canonical accent normalization match');
-- Exact scalar sequences emitted by ForumHomeSearchParameters in the native
-- wire regression test. Preserve case until PostgreSQL handles both sides;
-- Swift and PostgreSQL can disagree when lowercasing uppercase Greek sigma.
select is((public.search_forum_home(U&'\0130STANBUL')->'songs'->0->'song'->>'id'),
    '86000000-0000-4000-8000-000000000090', 'serialized case-preserved dotted-I query matches database-normalized metadata');
select is((public.search_forum_home(U&'\039F\03A3')->'songs'->0->'song'->>'id'),
    '86000000-0000-4000-8000-000000000090', 'serialized case-preserved Greek query matches database-normalized metadata');
select is(jsonb_array_length(public.search_forum_home('visibility-only-needle')->'songs'->0->'posts'),
    2, 'RLS excludes blocked contributors and feed excludes hidden removed and ownpending posts');
select is((public.search_forum_home('visibility-only-needle')->'songs'->0->'posts'->0->>'layout_style'),
    'leadSheet', 'legacy layout style remains unchanged in returned metadata');
select is(jsonb_array_length(public.search_forum_home('unmatched-unique-audit-term')->'songs'),
    0, 'unmatched search returns an empty page');
select ok(public.search_forum_home('unmatched-unique-audit-term')->'next_cursor' = 'null'::jsonb,
    'empty result has no continuation cursor');
select is(jsonb_array_length(public.search_forum_home('audit keyset paging', 999)->'songs'),
    20, 'response size clamps to twenty groups');
select is(jsonb_array_length(public.search_forum_home('', 20)->'songs'),
    20, 'empty query is supported without fetching all history');
select ok(position('.123456' in public.search_forum_home('audit keyset paging')->'next_cursor'->>'updated_at') > 0,
    'cursor retains database timestamp microseconds');
select is(public.search_forum_home('audit keyset paging')->'songs'->19->'song'->>'updated_at',
    public.search_forum_home('audit keyset paging')->'next_cursor'->>'updated_at',
    'last included song and cursor expose the same exact timestamp string');
select throws_ok($$select public.search_forum_home(repeat('x',201))$$,
    '22023', null, 'oversized search is rejected rather than truncated');
select throws_ok($$select public.search_forum_home('needle',0)$$,
    '22023', null, 'nonpositive page size is rejected');
select throws_ok($$select public.search_forum_home('needle',20,now(),null)$$,
    '22023', null, 'partial timestamp-only cursor is rejected');
select throws_ok($$select public.search_forum_home('needle',20,null,'86000000-0000-4000-8000-000000000001')$$,
    '22023', null, 'partial id-only cursor is rejected');
select throws_ok($$select public.search_forum_home('needle',20,'infinity','86000000-0000-4000-8000-000000000001')$$,
    '22023', null, 'nonfinite cursor is rejected');

do $$
declare
    response jsonb;
    cursor_time timestamptz := null;
    cursor_id uuid := null;
begin
    for page_number in 1..6 loop
        response := public.search_forum_home('audit keyset paging',20,cursor_time,cursor_id);
        insert into forum_search_test_pages values(page_number,response);
        exit when response->'next_cursor' = 'null'::jsonb;
        cursor_time := (response->'next_cursor'->>'updated_at')::timestamptz;
        cursor_id := (response->'next_cursor'->>'id')::uuid;
    end loop;
end;
$$;

select is((select sum(jsonb_array_length(payload->'songs'))::integer from forum_search_test_pages),
    86, 'keyset traversal reaches every matching song beyond the original window');
select is((select count(distinct song->'song'->>'id')::integer
    from forum_search_test_pages, lateral jsonb_array_elements(payload->'songs') song),
    86, 'timestamp ties do not repeat or omit song identities');
select ok((select bool_and(jsonb_array_length(payload->'songs') <= 20) from forum_search_test_pages),
    'every continuation page stays within the group bound');
select ok((select bool_and(jsonb_array_length(song->'posts') <= 3)
    from forum_search_test_pages, lateral jsonb_array_elements(payload->'songs') song),
    'every group stays within three ranked matching posts');
select is(
    (select array_agg(song->'song'->>'id' order by page, item_position)
        from forum_search_test_pages,
        lateral jsonb_array_elements(payload->'songs') with ordinality expanded(song,item_position)),
    (select array_agg(id::text order by updated_at desc,id desc)
        from public.forum_songs where song_title like 'Audit Keyset Paging %'),
    'pagination preserves exact timestamp and UUID tie ordering'
);
select ok((select payload->'next_cursor' = 'null'::jsonb from forum_search_test_pages order by page desc limit 1),
    'last page reports exhaustion');

select set_config('request.jwt.claim.sub', '', true);
select is(jsonb_array_length(public.search_forum_home('audit')->'songs'),0,
    'stale authenticated role without signedin identity sees no results');
reset role;

insert into private.free_pro_beta_memberships(owner_id,participating)
values ('85000000-0000-4000-8000-000000000001',false);
set local role authenticated;
select set_config('request.jwt.claim.sub', '85000000-0000-4000-8000-000000000001', true);
select is(jsonb_array_length(public.search_forum_home('audit')->'songs'),0,
    'explicit Basic participation blocks forum search through current policy');
reset role;

select * from finish();
rollback;
