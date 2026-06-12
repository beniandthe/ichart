alter table public.profiles
    add column if not exists first_name text,
    add column if not exists last_name text;

grant insert (first_name, last_name) on table public.profiles to authenticated;
grant update (first_name, last_name) on table public.profiles to authenticated;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id, email, phone, first_name, last_name)
    values (
        new.id,
        new.email,
        coalesce(new.phone, new.raw_user_meta_data ->> 'phone'),
        nullif(new.raw_user_meta_data ->> 'first_name', ''),
        nullif(new.raw_user_meta_data ->> 'last_name', '')
    )
    on conflict (id) do update
        set email = excluded.email,
            phone = coalesce(public.profiles.phone, excluded.phone),
            first_name = coalesce(public.profiles.first_name, excluded.first_name),
            last_name = coalesce(public.profiles.last_name, excluded.last_name),
            updated_at = now();

    insert into public.subscriptions (owner_id)
    values (new.id)
    on conflict (owner_id) do nothing;

    return new;
end;
$$;
