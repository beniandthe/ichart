revoke insert (mailing_address) on table public.profiles from authenticated;
revoke update (mailing_address) on table public.profiles from authenticated;

alter table public.profiles
    drop column if exists mailing_address;
