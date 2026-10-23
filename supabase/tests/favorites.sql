begin;
create function pg_temp.fav_assert(value boolean, label text) returns void language plpgsql as $$ begin
 if not coalesce(value,false) then raise exception 'FAIL: %',label; end if; raise notice 'PASS: %',label;
end $$;
insert into auth.users(id) values ('14000000-0000-0000-0000-000000000001'),('14000000-0000-0000-0000-000000000002');
select pg_temp.fav_assert(not has_function_privilege('anon','public.resolve_google_restroom(text)','execute'), 'guest cannot create Google anchors');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"14000000-0000-0000-0000-000000000001","is_anonymous":false}',true);
select public.resolve_google_restroom('day14-test-place') as anchor \gset
select pg_temp.fav_assert(public.resolve_google_restroom('day14-test-place') = :'anchor'::uuid, 'repeated Google resolution uses one UUID');
insert into public.favorites(restroom_id) values (:'anchor');
insert into public.favorites(user_id,restroom_id) values ('14000000-0000-0000-0000-000000000001',:'anchor') on conflict(user_id,restroom_id) do nothing;
select pg_temp.fav_assert((select count(*)=1 from public.favorites where restroom_id=:'anchor'), 'duplicate saves create one relationship');
select pg_temp.fav_assert((select name is null and address is null and latitude is null and longitude is null and verification_status='unverified' from public.restrooms where id=:'anchor'), 'Google anchor contains no copied display data and never claims verification');
select set_config('request.jwt.claims','{"sub":"14000000-0000-0000-0000-000000000002","is_anonymous":false}',true);
select pg_temp.fav_assert(not exists(select 1 from public.favorites where restroom_id=:'anchor'), 'B cannot read A favorites');
delete from public.favorites where restroom_id=:'anchor';
do $$ begin
 insert into public.favorites(user_id,restroom_id) values ('14000000-0000-0000-0000-000000000001',public.resolve_google_restroom('day14-test-place'));
 raise exception 'FAIL: spoofed favorite owner';
exception when insufficient_privilege then raise notice 'PASS: cannot insert favorite for A'; end $$;
insert into public.favorites(restroom_id) values (public.resolve_google_restroom('day14-test-place'));
select pg_temp.fav_assert((select count(*)=1 from public.favorites where restroom_id=:'anchor'), 'B sees only its own relationship');
select set_config('request.jwt.claims','{"sub":"14000000-0000-0000-0000-000000000001","is_anonymous":false}',true);
select pg_temp.fav_assert((select count(*)=1 from public.favorites where restroom_id=:'anchor'), 'B could not delete A favorite');
delete from public.favorites where restroom_id=:'anchor';
select pg_temp.fav_assert(exists(select 1 from public.restrooms where id=:'anchor'), 'unsave does not delete restroom');
select set_config('request.jwt.claims','{"sub":"14000000-0000-0000-0000-000000000002","is_anonymous":false}',true);
select pg_temp.fav_assert(exists(select 1 from public.favorites where restroom_id=:'anchor'), 'A unsave preserves B relationship');
select set_config('request.jwt.claims','{"sub":"14000000-0000-0000-0000-000000000002","is_anonymous":true}',true);
do $$ begin
 perform public.resolve_google_restroom('anonymous-forbidden'); raise exception 'FAIL: anonymous anchor creation';
exception when insufficient_privilege then raise notice 'PASS: anonymous anchor creation rejected'; end $$;
reset role;
select pg_temp.fav_assert((select count(*)=1 from public.restrooms where google_place_id='day14-test-place'), 'unique Google identity across accounts');
rollback;
