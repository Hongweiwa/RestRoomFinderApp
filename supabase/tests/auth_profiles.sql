-- Development-only test, run as database owner after BOTH migrations. All fixtures roll back.
begin;
create function pg_temp.auth_assert(value boolean, label text) returns void
language plpgsql as $$ begin
    if not coalesce(value,false) then raise exception 'FAIL: %',label; end if;
    raise notice 'PASS: %',label;
end $$;

insert into auth.users(id,raw_user_meta_data) values
('12000000-0000-0000-0000-000000000001','{"display_name":"  Test Person  "}'),
('12000000-0000-0000-0000-000000000002','{}'),
('12000000-0000-0000-0000-000000000003','{"display_name":42}'),
('12000000-0000-0000-0000-000000000004',jsonb_build_object('display_name',repeat('a',100))),
('12000000-0000-0000-0000-000000000005','{"display_name":"   \n\t"}');
select pg_temp.auth_assert((select display_name='Test Person' from public.profiles where id='12000000-0000-0000-0000-000000000001'), 'profile created before confirmation with exact Auth UUID and trimmed name');
select pg_temp.auth_assert((select display_name is null from public.profiles where id='12000000-0000-0000-0000-000000000002'), 'missing metadata does not block signup');
select pg_temp.auth_assert((select display_name is null from public.profiles where id='12000000-0000-0000-0000-000000000003'), 'non-string metadata does not block signup');
select pg_temp.auth_assert((select char_length(display_name)=80 from public.profiles where id='12000000-0000-0000-0000-000000000004'), 'oversized metadata respects profile constraint');
select pg_temp.auth_assert((select display_name is null from public.profiles where id='12000000-0000-0000-0000-000000000005'), 'blank metadata safely becomes NULL');
insert into auth.users(id,raw_user_meta_data,is_anonymous) values
('12000000-0000-0000-0000-000000000006','{"display_name":"Anonymous"}',true);
select pg_temp.auth_assert(not exists(select 1 from public.profiles where id='12000000-0000-0000-0000-000000000006'), 'anonymous Auth user gets no profile');
update public.profiles set display_name='Durable name' where id='12000000-0000-0000-0000-000000000001';
update auth.users set raw_user_meta_data='{"display_name":"Metadata edit", "role":"admin"}' where id='12000000-0000-0000-0000-000000000001';
select pg_temp.auth_assert((select display_name='Durable name' from public.profiles where id='12000000-0000-0000-0000-000000000001'), 'auth metadata updates cannot overwrite durable profile');
select pg_temp.auth_assert(not has_function_privilege('anon','app_private.create_auth_profile()','EXECUTE') and not has_function_privilege('authenticated','app_private.create_auth_profile()','EXECUTE'), 'profile definer cannot be called by clients');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"12000000-0000-0000-0000-000000000001","is_anonymous":false}',true);
select pg_temp.auth_assert((select count(*)=1 from public.profiles where id::text like '12000000-%'), 'new profile still restricted to its authenticated owner');
reset role;
delete from auth.users where id='12000000-0000-0000-0000-000000000001';
select pg_temp.auth_assert(not exists(select 1 from public.profiles where id='12000000-0000-0000-0000-000000000001'), 'Auth deletion retains existing profile FK behavior');
rollback;
