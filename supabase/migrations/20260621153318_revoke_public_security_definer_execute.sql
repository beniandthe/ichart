revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.handle_new_auth_user() from public, anon, authenticated;

do $$
begin
    if to_regprocedure('public.rls_auto_enable()') is not null then
        revoke all on function public.rls_auto_enable() from public, anon, authenticated;
    end if;
end;
$$;
