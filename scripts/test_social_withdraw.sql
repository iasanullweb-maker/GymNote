-- Isolated regression DB only; never run against the live project.
begin;
create function pg_temp.withdraw_check(value boolean, label text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception 'FAILED: %', label; end if; end $$;
insert into auth.users values ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002');
insert into auth.sessions values
 ('30000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001'),
 ('30000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002');
insert into public.workout_backups(user_id,version,payload) values
 ('00000000-0000-0000-0000-000000000001',1,'{"records":[{"value":30}],"workouts":[{"title":"private journal"}]}');
insert into public.social_profiles values
 ('00000000-0000-0000-0000-000000000001','owner','AAAA2345',true,now()),
 ('00000000-0000-0000-0000-000000000002','friend','BBBB2345',true,now());
insert into public.social_friendships(requester,addressee,accepted) values
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',true);
insert into public.social_groups(id,name,owner) values
 ('40000000-0000-0000-0000-000000000001','shared','00000000-0000-0000-0000-000000000001'),
 ('40000000-0000-0000-0000-000000000002','alone','00000000-0000-0000-0000-000000000001');
insert into public.social_group_members(group_id,user_id,joined) values
 ('40000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001',true),
 ('40000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',true),
 ('40000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001',true);
insert into public.social_records(user_id,type_id,value,achieved_at) values
 ('00000000-0000-0000-0000-000000000001','common-pushup-v1',30,current_date),
 ('00000000-0000-0000-0000-000000000002','common-pushup-v1',20,current_date);
select pg_temp.withdraw_check(not has_function_privilege('anon','public.social_withdraw()','EXECUTE'), 'Guest cannot withdraw');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","session_id":"99999999-0000-0000-0000-000000000001"}',true);
do $$ begin perform public.social_withdraw(); raise exception 'FAILED: invalid session withdrew';
exception when insufficient_privilege then null; end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","session_id":"30000000-0000-0000-0000-000000000001"}',true);
select pg_temp.withdraw_check(public.social_withdraw(), 'Withdrawal succeeds');
select pg_temp.withdraw_check(public.social_withdraw(), 'Repeated withdrawal is idempotent');
select pg_temp.withdraw_check(public.social_overview()->'profile' = 'null'::jsonb, 'No profile after withdrawal');
select pg_temp.withdraw_check(public.social_publish_records('[]') = 0, 'Cannot publish after withdrawal');
reset role;
select pg_temp.withdraw_check((select count(*) = 2 from auth.users), 'App accounts preserved');
select pg_temp.withdraw_check((select count(*) = 2 from auth.sessions), 'Sessions preserved');
select pg_temp.withdraw_check((select payload = '{"records":[{"value":30}],"workouts":[{"title":"private journal"}]}'::jsonb
 from public.workout_backups where user_id = '00000000-0000-0000-0000-000000000001'), 'Private backup preserved exactly');
select pg_temp.withdraw_check((select count(*) = 1 from public.social_profiles), 'Other profile preserved');
select pg_temp.withdraw_check((select count(*) = 0 from public.social_friendships), 'Friendships removed');
select pg_temp.withdraw_check((select count(*) = 1 from public.social_records), 'Only own published records removed');
select pg_temp.withdraw_check((select owner = '00000000-0000-0000-0000-000000000002' from public.social_groups
 where id = '40000000-0000-0000-0000-000000000001'), 'Owner transferred');
select pg_temp.withdraw_check((select count(*) = 1 from public.social_groups), 'Empty owned group removed');
select pg_temp.withdraw_check((select count(*) = 1 from public.social_group_members), 'Own memberships removed');
-- FK checks prevent an old in-flight sender/publisher from restoring deleted social data.
do $$ begin
 insert into public.social_records(user_id,type_id,value,achieved_at)
 values ('00000000-0000-0000-0000-000000000001','common-pushup-v1',99,current_date);
 raise exception 'FAILED: withdrawn profile records resurrected';
exception when foreign_key_violation then null; end $$;
do $$ begin
 insert into public.social_friendships(requester,addressee)
 values ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001');
 raise exception 'FAILED: withdrawn profile friendship resurrected';
exception when foreign_key_violation then null; end $$;
set local role authenticated;
select public.social_save_profile('rejoined',false);
select pg_temp.withdraw_check(jsonb_array_length(public.social_overview()->'friends') = 0, 'Rejoining does not restore friends');
select pg_temp.withdraw_check(jsonb_array_length(public.social_overview()->'groups') = 0, 'Rejoining does not restore groups');
rollback;
