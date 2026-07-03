do $$
begin
    if exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'profiles'
          and column_name = 'mailing_address'
    ) then
        revoke insert (id, email, phone, mailing_address, payment_summary) on table public.profiles from authenticated;
        revoke update (id, email, phone, mailing_address, payment_summary) on table public.profiles from authenticated;
    end if;
end $$;

alter table public.profiles drop column if exists mailing_address;

grant insert (id, email, phone, payment_summary) on table public.profiles to authenticated;
grant update (id, email, phone, payment_summary) on table public.profiles to authenticated;
