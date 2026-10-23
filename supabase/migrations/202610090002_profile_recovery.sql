-- Day 13: recover only the calling registered user's missing profile.
-- Day 12's auth.users trigger remains the normal creation path. No policy/grant widening.
begin;
create function public.ensure_current_profile() returns setof public.profiles
language plpgsql security invoker set search_path = '' as $$
begin
    if auth.uid() is null or not app_private.is_registered_user() then
        raise exception 'Registered account required' using errcode = '42501';
    end if;
    -- No user ID or editable metadata accepted. Never overwrite an existing profile.
    insert into public.profiles(id) values (auth.uid()) on conflict (id) do nothing;
    return query select p.* from public.profiles p where p.id = auth.uid();
end $$;
revoke all on function public.ensure_current_profile() from public, anon, authenticated;
grant execute on function public.ensure_current_profile() to authenticated;
comment on function public.ensure_current_profile() is
    'Idempotent missing-profile recovery under caller RLS; no arbitrary identity or existing-name overwrite.';
commit;
