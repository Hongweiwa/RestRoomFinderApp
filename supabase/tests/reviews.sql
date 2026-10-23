begin;
create function pg_temp.review_assert(value boolean,label text) returns void language plpgsql as $$ begin
 if not coalesce(value,false) then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label;
end $$;
create function pg_temp.review_reject(command text,expected text,label text) returns void language plpgsql as $$
begin
 begin execute command; exception when others then
  if sqlstate=expected then raise notice 'PASS: %',label; return; end if; raise;
 end;
 raise exception 'FAIL: %',label;
end $$;
insert into auth.users(id) values ('15000000-0000-0000-0000-000000000001'),('15000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"15000000-0000-0000-0000-000000000001","is_anonymous":false}',true);
select public.resolve_google_restroom('day15-real-test') as anchor \gset
select pg_temp.review_assert((select review_count=0 and overall_rating is null and cleanliness_rating is null from public.restroom_rating_summaries('{}',array['day15-real-test'])), 'unrated is unknown, never zero');
insert into public.reviews(restroom_id,overall_rating,cleanliness_rating,comment) values (:'anchor',4,5,E'  Very clean.\n') returning id as a_review \gset
select pg_temp.review_assert((select comment='Very clean.' from public.reviews where id=:'a_review'), 'server trims comments');
select pg_temp.review_reject(format('insert into public.reviews(restroom_id,overall_rating,cleanliness_rating) values (%L,4,5)',:'anchor'),'23505','one review per user per restroom');
select pg_temp.review_reject(format('update public.reviews set cleanliness_rating=null where id=%L',:'a_review'),'23514','cleanliness required in database');
select pg_temp.review_reject(format('update public.reviews set overall_rating=0 where id=%L',:'a_review'),'23514','database rejects rating below 1');
select pg_temp.review_reject(format('update public.reviews set cleanliness_rating=6 where id=%L',:'a_review'),'23514','database rejects rating above 5');
select pg_temp.review_reject(format('update public.reviews set comment=%L where id=%L',repeat('x',1001),:'a_review'),'23514','database caps comments at 1000');
select pg_temp.review_assert((select count(*)=1 from public.my_restroom_reviews()),'My Reviews returns own row');
select set_config('request.jwt.claims','{"sub":"15000000-0000-0000-0000-000000000002","is_anonymous":false}',true);
select pg_temp.review_assert((select count(*)=0 from public.my_restroom_reviews()),'B management list excludes A');
with changed as (update public.reviews set overall_rating=1 where id=:'a_review' returning id)
select pg_temp.review_assert((select count(*)=0 from changed),'B cannot edit A');
with changed as (delete from public.reviews where id=:'a_review' returning id)
select pg_temp.review_assert((select count(*)=0 from changed),'B cannot delete A');
select pg_temp.review_reject(format('insert into public.reviews(user_id,restroom_id,overall_rating,cleanliness_rating) values (%L,%L,1,1)','15000000-0000-0000-0000-000000000001',:'anchor'),'42501','B cannot submit as A');
insert into public.reviews(restroom_id,overall_rating,cleanliness_rating,comment) values (:'anchor',2,3,E' \n\t ') returning id as b_review \gset
select pg_temp.review_assert((select comment is null from public.reviews where id=:'b_review'),'whitespace-only comment becomes null');
select pg_temp.review_assert((select overall_rating=3 and cleanliness_rating=4 and review_count=2 from public.restroom_rating_summaries('{}',array['day15-real-test'])),'database aggregate averages and count are correct');
update public.reviews set cleanliness_rating=5 where id=:'b_review';
select pg_temp.review_assert((select cleanliness_rating=5 and review_count=2 from public.restroom_rating_summaries('{}',array['day15-real-test'])),'edit updates aggregate without duplicate');
set local role anon;
select set_config('request.jwt.claims','{}',true);
select pg_temp.review_assert((select count(*)=2 from public.restroom_reviews_page(:'anchor')),'guest reads Google-origin restroom reviews');
select pg_temp.review_assert((select overall_rating=3 and cleanliness_rating=5 from public.restroom_rating_summaries('{}',array['day15-real-test'])),'guest reads same averages');
select pg_temp.review_reject('select * from public.my_restroom_reviews()','42501','guest cannot read management endpoint');
select pg_temp.review_reject(format('insert into public.reviews(restroom_id,overall_rating,cleanliness_rating) values (%L,4,5)',:'anchor'),'42501','guest cannot submit');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"15000000-0000-0000-0000-000000000002","is_anonymous":true}',true);
select pg_temp.review_assert((select count(*)=0 from public.my_restroom_reviews()),'anonymous Auth account has no management access');
select pg_temp.review_reject(format('insert into public.reviews(restroom_id,overall_rating,cleanliness_rating) values (%L,4,5)',:'anchor'),'42501','anonymous Auth cannot review');
select set_config('request.jwt.claims','{"sub":"15000000-0000-0000-0000-000000000002","is_anonymous":false}',true);
delete from public.reviews where id=:'b_review';
select pg_temp.review_assert((select review_count=1 and overall_rating=4 and cleanliness_rating=5 from public.restroom_rating_summaries('{}',array['day15-real-test'])),'delete updates aggregates');
select pg_temp.review_assert(exists(select 1 from public.restrooms where id=:'anchor'),'review deletion preserves restroom');
select pg_temp.review_assert(public.resolve_google_restroom('day15-real-test')=:'anchor'::uuid,'favorites and reviews reuse unique Google resolver');
reset role;
-- Page with matching timestamps: UUID is the deterministic tie breaker.
insert into auth.users(id) select ('15100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,25)n;
insert into public.reviews(user_id,restroom_id,overall_rating,cleanliness_rating,created_at)
select ('15100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,:'anchor',4,5,'2026-10-15T12:00:00.123456Z' from generate_series(1,25)n;
set local role anon;
select set_config('request.jwt.claims','{}',true);
select pg_temp.review_assert((select count(*)=21 from public.restroom_reviews_page(:'anchor',null,null,9999)),'page bounded to 21 including lookahead');
select id as cursor_id,created_at as cursor_created from public.restroom_reviews_page(:'anchor',null,null,20) offset 19 limit 1 \gset
select pg_temp.review_assert((select count(*)=6 from public.restroom_reviews_page(:'anchor',:'cursor_created',:'cursor_id',21)),'keyset next page has remainder with no skipped tie rows');
select pg_temp.review_reject('select * from public.restroom_rating_summaries(array_fill(gen_random_uuid(),array[101]),''{}'')','22023','summary batch bounded');
rollback;
