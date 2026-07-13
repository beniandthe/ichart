create or replace function private.profile_display_name(target_user_id uuid)
returns text
language sql
security definer
set search_path = public, pg_temp
as $$
    with profile_name as (
        select
            nullif(btrim(first_name), '') as first_name,
            nullif(btrim(last_name), '') as last_name
        from public.profiles
        where id = target_user_id
    )
    select nullif(
        btrim(
            case
                when first_name is not null and last_name is not null
                    then first_name || ' ' || upper(left(last_name, 1)) || '.'
                else concat_ws(' ', first_name, last_name)
            end
        ),
        ''
    )
    from profile_name;
$$;

revoke all on function private.profile_display_name(uuid) from public, anon, authenticated;

alter table public.forum_comments
    add column if not exists creator_display_name text;

update public.forum_comments
set creator_display_name = coalesce(private.profile_display_name(owner_id), 'iChart User')
where creator_display_name is null
    or btrim(creator_display_name) = '';

alter table public.forum_comments
    alter column creator_display_name set not null;

alter table public.forum_comments
    drop constraint if exists forum_comments_creator_display_name_not_empty;

alter table public.forum_comments
    add constraint forum_comments_creator_display_name_not_empty
    check (btrim(creator_display_name) <> '');

create or replace function private.apply_forum_comment_server_fields()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
    profile_display_name text;
begin
    profile_display_name := private.profile_display_name(new.owner_id);
    if profile_display_name is null then
        raise exception 'Forum comments require a locked account name.';
    end if;

    new.creator_display_name := profile_display_name;
    return new;
end;
$$;

revoke all on function private.apply_forum_comment_server_fields() from public, anon, authenticated;

drop trigger if exists forum_comments_apply_server_fields on public.forum_comments;
create trigger forum_comments_apply_server_fields
    before insert or update of owner_id, creator_display_name on public.forum_comments
    for each row
    execute function private.apply_forum_comment_server_fields();
