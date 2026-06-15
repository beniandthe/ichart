revoke update (first_name, last_name) on table public.profiles from authenticated;

create or replace function private.lock_profile_account_names()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
    if new.first_name is distinct from old.first_name then
        new.first_name = old.first_name;
    end if;

    if new.last_name is distinct from old.last_name then
        new.last_name = old.last_name;
    end if;

    return new;
end;
$$;

drop trigger if exists profiles_lock_account_names on public.profiles;
create trigger profiles_lock_account_names
    before update on public.profiles
    for each row
    execute function private.lock_profile_account_names();
