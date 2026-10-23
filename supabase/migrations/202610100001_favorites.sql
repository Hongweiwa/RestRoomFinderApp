-- Day 14: allow authenticated favorites of minimal Google identity anchors.
-- Existing favorites ownership policies and all table write grants stay restricted.
begin;
create function app_private.is_google_anchor(r public.restrooms) returns boolean
language sql immutable security invoker set search_path = '' as $$
    select r.source = 'google' and r.verification_status = 'unverified'
       and r.name is null and r.address is null and r.latitude is null and r.longitude is null
       and r.created_by is null;
$$;
revoke all on function app_private.is_google_anchor(public.restrooms) from public, anon;
grant execute on function app_private.is_google_anchor(public.restrooms) to authenticated;
-- These rows contain a Place ID and bookkeeping only, never private contributions or Google content.
create policy restrooms_read_google_anchors on public.restrooms for select to authenticated
using ((select app_private.is_registered_user()) and app_private.is_google_anchor(restrooms));
drop policy favorites_insert_own on public.favorites;
create policy favorites_insert_own on public.favorites for insert to authenticated
with check ((select auth.uid()) = user_id and (select app_private.is_registered_user())
    and exists (select 1 from public.restrooms r where r.id = restroom_id
        and (r.verification_status = 'verified' or app_private.is_google_anchor(r))));

-- Only anchor creation needs server privilege; favorites are still inserted/deleted under caller RLS.
create function public.resolve_google_restroom(place_id text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare resolved_id uuid;
begin
    if auth.uid() is null or not app_private.is_registered_user() then
        raise exception 'Registered account required' using errcode = '42501';
    end if;
    if place_id is null or char_length(place_id) not between 1 and 512 or btrim(place_id) = '' then
        raise exception 'Invalid place reference' using errcode = '22023';
    end if;
    insert into public.restrooms(google_place_id, source) values (place_id, 'google')
        on conflict (google_place_id) do nothing;
    select r.id into resolved_id from public.restrooms r where r.google_place_id = place_id
        and (r.verification_status = 'verified' or app_private.is_google_anchor(r));
    if resolved_id is null then raise exception 'Place unavailable' using errcode = '42501'; end if;
    return resolved_id;
end $$;
revoke all on function public.resolve_google_restroom(text) from public, anon, authenticated;
grant execute on function public.resolve_google_restroom(text) to authenticated;
-- favorites(user_id, restroom_id) primary key and favorites_restroom_idx already exist.
commit;
