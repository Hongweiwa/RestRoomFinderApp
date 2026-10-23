begin;
create function pg_temp.submission_assert(value boolean,label text) returns void language plpgsql as $$ begin
 if not coalesce(value,false) then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label;
end $$;
create function pg_temp.submission_reject(command text,expected text,label text) returns void language plpgsql as $$
begin
 begin execute command; exception when others then
  if sqlstate=expected then raise notice 'PASS: %',label; return; end if; raise;
 end;
 raise exception 'FAIL: %',label;
end $$;
insert into auth.users(id) values ('16000000-0000-0000-0000-000000000001'),('16000000-0000-0000-0000-000000000002');
insert into public.restrooms(id,name,latitude,longitude,source,verification_status) values
 ('16100000-0000-0000-0000-000000000001','Verified nearby',40,-73,'admin','verified'),
 ('16100000-0000-0000-0000-000000000002','Private nearby',40,-73,'user_submission','pending'),
 ('16100000-0000-0000-0000-000000000003','Far away',41,-73,'admin','verified');
select count(*) as original_restrooms from public.restrooms \gset
set local role anon;
select set_config('request.jwt.claims','{}',true);
select pg_temp.submission_reject('select * from public.restroom_submissions','42501','guest cannot read private submissions');
select pg_temp.submission_reject($q$insert into public.restroom_submissions(name,latitude,longitude) values ('Guest',40,-73)$q$,'42501','guest cannot submit');
select pg_temp.submission_reject($q$select * from public.submission_duplicate_candidates(40,-73,gen_random_uuid())$q$,'42501','guest cannot query private duplicate checks');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"16000000-0000-0000-0000-000000000001","is_anonymous":false}',true);
insert into public.restroom_submissions(user_id,client_request_id,name,address,latitude,longitude,notes,
 is_accessible,has_baby_changing,is_gender_neutral,is_free,is_family_restroom,is_24_hours)
values ('16000000-0000-0000-0000-000000000001','16200000-0000-0000-0000-000000000001',E'  Park Restroom\n',' ',40,-73,E' \n\t ',null,null,null,null,null,null)
returning id as submission_id \gset
select pg_temp.submission_assert((select status='pending' and approved_restroom_id is null and name='Park Restroom' and notes is null and address is null
 and is_accessible is null and has_baby_changing is null and is_gender_neutral is null and is_free is null and is_family_restroom is null and is_24_hours is null
 from public.restroom_submissions where id=:'submission_id'),'insert stays pending; name trims; optional text/features preserve NULL');
-- Mirror the SDK idempotent INSERT instead of granting UPDATE to ownership/request columns.
insert into public.restroom_submissions(user_id,client_request_id,name,latitude,longitude)
values ('16000000-0000-0000-0000-000000000001','16200000-0000-0000-0000-000000000001','Park Restroom',40,-73)
on conflict(user_id,client_request_id) do nothing;
select pg_temp.submission_assert((select count(*)=1 from public.restroom_submissions),'retry creates one row per request');
select pg_temp.submission_reject($q$insert into public.restroom_submissions(name,latitude,longitude) values (' ',40,-73)$q$,'23514','database rejects whitespace name');
select pg_temp.submission_reject($q$insert into public.restroom_submissions(name,latitude,longitude) values ('Invalid',91,-73)$q$,'23514','database rejects invalid latitude');
select pg_temp.submission_reject($q$insert into public.restroom_submissions(name,latitude,longitude) values ('Invalid',40,'NaN')$q$,'23514','database rejects NaN longitude');
select pg_temp.submission_reject($q$insert into public.restroom_submissions(name,latitude,longitude) values ('Missing',null,-73)$q$,'23502','database requires coordinates');
select pg_temp.submission_reject($q$insert into public.restroom_submissions(name,latitude,longitude,notes) values ('Long',40,-73,repeat('x',1001))$q$,'23514','database caps notes');
select pg_temp.submission_reject($q$insert into public.restroom_submissions(user_id,name,latitude,longitude) values ('16000000-0000-0000-0000-000000000002','Spoof',40,-73)$q$,'42501','cannot submit as B');
select pg_temp.submission_reject($q$insert into public.restroom_submissions(name,latitude,longitude,status) values ('Approved',40,-73,'approved')$q$,'42501','cannot insert approved status');
select pg_temp.submission_reject($q$update public.restroom_submissions set status='approved'$q$,'42501','cannot self-approve');
select pg_temp.submission_reject($q$update public.restroom_submissions set user_id='16000000-0000-0000-0000-000000000002'$q$,'42501','cannot transfer ownership');
select pg_temp.submission_reject($q$update public.restroom_submissions set approved_restroom_id='16100000-0000-0000-0000-000000000001'$q$,'42501','cannot link public restroom');
select pg_temp.submission_reject($q$update public.restroom_submissions set moderation_notes='Approve'$q$,'42501','cannot write moderation metadata');
select pg_temp.submission_reject($q$select moderation_notes,reviewed_by from public.restroom_submissions$q$,'42501','internal moderation data is not client-readable');
update public.restroom_submissions set is_accessible=false,is_free=true,notes='  Updated  ' where id=:'submission_id';
select pg_temp.submission_assert((select is_accessible=false and is_free=true and notes='Updated' from public.restroom_submissions where id=:'submission_id'),'owner can edit content and true/false pending features');
update public.restroom_submissions set is_accessible=null where id=:'submission_id';
select pg_temp.submission_assert((select is_accessible is null from public.restroom_submissions where id=:'submission_id'),'pending edit can restore Unknown');
select pg_temp.submission_assert((select count(*)=2 from public.submission_duplicate_candidates(40,-73,gen_random_uuid())),'duplicates include verified public and own pending, excluding private/unrelated public restrooms');
select pg_temp.submission_assert((select count(*)=1 from public.submission_duplicate_candidates(40,-73,'16200000-0000-0000-0000-000000000001')),'idempotent retry excludes its own request candidate');
select pg_temp.submission_assert((select count(*)=1 from public.submission_duplicate_candidates(40,-73,gen_random_uuid(),:'submission_id')),'pending edit excludes itself');
select pg_temp.submission_reject('select * from public.submission_duplicate_candidates(91,-73,gen_random_uuid())','22023','duplicate RPC rejects invalid coordinates');
select set_config('request.jwt.claims','{"sub":"16000000-0000-0000-0000-000000000002","is_anonymous":false}',true);
select pg_temp.submission_assert((select count(*)=0 from public.restroom_submissions),'B cannot read A submissions');
with changed as(update public.restroom_submissions set name='Changed by B' where id=:'submission_id' returning id)
select pg_temp.submission_assert((select count(*)=0 from changed),'B cannot edit A pending submission');
select pg_temp.submission_assert((select count(*)=1 from public.submission_duplicate_candidates(40,-73,gen_random_uuid())),'duplicate check cannot leak A pending data to B');
select pg_temp.submission_reject(format('delete from public.restroom_submissions where id=%L',:'submission_id'),'42501','ordinary clients cannot delete submissions');
select set_config('request.jwt.claims','{"sub":"16000000-0000-0000-0000-000000000002","is_anonymous":true}',true);
select pg_temp.submission_reject($q$insert into public.restroom_submissions(name,latitude,longitude) values ('Anonymous',40,-73)$q$,'42501','anonymous Auth cannot submit');
select pg_temp.submission_reject('select * from public.submission_duplicate_candidates(40,-73,gen_random_uuid())','42501','anonymous Auth cannot use duplicate endpoint');
reset role;
select pg_temp.submission_assert((select count(*)=:'original_restrooms'::int from public.restrooms),'pending contribution does not create any public restroom row');
-- Only local database owner simulates future privileged moderation; no app endpoint exists.
update public.restroom_submissions set status='approved',approved_restroom_id='16100000-0000-0000-0000-000000000001',
 reviewed_by='16000000-0000-0000-0000-000000000002',reviewed_at=now(),moderation_notes='Internal fixture note'
where id=:'submission_id';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"16000000-0000-0000-0000-000000000001","is_anonymous":false}',true);
select pg_temp.submission_assert((select status='approved' and approved_restroom_id='16100000-0000-0000-0000-000000000001' from public.restroom_submissions where id=:'submission_id'),'owner sees real privileged status and link');
with changed as(update public.restroom_submissions set name='Changed after approval' where id=:'submission_id' returning id)
select pg_temp.submission_assert((select count(*)=0 from changed),'owner cannot edit approved submission');
reset role;
update public.restroom_submissions set status='rejected',approved_restroom_id=null,rejection_reason='Duplicate fixture' where id=:'submission_id';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"16000000-0000-0000-0000-000000000001","is_anonymous":false}',true);
with changed as(update public.restroom_submissions set notes='Changed after rejection' where id=:'submission_id' returning id)
select pg_temp.submission_assert((select count(*)=0 from changed),'owner cannot edit rejected submission');
select pg_temp.submission_assert((select rejection_reason='Duplicate fixture' from public.restroom_submissions where id=:'submission_id'),'owner can read rejection reason without private moderation notes');
reset role;
rollback;
