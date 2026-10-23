-- RestRoom Finder foundation. Apply once to a new Supabase project as its database owner.
-- Additive migration: no drops, backfills, Google imports, auth triggers or storage buckets.
-- Fail atomically on conflicting existing objects rather than silently changing their security.
begin;

create schema if not exists gis;
-- Do not move an existing PostGIS installation automatically.
do $$
begin
    if exists (
        select 1 from pg_extension e join pg_namespace n on n.oid = e.extnamespace
        where e.extname = 'postgis' and n.nspname <> 'gis'
    ) then
        raise exception 'PostGIS already exists outside gis. Review its dependencies before adapting this migration.';
    end if;
end $$;
create extension if not exists postgis with schema gis;
-- Keep gis out of the Data API exposed schemas. Clients need type/function usage, not reference tables.
revoke all on schema gis from public, anon, authenticated;
grant usage on schema gis to anon, authenticated, service_role;
revoke all on all tables in schema gis from public, anon, authenticated;

create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;
grant usage on schema app_private to authenticated;

create type public.restroom_source as enum ('google', 'user_submission', 'admin');
create type public.verification_status as enum ('unverified', 'pending', 'verified', 'rejected');
create type public.report_type as enum (
    'closed', 'incorrect_location', 'not_public', 'dirty', 'wrong_hours',
    'incorrect_accessibility', 'duplicate', 'other'
);
create type public.report_status as enum ('pending', 'reviewed', 'resolved', 'dismissed');
create type public.submission_status as enum ('pending', 'approved', 'rejected');

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text check (char_length(display_name) between 1 and 80 and btrim(display_name) <> ''),
    avatar_url text check (char_length(avatar_url) <= 2048 and avatar_url like 'https://%'),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.restrooms (
    id uuid primary key default gen_random_uuid(),
    google_place_id text unique check (char_length(google_place_id) between 1 and 512 and btrim(google_place_id) <> ''),
    -- Google-linked rows may be ID-only anchors. These fields are app-owned contributions,
    -- not a persistent cache of Google name/address/coordinates/ratings.
    name text check (char_length(name) between 1 and 200 and btrim(name) <> ''),
    address text check (char_length(address) <= 1000),
    latitude double precision check (latitude between -90 and 90),
    longitude double precision check (longitude between -180 and 180),
    source public.restroom_source not null,
    verification_status public.verification_status not null default 'unverified',
    created_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    location gis.geography(Point, 4326) generated always as (
        case when latitude is not null and longitude is not null
             then gis.st_setsrid(gis.st_makepoint(longitude, latitude), 4326)::gis.geography
             else null end
    ) stored,
    constraint coordinate_pair check ((latitude is null) = (longitude is null)),
    constraint google_identity check (source <> 'google' or google_place_id is not null),
    constraint contributed_location check (source = 'google' or (name is not null and latitude is not null and longitude is not null))
);

create table public.restroom_features (
    restroom_id uuid primary key references public.restrooms(id) on delete cascade,
    is_accessible boolean,
    has_baby_changing boolean,
    is_gender_neutral boolean,
    is_free boolean,
    is_family_restroom boolean,
    is_24_hours boolean,
    updated_at timestamptz not null default now()
);

create table public.favorites (
    user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
    restroom_id uuid not null references public.restrooms(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, restroom_id)
);

create table public.reviews (
    id uuid primary key default gen_random_uuid(),
    -- Retain community content if an account is deleted; remove its profile association.
    user_id uuid default auth.uid() references public.profiles(id) on delete set null,
    restroom_id uuid not null references public.restrooms(id) on delete restrict,
    overall_rating smallint not null check (overall_rating between 1 and 5),
    cleanliness_rating smallint check (cleanliness_rating between 1 and 5),
    comment text check (char_length(comment) <= 5000),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, restroom_id),
    unique (id, restroom_id)
);

create table public.reports (
    id uuid primary key default gen_random_uuid(),
    user_id uuid default auth.uid() references public.profiles(id) on delete set null,
    restroom_id uuid not null references public.restrooms(id) on delete restrict,
    report_type public.report_type not null,
    comment text check (char_length(comment) <= 5000),
    status public.report_status not null default 'pending',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.restroom_submissions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid default auth.uid() references public.profiles(id) on delete set null,
    name text not null check (char_length(name) between 1 and 200 and btrim(name) <> ''),
    address text check (char_length(address) <= 1000),
    latitude double precision not null check (latitude between -90 and 90),
    longitude double precision not null check (longitude between -180 and 180),
    notes text check (char_length(notes) <= 5000),
    status public.submission_status not null default 'pending',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.photos (
    id uuid primary key default gen_random_uuid(),
    user_id uuid default auth.uid() references public.profiles(id) on delete set null,
    restroom_id uuid not null references public.restrooms(id) on delete restrict,
    review_id uuid,
    storage_path text not null unique check (
        char_length(storage_path) between 1 and 1024 and btrim(storage_path) <> ''
        and storage_path !~ '(^/|://|(^|/)\.\.(/|$))'
    ),
    status public.submission_status not null default 'pending',
    created_at timestamptz not null default now(),
    -- A review photo must belong to the same restroom. Keep photo metadata on review deletion.
    foreign key (review_id, restroom_id) references public.reviews(id, restroom_id) on delete set null (review_id)
);

-- Unique/primary keys already index google_place_id, favorites.user_id,
-- reviews.user_id and restroom_features.restroom_id. Avoid duplicate indexes.
create index restrooms_location_idx on public.restrooms using gist (location);
create index restrooms_created_by_idx on public.restrooms(created_by);
create index favorites_restroom_idx on public.favorites(restroom_id);
create index reviews_restroom_idx on public.reviews(restroom_id);
create index reports_restroom_idx on public.reports(restroom_id);
create index reports_user_idx on public.reports(user_id);
create index submissions_user_idx on public.restroom_submissions(user_id);
create index photos_restroom_idx on public.photos(restroom_id);
create index photos_user_idx on public.photos(user_id);
create index photos_review_idx on public.photos(review_id, restroom_id);

create function app_private.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
    new.updated_at = now();
    return new;
end $$;
revoke all on function app_private.set_updated_at() from public, anon, authenticated;

create trigger profiles_updated before update on public.profiles
for each row execute function app_private.set_updated_at();
create trigger restrooms_updated before update on public.restrooms
for each row execute function app_private.set_updated_at();
create trigger features_updated before update on public.restroom_features
for each row execute function app_private.set_updated_at();
create trigger reviews_updated before update on public.reviews
for each row execute function app_private.set_updated_at();
create trigger reports_updated before update on public.reports
for each row execute function app_private.set_updated_at();
create trigger submissions_updated before update on public.restroom_submissions
for each row execute function app_private.set_updated_at();

-- Supabase anonymous Auth sessions also use the authenticated database role.
-- They remain read-only guests, even if anonymous Auth is enabled later.
create function app_private.is_registered_user() returns boolean
language sql stable security invoker set search_path = '' as $$
    select auth.uid() is not null
       and not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
$$;
revoke all on function app_private.is_registered_user() from public, anon, authenticated;
grant execute on function app_private.is_registered_user() to authenticated;

alter table public.profiles enable row level security;
alter table public.restrooms enable row level security;
alter table public.restroom_features enable row level security;
alter table public.favorites enable row level security;
alter table public.reviews enable row level security;
alter table public.reports enable row level security;
alter table public.restroom_submissions enable row level security;
alter table public.photos enable row level security;

-- Reset project-default table grants on ONLY these new application tables.
revoke all on public.profiles, public.restrooms, public.restroom_features, public.favorites,
    public.reviews, public.reports, public.restroom_submissions, public.photos from public, anon, authenticated;
grant usage on schema public to anon, authenticated, service_role;
grant select on public.restrooms, public.restroom_features, public.reviews, public.photos to anon, authenticated;
grant select on public.profiles, public.favorites, public.reports, public.restroom_submissions to authenticated;
-- Column grants also prevent changing IDs, timestamps, ownership and moderation status.
grant insert (id, display_name, avatar_url), update (display_name, avatar_url) on public.profiles to authenticated;
grant insert (user_id, restroom_id), delete on public.favorites to authenticated;
grant insert (user_id, restroom_id, overall_rating, cleanliness_rating, comment),
    update (overall_rating, cleanliness_rating, comment), delete on public.reviews to authenticated;
grant insert (user_id, restroom_id, report_type, comment) on public.reports to authenticated;
grant insert (user_id, name, address, latitude, longitude, notes) on public.restroom_submissions to authenticated;
-- No client write grants/policies on restrooms, features or photos. Future moderation/storage work is server-side.
grant all on public.profiles, public.restrooms, public.restroom_features, public.favorites,
    public.reviews, public.reports, public.restroom_submissions, public.photos to service_role;

create policy profiles_read_own on public.profiles for select to authenticated
using ((select auth.uid()) = id and (select app_private.is_registered_user()));
create policy profiles_insert_own on public.profiles for insert to authenticated
with check ((select auth.uid()) = id and (select app_private.is_registered_user()));
create policy profiles_update_own on public.profiles for update to authenticated
using ((select auth.uid()) = id and (select app_private.is_registered_user()))
with check ((select auth.uid()) = id and (select app_private.is_registered_user()));

create policy restrooms_read_verified on public.restrooms for select to anon, authenticated
using (verification_status = 'verified');
create policy features_read_verified on public.restroom_features for select to anon, authenticated
using (exists (select 1 from public.restrooms r where r.id = restroom_id and r.verification_status = 'verified'));

create policy favorites_read_own on public.favorites for select to authenticated
using ((select auth.uid()) = user_id and (select app_private.is_registered_user()));
create policy favorites_insert_own on public.favorites for insert to authenticated
with check ((select auth.uid()) = user_id and (select app_private.is_registered_user())
    and exists (select 1 from public.restrooms r where r.id = restroom_id and r.verification_status = 'verified'));
create policy favorites_delete_own on public.favorites for delete to authenticated
using ((select auth.uid()) = user_id and (select app_private.is_registered_user()));

create policy reviews_read_verified on public.reviews for select to anon, authenticated
using (exists (select 1 from public.restrooms r where r.id = restroom_id and r.verification_status = 'verified'));
create policy reviews_read_own on public.reviews for select to authenticated
using ((select auth.uid()) = user_id and (select app_private.is_registered_user()));
create policy reviews_insert_own on public.reviews for insert to authenticated
with check ((select auth.uid()) = user_id and (select app_private.is_registered_user())
    and exists (select 1 from public.restrooms r where r.id = restroom_id and r.verification_status = 'verified'));
create policy reviews_update_own on public.reviews for update to authenticated
using ((select auth.uid()) = user_id and (select app_private.is_registered_user()))
with check ((select auth.uid()) = user_id and (select app_private.is_registered_user()));
create policy reviews_delete_own on public.reviews for delete to authenticated
using ((select auth.uid()) = user_id and (select app_private.is_registered_user()));

create policy reports_read_own on public.reports for select to authenticated
using ((select auth.uid()) = user_id and (select app_private.is_registered_user()));
create policy reports_insert_own on public.reports for insert to authenticated
with check ((select auth.uid()) = user_id and (select app_private.is_registered_user()) and status = 'pending'
    and exists (select 1 from public.restrooms r where r.id = restroom_id and r.verification_status = 'verified'));

create policy submissions_read_own on public.restroom_submissions for select to authenticated
using ((select auth.uid()) = user_id and (select app_private.is_registered_user()));
create policy submissions_insert_own on public.restroom_submissions for insert to authenticated
with check ((select auth.uid()) = user_id and (select app_private.is_registered_user()) and status = 'pending');

create policy photos_read_approved on public.photos for select to anon, authenticated
using (status = 'approved'
    and exists (select 1 from public.restrooms r where r.id = restroom_id and r.verification_status = 'verified'));
create policy photos_read_own on public.photos for select to authenticated
using ((select auth.uid()) = user_id and (select app_private.is_registered_user()));

comment on column public.restrooms.google_place_id is 'Stable Google identity for joining app-owned contributions; do not match by name or copy every search result.';
comment on column public.restroom_features.is_accessible is 'NULL means unknown, not false. All feature booleans preserve this distinction.';
comment on column public.restrooms.location is 'Generated WGS84 geography, longitude first. GiST supports future ST_DWithin in meters; Google discovery is unchanged.';
comment on table public.photos is 'Metadata only. No Storage bucket, upload policy or client writes until the photo feature is designed.';

commit;
