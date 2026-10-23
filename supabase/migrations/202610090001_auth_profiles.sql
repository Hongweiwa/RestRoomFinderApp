-- Day 12: server-side profile creation, including signups awaiting email confirmation.
-- Apply after the Day 11 foundation. Does not alter Auth confirmation/provider settings or RLS.
begin;

create function app_private.create_auth_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
    safe_name text;
begin
    -- Ordinary guests have no Auth user. Do not create profiles for anonymous Auth users either.
    if coalesce(new.is_anonymous, false) then return new; end if;
    if jsonb_typeof(new.raw_user_meta_data -> 'display_name') = 'string' then
        safe_name = nullif(left(btrim(new.raw_user_meta_data ->> 'display_name', E' \t\r\n'), 80), '');
    end if;
    insert into public.profiles(id, display_name) values (new.id, safe_name)
    on conflict (id) do nothing;
    return new;
end $$;
-- Narrow trigger-only definer: no API-callable RPC, dynamic SQL, role/permission metadata or unsafe search_path.
revoke all on function app_private.create_auth_profile() from public, anon, authenticated, service_role;

create trigger on_restroom_auth_user_created
    after insert on auth.users
    for each row execute function app_private.create_auth_profile();

-- Repair pre-Day-12 accounts without replacing an existing profile or edited display name.
insert into public.profiles(id, display_name)
select id, case when jsonb_typeof(raw_user_meta_data -> 'display_name') = 'string'
    then nullif(left(btrim(raw_user_meta_data ->> 'display_name', E' \t\r\n'), 80), '')
    else null end
from auth.users where not coalesce(is_anonymous, false)
on conflict (id) do nothing;

comment on function app_private.create_auth_profile() is
    'Creates a profile transactionally with each non-anonymous Auth user. Display name only; metadata never grants privileges.';
commit;
