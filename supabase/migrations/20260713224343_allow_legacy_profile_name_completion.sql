grant update (first_name, last_name) on table public.profiles to authenticated;

create or replace function private.lock_profile_account_names()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
    old_first_name text := nullif(btrim(coalesce(old.first_name, '')), '');
    old_last_name text := nullif(btrim(coalesce(old.last_name, '')), '');
    requested_first_name text := nullif(btrim(coalesce(new.first_name, '')), '');
    requested_last_name text := nullif(btrim(coalesce(new.last_name, '')), '');
begin
    if old_first_name is null then
        new.first_name = requested_first_name;
    elsif requested_first_name is distinct from old_first_name then
        new.first_name = old_first_name;
    else
        new.first_name = old.first_name;
    end if;

    if old_last_name is null then
        new.last_name = requested_last_name;
    elsif requested_last_name is distinct from old_last_name then
        new.last_name = old_last_name;
    else
        new.last_name = old.last_name;
    end if;

    return new;
end;
$$;
