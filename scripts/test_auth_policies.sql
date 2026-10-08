begin;
create function pg_temp.check_true(value boolean, label text) returns void language plpgsql as $$
begin
  if value is distinct from true then raise exception 'FAILED: %', label; end if;
end;
$$;

insert into auth.users(id) values ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002');
insert into auth.sessions(id,user_id) values
  ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002');

select pg_temp.check_true(not has_table_privilege('authenticated','public.workout_backups','INSERT'), 'No direct client INSERT');
select pg_temp.check_true(not has_table_privilege('authenticated','public.workout_backups','UPDATE'), 'No direct client UPDATE');
select pg_temp.check_true(not has_table_privilege('authenticated','public.workout_backups','DELETE'), 'No direct client DELETE');
select pg_temp.check_true(not has_function_privilege('anon','public.load_workout()','EXECUTE'), 'Anonymous read denied');
select pg_temp.check_true(not has_function_privilege('anon','public.save_workout(jsonb,bigint)','EXECUTE'), 'Anonymous write denied');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}',true);
select pg_temp.check_true(public.gymnote_session_valid(), 'Active own session');
select pg_temp.check_true((select count(*) = 1 from public.save_workout(
  '{"week":[],"recordTypes":[],"records":[],"logs":[],"scheduledPlans":{},"exerciseLibrary":[],"defaultRest":90,"restSound":false}',0)), 'Initial snapshot saved');
select pg_temp.check_true((select count(*) = 0 from public.save_workout(
  '{"week":[],"recordTypes":[],"records":[],"logs":[],"scheduledPlans":{},"exerciseLibrary":[],"defaultRest":90,"restSound":false}',0)), 'Duplicate initial upload rejected');
select pg_temp.check_true((select count(*) = 1 from public.save_workout(
  '{"week":[],"recordTypes":[],"records":[],"logs":[],"scheduledPlans":{},"exerciseLibrary":[],"defaultRest":45,"restSound":false}',1)), 'CAS update accepted');
select pg_temp.check_true((select count(*) = 0 from public.save_workout(
  '{"week":[],"recordTypes":[],"records":[],"logs":[],"scheduledPlans":{},"exerciseLibrary":[],"defaultRest":75,"restSound":false}',1)), 'Stale device overwrite rejected');
select pg_temp.check_true((select version = 2 and payload->>'defaultRest' = '45' from public.load_workout()), 'Winning snapshot preserved');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000002"}',true);
select pg_temp.check_true((select count(*) = 0 from public.load_workout()), 'B cannot read A via RPC');
select pg_temp.check_true((select count(*) = 0 from public.workout_backups), 'B cannot read A via direct REST');
select pg_temp.check_true((select count(*) = 0 from public.save_workout(
  '{"week":[],"recordTypes":[],"records":[],"logs":[],"scheduledPlans":{},"exerciseLibrary":[],"defaultRest":75,"restSound":false}',2)), 'B cannot update A');
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000002","session_id":"10000000-0000-0000-0000-000000000001"}',true);
select pg_temp.check_true(not public.gymnote_session_valid(), 'Wrong session owner denied');
do $$ begin
  perform public.load_workout();
  raise exception 'FAILED: Wrong owner RPC accepted';
exception when insufficient_privilege then null; end $$;

reset role;
delete from auth.sessions where user_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}',true);
select pg_temp.check_true(not public.gymnote_session_valid(), 'Revoked session denied');
select pg_temp.check_true((select count(*) = 0 from public.workout_backups), 'Revoked JWT blocked by RLS');
do $$ begin
  perform public.save_workout('{"week":[]}',2);
  raise exception 'FAILED: Revoked session upload accepted';
exception when insufficient_privilege then null; end $$;
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-000000000001';
select pg_temp.check_true((select count(*) = 0 from public.workout_backups), 'Account deletion cascades to records');
rollback;
