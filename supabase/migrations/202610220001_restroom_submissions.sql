-- Day 16: private pending submissions. No automatic publication or moderation endpoint.
begin;
alter table public.restroom_submissions
    add column is_accessible boolean,
    add column has_baby_changing boolean,
    add column is_gender_neutral boolean,
    add column is_free boolean,
    add column is_family_restroom boolean,
    add column is_24_hours boolean,
    add column client_request_id uuid not null default gen_random_uuid(),
    add column approved_restroom_id uuid references public.restrooms(id) on delete set null,
    add column reviewed_by uuid references public.profiles(id) on delete set null,
    add column reviewed_at timestamptz,
    add column moderation_notes text check (char_length(moderation_notes) <= 2000),
    add column rejection_reason text check (char_length(rejection_reason) <= 1000),
    add constraint submissions_request_unique unique(user_id,client_request_id),
    add constraint submissions_approval_link check (approved_restroom_id is null or status = 'approved'),
    add constraint submissions_notes_mvp_length check (char_length(notes) <= 1000) not valid;
-- Historical notes are retained; new/updated rows must meet the shorter limit.
create function app_private.normalize_submission_text() returns trigger
language plpgsql set search_path = '' as $$
begin
    new.name = regexp_replace(new.name, '^\s+|\s+$', '', 'g');
    new.address = nullif(regexp_replace(new.address, '^\s+|\s+$', '', 'g'), '');
    new.notes = nullif(regexp_replace(new.notes, '^\s+|\s+$', '', 'g'), '');
    return new;
end $$;
revoke all on function app_private.normalize_submission_text() from public,anon,authenticated;
create trigger submissions_normalize before insert or update on public.restroom_submissions
for each row execute function app_private.normalize_submission_text();

-- Keep internal reviewer identity/notes private even from the submission's owner.
revoke select on public.restroom_submissions from authenticated;
grant select(id,user_id,name,address,latitude,longitude,is_accessible,has_baby_changing,
    is_gender_neutral,is_free,is_family_restroom,is_24_hours,notes,status,created_at,updated_at,
    client_request_id,approved_restroom_id,rejection_reason) on public.restroom_submissions to authenticated;
grant insert(is_accessible,has_baby_changing,is_gender_neutral,is_free,is_family_restroom,is_24_hours,
    client_request_id) on public.restroom_submissions to authenticated;
grant update(name,address,latitude,longitude,is_accessible,has_baby_changing,is_gender_neutral,
    is_free,is_family_restroom,is_24_hours,notes) on public.restroom_submissions to authenticated;
create policy submissions_update_own_pending on public.restroom_submissions for update to authenticated
using ((select auth.uid()) = user_id and (select app_private.is_registered_user()) and status = 'pending')
with check ((select auth.uid()) = user_id and (select app_private.is_registered_user()) and status = 'pending');
-- Existing SELECT/INSERT policies enforce owner/registered identity and pending INSERT status.
-- No client grant for status, owner updates, approval link, timestamps, moderation or DELETE.
create index submissions_user_page_idx on public.restroom_submissions(user_id,created_at desc,id desc);
create index submissions_pending_coordinate_idx on public.restroom_submissions(user_id,latitude,longitude) where status='pending';

-- Geography distance calculations read this static PostGIS projection catalog.
-- No write access or broader gis schema-table grant is needed.
grant select on gis.spatial_ref_sys to authenticated;

-- Invoker-only, bounded warning candidates. Other users' private submissions are never exposed.
create function public.submission_duplicate_candidates(chosen_latitude double precision, chosen_longitude double precision,
    request_id uuid, editing_id uuid default null)
returns table(id uuid,kind text,name text,address text,latitude double precision,longitude double precision,
    google_place_id text,distance_meters double precision)
language plpgsql stable security invoker set search_path = '' as $$
begin
    if auth.uid() is null or not app_private.is_registered_user() then
        raise exception 'Registered account required' using errcode='42501';
    end if;
    if chosen_latitude is null or chosen_longitude is null or not(chosen_latitude between -90 and 90)
        or not(chosen_longitude between -180 and 180) then
        raise exception 'Invalid location' using errcode='22023';
    end if;
    return query
    select candidates.* from (
        select r.id,'restroom'::text,r.name,r.address,r.latitude,r.longitude,r.google_place_id,
            gis.st_distance(r.location,gis.st_setsrid(gis.st_makepoint(chosen_longitude,chosen_latitude),4326)::gis.geography) as distance_meters
        from public.restrooms r
        where r.verification_status='verified' and r.location is not null
          and gis.st_dwithin(r.location,gis.st_setsrid(gis.st_makepoint(chosen_longitude,chosen_latitude),4326)::gis.geography,50)
        union all
        select s.id,'submission'::text,s.name,s.address,s.latitude,s.longitude,null::text,
            gis.st_distance(gis.st_setsrid(gis.st_makepoint(s.longitude,s.latitude),4326)::gis.geography,
                gis.st_setsrid(gis.st_makepoint(chosen_longitude,chosen_latitude),4326)::gis.geography)
        from public.restroom_submissions s
        where s.user_id=(select auth.uid()) and s.status='pending'
          and s.client_request_id is distinct from request_id and s.id is distinct from editing_id
          and s.latitude between chosen_latitude-0.001 and chosen_latitude+0.001
          and gis.st_dwithin(gis.st_setsrid(gis.st_makepoint(s.longitude,s.latitude),4326)::gis.geography,
                gis.st_setsrid(gis.st_makepoint(chosen_longitude,chosen_latitude),4326)::gis.geography,25)
    ) candidates order by candidates.distance_meters,candidates.id limit 10;
end $$;
revoke all on function public.submission_duplicate_candidates(double precision,double precision,uuid,uuid) from public,anon,authenticated;
grant execute on function public.submission_duplicate_candidates(double precision,double precision,uuid,uuid) to authenticated;
comment on column public.restroom_submissions.approved_restroom_id is
    'Set only by future privileged moderation after canonical restroom/features creation; pending submissions are never public.';
notify pgrst,'reload schema';
commit;
