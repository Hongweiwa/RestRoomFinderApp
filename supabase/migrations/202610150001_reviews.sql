-- Day 15: restroom reviews, public reads, bounded paging and batched aggregates.
begin;
-- Preserve historical rows without inventing scores or truncating existing comments.
-- NOT VALID skips historical validation, but enforces both checks on every new/updated row.
alter table public.reviews add constraint reviews_cleanliness_required check (cleanliness_rating is not null) not valid;
alter table public.reviews add constraint reviews_comment_mvp_length check (char_length(comment) <= 1000) not valid;
create function app_private.normalize_review_comment() returns trigger
language plpgsql set search_path = '' as $$
begin
    new.comment = nullif(regexp_replace(new.comment, '^\s+|\s+$', '', 'g'), '');
    return new;
end $$;
revoke all on function app_private.normalize_review_comment() from public, anon, authenticated;
create trigger reviews_normalize_comment before insert or update on public.reviews
for each row execute function app_private.normalize_review_comment();

-- A Google anchor contains an ID only, not private submissions or copied Google content.
grant usage on schema app_private to anon;
grant execute on function app_private.is_google_anchor(public.restrooms) to anon;
create policy restrooms_read_public_google_anchors on public.restrooms for select to anon, authenticated
using (app_private.is_google_anchor(restrooms));
drop policy reviews_read_verified on public.reviews;
create policy reviews_read_public on public.reviews for select to anon, authenticated
using (exists (select 1 from public.restrooms r where r.id = restroom_id
    and (r.verification_status = 'verified' or app_private.is_google_anchor(r))));
drop policy reviews_insert_own on public.reviews;
create policy reviews_insert_own on public.reviews for insert to authenticated
with check ((select auth.uid()) = user_id and (select app_private.is_registered_user())
    and exists (select 1 from public.restrooms r where r.id = restroom_id
        and (r.verification_status = 'verified' or app_private.is_google_anchor(r))));
-- Existing owner-only UPDATE/DELETE, immutable-column grants, range checks and UNIQUE stay intact.
create index reviews_restroom_page_idx on public.reviews(restroom_id, created_at desc, id desc);
create index reviews_user_page_idx on public.reviews(user_id, created_at desc, id desc);

create function public.restroom_rating_summaries(restroom_ids uuid[] default '{}', place_ids text[] default '{}')
returns table(restroom_id uuid, google_place_id text, overall_rating double precision,
    cleanliness_rating double precision, review_count bigint)
language plpgsql stable security invoker set search_path = '' as $$
begin
    if coalesce(cardinality(restroom_ids),0) > 100 or coalesce(cardinality(place_ids),0) > 100 then
        raise exception 'Too many restrooms' using errcode = '22023';
    end if;
    return query
    select r.id, r.google_place_id, avg(v.overall_rating)::double precision,
           avg(v.cleanliness_rating)::double precision, count(v.id)
    from public.restrooms r left join public.reviews v on v.restroom_id = r.id
    where (r.id = any(restroom_ids) or r.google_place_id = any(place_ids))
      and (r.verification_status = 'verified' or app_private.is_google_anchor(r))
    group by r.id;
end $$;

create function public.restroom_reviews_page(target_restroom uuid, before_created timestamptz default null,
    before_id uuid default null, page_size integer default 20)
returns setof public.reviews language sql stable security invoker set search_path = '' as $$
    select v.* from public.reviews v join public.restrooms r on r.id = v.restroom_id
    where v.restroom_id = target_restroom
      and (r.verification_status = 'verified' or app_private.is_google_anchor(r))
      and (before_created is null or (v.created_at,v.id) < (before_created,before_id))
    order by v.created_at desc, v.id desc limit greatest(1,least(coalesce(page_size,20),21));
$$;

-- No caller-supplied user ID. Even though published reviews are public, this management
-- endpoint only returns the current registered account's rows, including hidden parents.
create function public.my_restroom_reviews(target_restroom uuid default null,
    before_created timestamptz default null, before_id uuid default null, page_size integer default 20)
returns table(review jsonb, restroom jsonb)
language sql stable security invoker set search_path = '' as $$
    select to_jsonb(v), case when r.id is null then null else jsonb_build_object(
        'id',r.id,'google_place_id',r.google_place_id,'name',r.name,'address',r.address,
        'latitude',r.latitude,'longitude',r.longitude) end
    from public.reviews v left join public.restrooms r on r.id=v.restroom_id
    where v.user_id=(select auth.uid()) and (select app_private.is_registered_user())
      and (target_restroom is null or v.restroom_id=target_restroom)
      and (before_created is null or (v.created_at,v.id) < (before_created,before_id))
    order by v.created_at desc,v.id desc limit greatest(1,least(coalesce(page_size,20),21));
$$;
revoke all on function public.restroom_rating_summaries(uuid[],text[]),
    public.restroom_reviews_page(uuid,timestamptz,uuid,integer),
    public.my_restroom_reviews(uuid,timestamptz,uuid,integer) from public,anon,authenticated;
grant execute on function public.restroom_rating_summaries(uuid[],text[]),
    public.restroom_reviews_page(uuid,timestamptz,uuid,integer) to anon,authenticated;
grant execute on function public.my_restroom_reviews(uuid,timestamptz,uuid,integer) to authenticated;
notify pgrst, 'reload schema';
commit;
