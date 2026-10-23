-- Run after the migration as the database owner in a development project.
-- Fixtures and helper functions are rolled back; no real account credentials are needed.
begin;
create function pg_temp.assert_true(value boolean, label text) returns void
language plpgsql as $$ begin
    if not coalesce(value, false) then raise exception 'FAIL: %', label; end if;
    raise notice 'PASS: %', label;
end $$;
create function pg_temp.expect_error(statement text, expected_state text, label text) returns void
language plpgsql as $$ begin
    begin
        execute statement;
    exception when others then
        if sqlstate = expected_state then raise notice 'PASS: %', label; return; end if;
        raise;
    end;
    raise exception 'FAIL: % (expected SQLSTATE %)', label, expected_state;
end $$;

select pg_temp.assert_true((select count(*) = 8 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in ('profiles','restrooms','restroom_features','favorites','reviews','reports','restroom_submissions','photos') and c.relrowsecurity), 'all eight tables have RLS');
select pg_temp.assert_true((select n.nspname='gis' from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='postgis'), 'PostGIS isolated in gis');

insert into auth.users(id) values ('10000000-0000-0000-0000-000000000001'), ('10000000-0000-0000-0000-000000000002');
insert into public.profiles(id,display_name) values
('10000000-0000-0000-0000-000000000001','User A'), ('10000000-0000-0000-0000-000000000002','User B')
on conflict (id) do nothing;
insert into public.restrooms(id,name,latitude,longitude,source,verification_status,created_by) values
('20000000-0000-0000-0000-000000000001','Test public restroom',42,-71,'admin','verified','10000000-0000-0000-0000-000000000001'),
('20000000-0000-0000-0000-000000000002','Test hidden restroom',42.001,-71,'user_submission','pending',null);
insert into public.restrooms(id,google_place_id,source,verification_status) values
('20000000-0000-0000-0000-000000000003','day11-test-google-anchor','google','verified');
insert into public.restroom_features(restroom_id) values ('20000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000002');
insert into public.reviews(id,user_id,restroom_id,overall_rating,cleanliness_rating,comment) values
('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',4,5,'A review'),
('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001',3,3,'B review'),
('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002',2,2,'Hidden review');
insert into public.photos(id,user_id,restroom_id,review_id,storage_path,status) values
('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','test/approved.jpg','approved'),
('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001',null,'test/pending.jpg','pending');
insert into public.favorites(user_id,restroom_id) values ('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","is_anonymous":false}',true);
insert into public.reports(user_id,restroom_id,report_type) values ('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','unclean_restroom');
insert into public.restroom_submissions(user_id,name,latitude,longitude) values ('10000000-0000-0000-0000-000000000002','B proposal',40,-70);

select pg_temp.assert_true((select is_accessible is null and is_free is null from public.restroom_features where restroom_id='20000000-0000-0000-0000-000000000001'), 'unknown features remain NULL');
select pg_temp.assert_true((select gis.st_x(location::gis.geometry)=-71 and gis.st_y(location::gis.geometry)=42 from public.restrooms where id='20000000-0000-0000-0000-000000000001'), 'generated geography longitude/latitude order');
update public.restrooms set latitude=42.002 where id='20000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select gis.st_y(location::gis.geometry)=42.002 from public.restrooms where id='20000000-0000-0000-0000-000000000001'), 'geography follows coordinate edits');
select pg_temp.assert_true((select location is null and name is null from public.restrooms where id='20000000-0000-0000-0000-000000000003'), 'Google anchor needs no cached place fields');
select pg_temp.expect_error($q$insert into public.restrooms(google_place_id,source) values ('day11-test-google-anchor','google')$q$,'23505','unique Google Place ID');
select pg_temp.expect_error($q$insert into public.restrooms(source) values ('google')$q$,'23514','Google source needs a Place ID');
select pg_temp.expect_error($q$insert into public.restrooms(name,latitude,longitude,source) values ('Bad',91,0,'admin')$q$,'23514','invalid latitude rejected');
select pg_temp.expect_error($q$insert into public.restroom_submissions(name,latitude,longitude) values ('Bad',0,'NaN')$q$,'23514','NaN longitude rejected');
select pg_temp.expect_error($q$insert into public.restrooms(name,latitude,source) values ('Bad',0,'admin')$q$,'23514','partial coordinates rejected');
select pg_temp.expect_error($q$insert into public.restrooms(name,latitude,longitude,source) values ('Bad',0,0,'uncontrolled')$q$,'22P02','source is constrained');
select pg_temp.expect_error($q$insert into public.photos(restroom_id,review_id,storage_path) values ('20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000001','test/mismatch.jpg')$q$,'23503','photo cannot reference a different restroom review');

set local role anon;
select set_config('request.jwt.claims','{}',true);
select pg_temp.assert_true((select count(*)=2 from public.restrooms where id::text like '20000000-%'), 'guest sees only verified restrooms');
select pg_temp.assert_true((select count(*)=1 from public.restroom_features where restroom_id::text like '20000000-%'), 'guest sees features only for verified restrooms');
select pg_temp.assert_true((select count(*)=2 from public.reviews where id::text like '30000000-%'), 'guest sees reviews only for verified restrooms');
select pg_temp.assert_true((select count(*)=1 from public.photos where id::text like '40000000-%'), 'guest sees approved photos only');
select pg_temp.expect_error('select * from public.profiles','42501','guest cannot read profiles');
select pg_temp.expect_error('select * from public.favorites','42501','guest cannot read favorites');
select pg_temp.expect_error('select * from public.reports','42501','guest cannot read reports');
select pg_temp.expect_error('select * from public.restroom_submissions','42501','guest cannot read submissions');
select pg_temp.expect_error($q$insert into public.favorites(restroom_id) values ('20000000-0000-0000-0000-000000000001')$q$,'42501','guest cannot favorite');
select pg_temp.expect_error($q$insert into public.reviews(restroom_id,overall_rating) values ('20000000-0000-0000-0000-000000000001',5)$q$,'42501','guest cannot review');
select pg_temp.expect_error($q$update public.restrooms set name='hacked'$q$,'42501','guest cannot edit restroom');
select pg_temp.expect_error($q$insert into public.reports(restroom_id,report_type) values ('20000000-0000-0000-0000-000000000001','unclean_restroom')$q$,'42501','guest cannot report');
select pg_temp.expect_error($q$insert into public.restroom_submissions(name,latitude,longitude) values ('guest',0,0)$q$,'42501','guest cannot submit');
select pg_temp.expect_error($q$update public.profiles set display_name='guest'$q$,'42501','guest cannot edit profile');
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","is_anonymous":false}',true);
select pg_temp.assert_true((select count(*)=1 from public.profiles), 'A sees only own profile');
select pg_temp.assert_true((select count(*)=0 from public.favorites), 'A cannot see B favorites');
select pg_temp.assert_true((select count(*)=0 from public.reports), 'A cannot see B reports');
select pg_temp.assert_true((select count(*)=0 from public.restroom_submissions), 'A cannot see B submissions');
select pg_temp.expect_error($q$insert into public.profiles(id,display_name) values ('10000000-0000-0000-0000-000000000002','spoof')$q$,'42501','cannot insert another user profile');
update public.profiles set display_name='A edited' where id='10000000-0000-0000-0000-000000000001';
with changed as (update public.profiles set display_name='hacked' where id='10000000-0000-0000-0000-000000000002' returning id)
select pg_temp.assert_true((select count(*)=0 from changed), 'A cannot update B profile');
insert into public.favorites(restroom_id) values ('20000000-0000-0000-0000-000000000001');
select pg_temp.assert_true((select user_id=auth.uid() from public.favorites), 'favorite defaults to authenticated identity');
select pg_temp.expect_error($q$insert into public.favorites(restroom_id) values ('20000000-0000-0000-0000-000000000001')$q$,'23505','duplicate favorite rejected');
select pg_temp.expect_error($q$insert into public.favorites(user_id,restroom_id) values ('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000003')$q$,'42501','cannot spoof favorite user');
select pg_temp.expect_error($q$insert into public.favorites(restroom_id) values ('20000000-0000-0000-0000-000000000002')$q$,'42501','cannot favorite hidden restroom');
with changed as (delete from public.favorites where user_id='10000000-0000-0000-0000-000000000002' returning user_id)
select pg_temp.assert_true((select count(*)=0 from changed), 'A cannot delete B favorites');
update public.reviews set overall_rating=5 where id='30000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select overall_rating=5 from public.reviews where id='30000000-0000-0000-0000-000000000001'), 'owner can update review');
with changed as (update public.reviews set overall_rating=1 where id='30000000-0000-0000-0000-000000000002' returning id)
select pg_temp.assert_true((select count(*)=0 from changed), 'A cannot update B review');
with changed as (delete from public.reviews where id='30000000-0000-0000-0000-000000000002' returning id)
select pg_temp.assert_true((select count(*)=0 from changed), 'A cannot delete B review');
select pg_temp.expect_error($q$update public.reviews set user_id='10000000-0000-0000-0000-000000000002'$q$,'42501','cannot transfer review ownership');
select pg_temp.expect_error($q$update public.reviews set overall_rating=6 where id='30000000-0000-0000-0000-000000000001'$q$,'23514','overall rating range');
select pg_temp.expect_error($q$update public.reviews set cleanliness_rating=0 where id='30000000-0000-0000-0000-000000000001'$q$,'23514','cleanliness rating range');
select pg_temp.expect_error($q$insert into public.reviews(user_id,restroom_id,overall_rating) values ('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000003',4)$q$,'42501','cannot spoof review author');
insert into public.reviews(restroom_id,overall_rating,cleanliness_rating) values ('20000000-0000-0000-0000-000000000003',4,4);
insert into public.reports(restroom_id,report_type) values ('20000000-0000-0000-0000-000000000001','unclean_restroom');
select pg_temp.expect_error($q$insert into public.reports(user_id,restroom_id,report_type) values ('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','unclean_restroom')$q$,'42501','cannot spoof reporter');
select pg_temp.expect_error($q$insert into public.reports(restroom_id,report_type,status) values ('20000000-0000-0000-0000-000000000001','unclean_restroom','resolved')$q$,'42501','cannot self-resolve a new report');
select pg_temp.expect_error($q$update public.reports set status='resolved'$q$,'42501','cannot moderate reports');
insert into public.restroom_submissions(name,latitude,longitude) values ('A proposal',41,-70);
select pg_temp.expect_error($q$insert into public.restroom_submissions(user_id,name,latitude,longitude) values ('10000000-0000-0000-0000-000000000002','Spoof',0,0)$q$,'42501','cannot spoof submitter');
select pg_temp.expect_error($q$insert into public.restroom_submissions(name,latitude,longitude,status) values ('Self-approved',0,0,'approved')$q$,'42501','cannot self-approve submission');
select pg_temp.expect_error($q$update public.restroom_submissions set status='approved'$q$,'42501','cannot moderate submissions');
select pg_temp.expect_error($q$update public.restrooms set verification_status='verified'$q$,'42501','cannot verify official records');
select pg_temp.expect_error($q$update public.restroom_features set is_accessible=true$q$,'42501','features are server-controlled');
select pg_temp.expect_error($q$insert into public.photos(restroom_id,storage_path) values ('20000000-0000-0000-0000-000000000001','test/client.jpg')$q$,'42501','photo writes deferred');
select pg_temp.assert_true((select count(*)=1 from public.restroom_submissions), 'A sees own submission only');
select pg_temp.assert_true((select count(*)=1 from public.reports), 'A sees own report only');

-- A signed-in anonymous Auth session must not become a registered account writer.
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","is_anonymous":true}',true);
select pg_temp.expect_error($q$insert into public.favorites(restroom_id) values ('20000000-0000-0000-0000-000000000003')$q$,'42501','anonymous Auth user cannot write');
select pg_temp.assert_true((select count(*)=0 from public.profiles), 'anonymous Auth user cannot read account profile');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","is_anonymous":false}',true);
delete from public.reviews where restroom_id='20000000-0000-0000-0000-000000000003';
delete from public.favorites where restroom_id='20000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select count(*)=0 from public.favorites), 'owner can remove favorite');
reset role;

-- Account removal preserves major app data, clearing authorship instead of deleting records.
delete from auth.users where id='10000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select count(*)=0 from public.profiles where id='10000000-0000-0000-0000-000000000001'), 'auth deletion removes profile');
select pg_temp.assert_true((select created_by is null from public.restrooms where id='20000000-0000-0000-0000-000000000001'), 'restroom survives author deletion');
select pg_temp.assert_true((select user_id is null from public.reviews where id='30000000-0000-0000-0000-000000000001'), 'review survives with removed authorship');
select pg_temp.assert_true((select user_id is null from public.photos where id='40000000-0000-0000-0000-000000000001'), 'photo metadata survives author deletion');
select pg_temp.assert_true((select user_id is null from public.restroom_submissions where name='A proposal'), 'submission survives author deletion');
select pg_temp.expect_error($q$delete from public.restrooms where id='20000000-0000-0000-0000-000000000001'$q$,'23503','restroom deletion cannot silently destroy reviews/reports/photos');
delete from public.reviews where id='30000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select review_id is null and restroom_id='20000000-0000-0000-0000-000000000001' from public.photos where id='40000000-0000-0000-0000-000000000001'), 'review deletion keeps photo linked to restroom');

rollback;
