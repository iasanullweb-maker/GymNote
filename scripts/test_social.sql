-- 친구·그룹·기록 공개 권한 회귀 검사. 격리된 테스트 DB 전용(실제 프로젝트에 실행하지 않음).
begin;
create function pg_temp.ok(value boolean, label text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception 'FAILED: %', label; end if; end $$;
create function pg_temp.as_user(n integer) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object(
        'sub', '00000000-0000-0000-0000-00000000000' || n,
        'session_id', '20000000-0000-0000-0000-00000000000' || n)::text, true);
end $$;
grant execute on function pg_temp.as_user(integer) to authenticated;

insert into auth.users values ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002'),
    ('00000000-0000-0000-0000-000000000003'), ('00000000-0000-0000-0000-000000000004');
insert into auth.sessions values
    ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001'),
    ('20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002'),
    ('20000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000003'),
    ('20000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000004');

-- 직접 접근·익명 호출 차단
select pg_temp.ok(not has_table_privilege('authenticated', 'public.social_records', 'SELECT'), 'No direct record reads');
select pg_temp.ok(not has_table_privilege('authenticated', 'public.social_friendships', 'INSERT'), 'No direct friendship writes');
select pg_temp.ok(not has_table_privilege('authenticated', 'public.social_profiles', 'SELECT'), 'No direct profile reads');
select pg_temp.ok(not has_function_privilege('anon', 'public.social_leaderboard(uuid)', 'EXECUTE'), 'Guests cannot read rankings');
select pg_temp.ok(not has_function_privilege('authenticated', 'public.social_are_friends(uuid,uuid)', 'EXECUTE'), 'Helpers are private');

set local role authenticated;
-- 세션이 없거나 폐기된 요청은 거부
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","session_id":"99999999-0000-0000-0000-000000000001"}', true);
do $$ begin perform public.social_overview(); raise exception 'FAILED: revoked session read overview';
exception when insufficient_privilege then null; end $$;

-- 닉네임 전에는 아무것도 공개되지 않고 친구 요청도 못 보냄
select pg_temp.as_user(1);
select pg_temp.ok(public.social_publish_records('[{"type_id":"common-pushup-v1","value":30,"achieved_at":"2026-10-01"}]') = 0, 'No profile, nothing published');
do $$ begin perform public.social_send_friend_request('AAAAAAAA'); raise exception 'FAILED: request without profile';
exception when invalid_parameter_value then null; end $$;
select pg_temp.ok((select friend_code ~ '^[A-HJ-NP-Z2-9]{8}$' from public.social_save_profile(' 수혁 ', true)), 'Profile gets friend code');
select pg_temp.ok((select nickname = '수혁' from public.social_save_profile('수혁', true)), 'Nickname trimmed, code kept');
do $$ begin perform public.social_save_profile('', true); raise exception 'FAILED: empty nickname';
exception when invalid_parameter_value then null; end $$;
select pg_temp.as_user(2);
select public.social_save_profile('민수', true);
select pg_temp.as_user(3);
select public.social_save_profile('지훈', true);

-- 기록 공개 검증: 활성 공통 종목·범위만
select pg_temp.as_user(1);
select pg_temp.ok(public.social_publish_records('[{"type_id":"common-pushup-v1","value":40,"achieved_at":"2026-10-05"},
    {"type_id":"common-cindy-v1","value":12,"extra_reps":7,"achieved_at":"2026-10-06"}]') = 2, 'Publish two records');
do $$ begin perform public.social_publish_records('[{"type_id":"pushup","value":40,"achieved_at":"2026-10-05"}]');
    raise exception 'FAILED: personal type published'; exception when invalid_parameter_value then null; end $$;
do $$ begin perform public.social_publish_records('[{"type_id":"common-pushup-v1","value":-1,"achieved_at":"2026-10-05"}]');
    raise exception 'FAILED: negative value'; exception when invalid_parameter_value then null; end $$;
do $$ begin perform public.social_publish_records('[{"type_id":"common-cindy-v1","value":3,"extra_reps":30,"achieved_at":"2026-10-05"}]');
    raise exception 'FAILED: extra reps exceed a round'; exception when invalid_parameter_value then null; end $$;
select pg_temp.as_user(2);
select pg_temp.ok(public.social_publish_records('[{"type_id":"common-pushup-v1","value":35,"achieved_at":"2026-10-04"}]') = 1, 'B publishes');
select pg_temp.as_user(3);
select pg_temp.ok(public.social_publish_records('[{"type_id":"common-pushup-v1","value":50,"achieved_at":"2026-10-04"}]') = 1, 'C publishes');

-- 친구가 아니면 서로의 기록이 보이지 않음
select pg_temp.as_user(2);
select pg_temp.ok((select count(*) = 1 and bool_and(is_me) from public.social_leaderboard()), 'Before friendship only own records');

-- 친구 요청·수락: 받은 사람만 수락, 다른 사람은 불가
select pg_temp.as_user(1);
select pg_temp.ok(public.social_send_friend_request((select friend_code from public.social_save_profile('수혁', true))) = 'self', 'Cannot friend self');
select pg_temp.ok(public.social_send_friend_request('ZZZZZZZZ') = 'not_found', 'Unknown code');
reset role;
create temp table codes as select user_id, friend_code from public.social_profiles;
grant select on codes to authenticated;
set local role authenticated;
select pg_temp.as_user(1);
select pg_temp.ok(public.social_send_friend_request((select lower(friend_code) from codes where user_id = '00000000-0000-0000-0000-000000000002')) = 'sent', 'A requests B (case-insensitive)');
select pg_temp.ok((select friends->0->>'status' = 'outgoing' from (select public.social_overview()->'friends' as friends) x), 'A sees outgoing');
select pg_temp.ok((select count(*) = 2 and bool_and(is_me) from public.social_leaderboard()), 'Pending request shares nothing');
select pg_temp.as_user(3);
select pg_temp.ok(not public.social_respond_friend_request('00000000-0000-0000-0000-000000000001', true), 'Third party cannot accept');
select pg_temp.as_user(2);
select pg_temp.ok((select friends->0->>'status' = 'incoming' and friends->0->>'nickname' = '수혁'
    from (select public.social_overview()->'friends' as friends) x), 'B sees incoming with nickname');
select pg_temp.ok(not (public.social_overview()::text like '%@%'), 'No email in overview');
select pg_temp.ok(public.social_respond_friend_request('00000000-0000-0000-0000-000000000001', true), 'B accepts');
select pg_temp.ok((select count(*) = 3 from public.social_leaderboard()), 'B sees own + A two records');
select pg_temp.as_user(1);
select pg_temp.ok((select count(*) = 3 from public.social_leaderboard()), 'A sees own two + B');
select pg_temp.ok(not exists (select 1 from public.social_leaderboard() where nickname = '지훈'), 'Non-friend C hidden');
-- 상대가 먼저 요청했으면 내 요청이 곧 수락
select pg_temp.as_user(3);
select pg_temp.ok(public.social_send_friend_request((select friend_code from codes where user_id = '00000000-0000-0000-0000-000000000001')) = 'sent', 'C requests A');
select pg_temp.as_user(1);
select pg_temp.ok(public.social_send_friend_request((select friend_code from codes where user_id = '00000000-0000-0000-0000-000000000003')) = 'accepted', 'Mutual request accepts');
select pg_temp.ok(public.social_send_friend_request((select friend_code from codes where user_id = '00000000-0000-0000-0000-000000000003')) = 'already_friends', 'Already friends');

-- 그룹: 가입자만 친구를 초대, 수락 전에는 순위를 볼 수 없음
select pg_temp.as_user(1);
create temp table g as select public.social_create_group(' 헬스 동아리 ') as id;
reset role; grant select on g to authenticated; set local role authenticated;
select pg_temp.as_user(1);
select pg_temp.ok(public.social_invite_to_group((select id from g), '00000000-0000-0000-0000-000000000002'), 'Owner invites friend B');
do $$ begin perform public.social_invite_to_group((select id from g), '00000000-0000-0000-0000-000000000004');
    raise exception 'FAILED: invited a non-friend'; exception when insufficient_privilege then null; end $$;
select pg_temp.as_user(3);
do $$ begin perform public.social_invite_to_group((select id from g), '00000000-0000-0000-0000-000000000001');
    raise exception 'FAILED: non-member invited'; exception when insufficient_privilege then null; end $$;
do $$ begin perform public.social_leaderboard((select id from g));
    raise exception 'FAILED: outsider read group ranking'; exception when insufficient_privilege then null; end $$;
select pg_temp.as_user(2);
select pg_temp.ok((select g2->>'joined' = 'false' and jsonb_array_length(g2->'members') = 2
    from (select public.social_overview()->'groups'->0 as g2) x), 'Invitee sees invite with owner only');
do $$ begin perform public.social_leaderboard((select id from g));
    raise exception 'FAILED: invitee read ranking before joining'; exception when insufficient_privilege then null; end $$;
select pg_temp.ok(public.social_respond_group_invite((select id from g), true), 'B joins');
select pg_temp.ok((select count(*) = 3 from public.social_leaderboard((select id from g))), 'Group ranking A(2)+B(1)');
-- 그룹원이지만 친구가 아닌 사람도 그룹 순위에서는 보임: B가 친구 C를 초대
reset role;
insert into public.social_friendships values ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.as_user(2);
select pg_temp.ok(public.social_invite_to_group((select id from g), '00000000-0000-0000-0000-000000000003'), 'Member B invites friend C');
select pg_temp.as_user(3);
select pg_temp.ok(public.social_respond_group_invite((select id from g), true), 'C joins');
select pg_temp.ok((select count(*) = 4 from public.social_leaderboard((select id from g))), 'Group shows all members');

-- 공개 끄기: 기록이 서버에서 지워지고 더 올라가지 않음
select pg_temp.as_user(2);
select public.social_save_profile('민수', false);
select pg_temp.ok(public.social_publish_records('[{"type_id":"common-pushup-v1","value":99,"achieved_at":"2026-10-07"}]') = 0, 'Sharing off publishes nothing');
reset role;
select pg_temp.ok((select count(*) = 0 from public.social_records where user_id = '00000000-0000-0000-0000-000000000002'), 'Sharing off deletes records');
set local role authenticated;
select pg_temp.as_user(1);
select pg_temp.ok(not exists (select 1 from public.social_leaderboard() where nickname = '민수'), 'Hidden from friends');
-- 다시 올리면 없어진 종목은 지움
select pg_temp.ok(public.social_publish_records('[{"type_id":"common-pushup-v1","value":41,"achieved_at":"2026-10-08"}]') = 1, 'Republish one');
select pg_temp.ok((select count(*) = 1 and max(value) = 41 from public.social_leaderboard() where is_me), 'Removed type deleted, value updated');

-- 그룹장 나가기: 다음 그룹원에게 넘김, 모두 나가면 그룹 삭제
select pg_temp.ok(public.social_leave_group((select id from g)), 'Owner leaves');
reset role;
select pg_temp.ok((select owner = '00000000-0000-0000-0000-000000000002' from public.social_groups where id = (select id from g)), 'Ownership transferred');
set local role authenticated;
select pg_temp.as_user(2); select public.social_leave_group((select id from g));
select pg_temp.as_user(3); select public.social_leave_group((select id from g));
reset role;
select pg_temp.ok(not exists (select 1 from public.social_groups where id = (select id from g)), 'Empty group deleted');

-- 친구 끊기, 계정 삭제 시 모두 정리
set local role authenticated;
select pg_temp.as_user(1);
select pg_temp.ok(public.social_remove_friend('00000000-0000-0000-0000-000000000003'), 'Unfriend C');
select pg_temp.ok(not exists (select 1 from public.social_leaderboard() where nickname = '지훈'), 'C hidden after unfriend');
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-000000000001';
select pg_temp.ok((select count(*) = 0 from public.social_records where user_id = '00000000-0000-0000-0000-000000000001'), 'Records deleted with account');
select pg_temp.ok((select count(*) = 0 from public.social_friendships
    where '00000000-0000-0000-0000-000000000001' in (requester, addressee)), 'Friendships deleted with account');
select pg_temp.ok((select count(*) = 0 from public.social_profiles where user_id = '00000000-0000-0000-0000-000000000001'), 'Profile deleted with account');
rollback;
\echo 'Social checks passed: profiles, friend requests, groups, rankings, sharing off, account deletion'
