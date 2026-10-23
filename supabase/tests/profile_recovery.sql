-- Local disposable test database only. Fixtures roll back.
begin;
create function pg_temp.profile_assert(value boolean, label text) returns void
language plpgsql as $$ begin
    if not coalesce(value,false) then raise exception 'FAIL: %',label; end if;
    raise notice 'PASS: %',label;
end $$;
insert into auth.users(id,raw_user_meta_data) values
('13000000-0000-0000-0000-000000000001','{"display_name":"User A"}'),
('13000000-0000-0000-0000-000000000002','{"display_name":"User B"}');
-- Simulate a legacy missing row, not a new signup (the existing trigger covers new users).
delete from public.profiles where id='13000000-0000-0000-0000-000000000001';
select pg_temp.profile_assert(not has_function_privilege('anon','public.ensure_current_profile()','EXECUTE'), 'guest cannot invoke profile recovery');
select pg_temp.profile_assert(not (select prosecdef from pg_proc where oid='public.ensure_current_profile()'::regprocedure), 'profile recovery runs under caller RLS');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"13000000-0000-0000-0000-000000000001","is_anonymous":false}',true);
select pg_temp.profile_assert((select id='13000000-0000-0000-0000-000000000001' and display_name is null from public.ensure_current_profile()), 'missing profile recovered for caller UUID only');
update public.profiles set display_name='Edited Name' where id='13000000-0000-0000-0000-000000000001';
select pg_temp.profile_assert((select display_name='Edited Name' from public.ensure_current_profile()), 'repeated recovery preserves edited display name');
select pg_temp.profile_assert((select count(*)=1 from public.ensure_current_profile()), 'recovery is idempotent');
update public.profiles set display_name='Wrong Owner' where id='13000000-0000-0000-0000-000000000002';
select pg_temp.profile_assert(not exists(select 1 from public.profiles where id='13000000-0000-0000-0000-000000000002'), 'user A cannot read user B');
select set_config('request.jwt.claims','{"sub":"13000000-0000-0000-0000-000000000002","is_anonymous":false}',true);
select pg_temp.profile_assert((select display_name='User B' from public.ensure_current_profile()), 'user B unaffected by user A update');
select set_config('request.jwt.claims','{"sub":"13000000-0000-0000-0000-000000000002","is_anonymous":true}',true);
do $$ begin
    perform public.ensure_current_profile();
    raise exception 'FAIL: anonymous session recovered a profile';
exception when insufficient_privilege then raise notice 'PASS: anonymous Auth recovery rejected'; end $$;
select set_config('request.jwt.claims','{}',true);
do $$ begin
    perform public.ensure_current_profile();
    raise exception 'FAIL: missing identity recovered a profile';
exception when insufficient_privilege then raise notice 'PASS: missing identity rejected'; end $$;
reset role;
select pg_temp.profile_assert((select display_name='Edited Name' from public.profiles where id='13000000-0000-0000-0000-000000000001'), 'edited name persists in database');
rollback;
