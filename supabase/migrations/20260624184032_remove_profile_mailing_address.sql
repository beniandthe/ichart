do $$
begin
    if exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'profiles'
          and column_name = 'mailing_address'
    ) then
        revoke insert (mailing_address) on table public.profiles from authenticated;
        revoke update (mailing_address) on table public.profiles from authenticated;
    end if;
end $$;

alter table public.profiles
    drop column if exists mailing_address;
