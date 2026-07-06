revoke insert (email, phone, payment_summary) on table public.profiles from authenticated;
revoke update (email, phone, payment_summary) on table public.profiles from authenticated;

create or replace function private.lock_profile_contact_identity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if new.email is distinct from old.email then
        new.email = old.email;
    end if;

    if new.phone is distinct from old.phone then
        new.phone = old.phone;
    end if;

    if new.payment_summary is distinct from old.payment_summary then
        new.payment_summary = old.payment_summary;
    end if;

    return new;
end;
$$;

revoke all on function private.lock_profile_contact_identity() from public, anon, authenticated;

drop trigger if exists profiles_lock_contact_identity on public.profiles;
create trigger profiles_lock_contact_identity
    before update on public.profiles
    for each row
    execute function private.lock_profile_contact_identity();
