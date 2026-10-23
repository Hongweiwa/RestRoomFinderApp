begin;
create function pg_temp.report_assert(value boolean,label text) returns void language plpgsql as $$ begin
 if not coalesce(value,false) then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label;
end $$;
create function pg_temp.report_reject(command text,expected text,label text) returns void language plpgsql as $$ begin
 begin execute command; exception when others then
 if sqlstate=expected then raise notice 'PASS: %',label; return; end if; raise; end;
 raise exception 'FAIL: %',label;
end $$;
insert into auth.users(id) values ('17000000-0000-0000-0000-000000000001'),('17000000-0000-0000-0000-000000000002');
insert into public.restrooms(id,name,latitude,longitude,source,verification_status) values
 ('17100000-0000-0000-0000-000000000001','Approved contribution',40,-73,'user_submission','verified'),
 ('17100000-0000-0000-0000-000000000002','Pending contribution',40,-73,'user_submission','pending');
select to_jsonb(r)::text as original_restroom from public.restrooms r where id='17100000-0000-0000-0000-000000000001' \gset
select pg_temp.report_assert((select relrowsecurity from pg_class where oid='public.reports'::regclass),'reports RLS remains enabled');
set local role anon;
select set_config('request.jwt.claims','{}',true);
select pg_temp.report_reject('select * from public.reports','42501','guest cannot read private reports');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type) values ('17100000-0000-0000-0000-000000000001','incorrect_location')$q$,'42501','guest cannot report');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"17000000-0000-0000-0000-000000000001","is_anonymous":false}',true);
insert into public.reports(restroom_id,report_type,comment,client_request_id) values
 ('17100000-0000-0000-0000-000000000001','incorrect_location',E' \n\t ','17200000-0000-0000-0000-000000000001') returning id as report_id \gset
select pg_temp.report_assert((select status='pending' and user_id=auth.uid() and comment is null and reviewed_at is null and resolved_at is null from public.reports where id=:'report_id'),'authenticated owner default; pending only; whitespace becomes NULL; no fabricated moderation dates');
insert into public.reports(restroom_id,report_type,client_request_id) values
 ('17100000-0000-0000-0000-000000000001','incorrect_location','17200000-0000-0000-0000-000000000001') on conflict(user_id,client_request_id) do nothing;
select pg_temp.report_assert((select count(*)=1 from public.reports),'same request UUID retry returns existing report without duplicate');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type) values ('17100000-0000-0000-0000-000000000001','incorrect_location')$q$,'P1701','fresh UUID cannot bypass five-minute identical-report protection');
insert into public.reports(restroom_id,report_type,comment) values ('17100000-0000-0000-0000-000000000001','incorrect_location','Entrance is behind the building.');
select pg_temp.report_assert((select count(*)=2 from public.reports),'new explanation can be submitted');
select pg_temp.report_reject($q$insert into public.reports(restroom_id) values ('17100000-0000-0000-0000-000000000001')$q$,'23502','database requires issue type');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type) values ('17100000-0000-0000-0000-000000000001','invented')$q$,'22P02','database rejects arbitrary issue string');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type) values ('17100000-0000-0000-0000-000000000001','other')$q$,'23514','Other requires explanation on database');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type,comment) values ('17100000-0000-0000-0000-000000000001','other',' short ')$q$,'23514','Other explanation minimum length');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type,comment) values ('17100000-0000-0000-0000-000000000001','other',repeat('x',1001))$q$,'23514','server caps comment length');
insert into public.reports(restroom_id,report_type,comment) values ('17100000-0000-0000-0000-000000000001','other','  A key is required.  ');
select pg_temp.report_assert((select comment='A key is required.' from public.reports where report_type='other'),'Other accepted and trimmed');
select pg_temp.report_reject($q$insert into public.reports(user_id,restroom_id,report_type) values ('17000000-0000-0000-0000-000000000002','17100000-0000-0000-0000-000000000001','unclean_restroom')$q$,'42501','cannot submit as B');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type,status) values ('17100000-0000-0000-0000-000000000001','unclean_restroom','resolved')$q$,'42501','cannot INSERT resolved status');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type,status) values ('17100000-0000-0000-0000-000000000001','unclean_restroom','dismissed')$q$,'42501','cannot INSERT dismissed status');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type,status) values ('17100000-0000-0000-0000-000000000001','unclean_restroom','in_review')$q$,'42501','cannot INSERT in-review status');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type,reviewed_at) values ('17100000-0000-0000-0000-000000000001','unclean_restroom',now())$q$,'42501','cannot forge reviewed timestamp');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type,resolved_at) values ('17100000-0000-0000-0000-000000000001','unclean_restroom',now())$q$,'42501','cannot forge resolved timestamp');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type,created_at) values ('17100000-0000-0000-0000-000000000001','unclean_restroom',now()-interval '1 year')$q$,'42501','cannot bypass cooldown with forged created_at');
select pg_temp.report_reject($q$update public.reports set status='resolved'$q$,'42501','cannot resolve own report');
select pg_temp.report_reject($q$update public.reports set comment='Changed'$q$,'42501','ordinary reports are immutable');
select pg_temp.report_reject($q$update public.reports set user_id='17000000-0000-0000-0000-000000000002'$q$,'42501','cannot transfer ownership');
select pg_temp.report_reject($q$delete from public.reports$q$,'42501','ordinary user cannot delete reports');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type) values ('17100000-0000-0000-0000-000000000002','incorrect_location')$q$,'42501','cannot report arbitrary private pending submissions');
select public.resolve_google_restroom('day17-google-report-fixture') as google_id \gset
select public.resolve_google_restroom('day17-google-report-fixture') as same_google_id \gset
select pg_temp.report_assert(:'google_id'=:'same_google_id','Google resolver reuses anchor');
insert into public.reports(restroom_id,report_type) values (:'google_id','permanently_closed');
select pg_temp.report_assert((select count(*)=1 from public.reports where restroom_id=:'google_id' and report_type='permanently_closed'),'Google report associates with minimal internal anchor');
select pg_temp.report_assert((select name is null and address is null and latitude is null and longitude is null and verification_status='unverified' from public.restrooms where id=:'google_id'),'report resolution copies no Google display data and does not publish anchor');
select pg_temp.report_assert((select to_jsonb(r)::text=:'original_restroom' from public.restrooms r where id='17100000-0000-0000-0000-000000000001'),'report did not change canonical restroom data');
select set_config('request.jwt.claims','{"sub":"17000000-0000-0000-0000-000000000002","is_anonymous":false}',true);
select pg_temp.report_assert((select count(*)=0 from public.reports),'B cannot read A private report list or details');
select pg_temp.report_reject(format('update public.reports set status=''resolved'' where id=%L',:'report_id'),'42501','B cannot modify A');
insert into public.reports(restroom_id,report_type) values ('17100000-0000-0000-0000-000000000001','incorrect_location');
select pg_temp.report_assert((select count(*)=1 from public.reports),'B can independently report same issue');
select set_config('request.jwt.claims','{"sub":"17000000-0000-0000-0000-000000000001","is_anonymous":true}',true);
select pg_temp.report_assert((select count(*)=0 from public.reports),'anonymous Auth cannot read reports');
select pg_temp.report_reject($q$insert into public.reports(restroom_id,report_type) values ('17100000-0000-0000-0000-000000000001','unclean_restroom')$q$,'42501','anonymous Auth cannot create reports');
reset role;
update public.reports set created_at=now()-interval '6 minutes' where id=:'report_id';
update public.reports set status='resolved',reviewed_at=now(),resolved_at=now() where id=:'report_id';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"17000000-0000-0000-0000-000000000001","is_anonymous":false}',true);
select pg_temp.report_assert((select status='resolved' and reviewed_at is not null and resolved_at is not null from public.reports where id=:'report_id'),'owner reads trusted moderation status and dates');
insert into public.reports(restroom_id,report_type) values ('17100000-0000-0000-0000-000000000001','incorrect_location');
select pg_temp.report_assert((select count(*)=2 from public.reports where report_type='incorrect_location' and comment is null),'cooldown expires; legitimate later report allowed');
rollback;
