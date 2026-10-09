begin;
create function pg_temp.catalog_check(ok boolean, label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAILED: %', label; end if; end $$;

insert into auth.users values
('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002');
insert into auth.sessions values
('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001'),
('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002');
insert into public.record_catalog_admins values ('00000000-0000-0000-0000-000000000001');

select pg_temp.catalog_check(not has_table_privilege('authenticated','public.record_catalog','UPDATE'), 'Direct writes denied');
select pg_temp.catalog_check(not has_table_privilege('authenticated','public.record_catalog_admins','INSERT'), 'Self promotion denied');
select pg_temp.catalog_check(not has_function_privilege('anon','public.save_record_catalog_type(jsonb,bigint)','EXECUTE'), 'Anonymous write denied');
set local role anon;
select pg_temp.catalog_check((select count(*) = 3 from public.list_record_catalog()), 'Guest gets common list');
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002","user_metadata":{"admin":true}}',true);
select pg_temp.catalog_check(not public.is_record_catalog_admin(), 'Metadata cannot grant admin');
do $$ begin
    perform public.save_record_catalog_type('{}',0);
    raise exception 'FAILED: ordinary user wrote catalog';
exception when insufficient_privilege then null; end $$;

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}',true);
select pg_temp.catalog_check(public.is_record_catalog_admin(), 'Server assigned admin recognized');
select pg_temp.catalog_check((select count(*) = 1 from public.save_record_catalog_type(
    '{"id":"common-test-v1","name":"테스트","unit":"초","style":"count","repsPerRound":30,"lowerIsBetter":true,"hint":"고정 조건","active":true,"position":3}',0)), 'Admin creates definition');
-- Admin-created active definitions must be visible to another ordinary user and a guest.
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}',true);
select pg_temp.catalog_check((select name = '테스트' and active from public.list_record_catalog() where id = 'common-test-v1'), 'Ordinary user sees newly created definition');
reset role;
set local role anon;
select pg_temp.catalog_check((select name = '테스트' and active from public.list_record_catalog() where id = 'common-test-v1'), 'Guest sees newly created definition');
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}',true);
select pg_temp.catalog_check((select count(*) = 0 from public.save_record_catalog_type(
    '{"id":"common-test-v1","name":"중복","unit":"초","style":"count","repsPerRound":30,"lowerIsBetter":true,"hint":"고정 조건","active":true,"position":3}',0)), 'Duplicate ID conflict');
select pg_temp.catalog_check((select revision = 2 and not active from public.save_record_catalog_type(
    '{"id":"common-test-v1","name":"수정","unit":"초","style":"count","repsPerRound":30,"lowerIsBetter":true,"hint":"오탈자 정정","active":false,"position":4}',1)), 'Admin edits and retires');
select pg_temp.catalog_check((select count(*) = 0 from public.save_record_catalog_type(
    '{"id":"common-test-v1","name":"오래된 수정","unit":"초","style":"count","repsPerRound":30,"lowerIsBetter":true,"hint":"","active":true,"position":3}',1)), 'Stale revision conflict');
do $$ begin
    perform public.save_record_catalog_type(
    '{"id":"common-test-v1","name":"수정","unit":"kg","style":"count","repsPerRound":30,"lowerIsBetter":true,"hint":"","active":true,"position":3}',2);
    raise exception 'FAILED: scoring unit changed';
exception when invalid_parameter_value then null; end $$;
do $$ begin
    perform public.save_record_catalog_type(
    '{"id":"common-bad-v1","name":"","unit":"회","style":"count","repsPerRound":30,"lowerIsBetter":false,"hint":"","active":true,"position":3}',0);
    raise exception 'FAILED: invalid name accepted';
exception when check_violation then null; end $$;
reset role;
delete from auth.sessions where user_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.catalog_check(not public.is_record_catalog_admin(), 'Revoked session loses admin');
do $$ begin
    perform public.save_record_catalog_type('{}',0);
    raise exception 'FAILED: revoked session wrote catalog';
exception when insufficient_privilege then null; end $$;
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-000000000001';
select pg_temp.catalog_check((select count(*) = 0 from public.record_catalog_admins), 'Admin assignment cascades');
select pg_temp.catalog_check((select count(*) = 4 from public.list_record_catalog()), 'Account deletion preserves catalog');
rollback;
