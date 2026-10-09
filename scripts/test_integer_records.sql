-- Isolated test DB only. Verify decimals cannot enter competitive repetition/round records.
begin;
create function pg_temp.integer_check(ok boolean, label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAILED: %', label; end if; end $$;
create function pg_temp.reject_record(records jsonb) returns void language plpgsql as $$
begin
    perform public.social_publish_records(records);
    raise exception 'FAILED: invalid record accepted';
exception when invalid_parameter_value then null;
end $$;

insert into auth.users values ('00000000-0000-0000-0000-000000000001');
insert into auth.sessions values ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001');
insert into public.record_catalog values
('common-weight-test', 'Weight', 'kg', 'count', 30, false, '', true, 3, 1),
('common-time-test', 'Time', '초', 'count', 30, true, '', true, 4, 1),
('common-empty-test', 'Repetitions', '', 'count', 30, false, '', true, 5, 1);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","session_id":"20000000-0000-0000-0000-000000000001"}', true);
select public.social_save_profile('Integer test', true);
select pg_temp.integer_check(public.social_publish_records(
    '[{"type_id":"common-pushup-v1","value":40,"achieved_at":"2026-10-01"},
      {"type_id":"common-cindy-v1","value":12,"extra_reps":29,"achieved_at":"2026-10-01"},
      {"type_id":"common-weight-test","value":72.5,"achieved_at":"2026-10-01"},
      {"type_id":"common-time-test","value":12.34,"achieved_at":"2026-10-01"}]') = 4,
    'Whole repetitions/rounds and decimal measurements accepted');
select pg_temp.reject_record('[{"type_id":"common-pushup-v1","value":40.004,"achieved_at":"2026-10-01"}]');
select pg_temp.reject_record('[{"type_id":"common-pushup-v1","value":40.000000000000000001,"achieved_at":"2026-10-01"}]');
select pg_temp.reject_record('[{"type_id":"common-empty-test","value":40.5,"achieved_at":"2026-10-01"}]');
select pg_temp.reject_record('[{"type_id":"common-cindy-v1","value":12.9,"achieved_at":"2026-10-01"}]');
select pg_temp.reject_record('[{"type_id":"common-cindy-v1","value":12,"extra_reps":0.5,"achieved_at":"2026-10-01"}]');
select pg_temp.reject_record('[{"type_id":"common-cindy-v1","value":12,"extra_reps":30,"achieved_at":"2026-10-01"}]');
select pg_temp.reject_record('[{"type_id":"common-pushup-v1","value":40,"extra_reps":1,"achieved_at":"2026-10-01"}]');
select pg_temp.reject_record('[{"type_id":"common-pushup-v1","value":100001,"achieved_at":"2026-10-01"}]');
select pg_temp.reject_record('[{"type_id":"common-pushup-v1","achieved_at":"2026-10-01"}]');
select pg_temp.reject_record('[{"type_id":"common-pushup-v1","value":40,"extra_reps":null,"achieved_at":"2026-10-01"}]');
select pg_temp.reject_record('[{"type_id":"common-pushup-v1","value":"40","achieved_at":"2026-10-01"}]');
-- A valid first row must not be committed when a later row is invalid.
select pg_temp.reject_record('[{"type_id":"common-pushup-v1","value":99,"achieved_at":"2026-10-01"},
    {"type_id":"common-cindy-v1","value":12.9,"achieved_at":"2026-10-01"}]');
select pg_temp.integer_check((select value = 40 from public.social_leaderboard() where type_id = 'common-pushup-v1'),
    'Rejected batch leaves earlier records intact');

-- Simulate already-published invalid rows from an older server version.
reset role;
update public.social_records set value = 40.004 where type_id = 'common-pushup-v1';
update public.social_records set value = 12.9 where type_id = 'common-cindy-v1';
set local role authenticated;
select pg_temp.integer_check((select count(*) = 2 from public.social_leaderboard()), 'Old invalid rows hidden, decimal measurements retained');
reset role;
select pg_temp.integer_check((select count(*) = 4 from public.social_records), 'Old rows preserved without silent rounding');
set local role authenticated;
select pg_temp.integer_check(public.social_publish_records(
    '[{"type_id":"common-pushup-v1","value":0,"achieved_at":"2026-10-01"},
      {"type_id":"common-cindy-v1","value":100000,"extra_reps":0,"achieved_at":"2026-10-01"}]') = 2,
    'Inclusive integer value boundaries accepted');
reset role;
delete from auth.sessions where user_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$ begin
    perform public.social_publish_records('[]');
    raise exception 'FAILED: revoked session published';
exception when insufficient_privilege then null; end $$;
do $$ begin
    perform public.social_leaderboard();
    raise exception 'FAILED: revoked session read leaderboard';
exception when insufficient_privilege then null; end $$;
reset role;
select pg_temp.integer_check(not has_function_privilege('anon', 'public.social_publish_records(jsonb)', 'EXECUTE'), 'Anonymous publish still denied');
select pg_temp.integer_check(not has_function_privilege('anon', 'public.social_leaderboard(uuid)', 'EXECUTE'), 'Anonymous rankings still denied');
rollback;
