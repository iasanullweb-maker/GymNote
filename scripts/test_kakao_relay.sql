-- Isolated regression DB only; never run against the live project.
begin;
create function pg_temp.relay_check(value boolean, label text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception 'FAILED: %', label; end if; end $$;

-- App roles have no path to the mailbox, status snapshots or relay functions.
select pg_temp.relay_check(not has_table_privilege(role, 'public.automation_kakao_inbox', privilege), role || ' inbox ' || privilege)
from unnest(array['anon', 'authenticated']) role, unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) privilege;
select pg_temp.relay_check(not has_table_privilege(role, 'public.automation_kakao_tasks', privilege), role || ' tasks ' || privilege)
from unnest(array['anon', 'authenticated']) role, unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) privilege;
select pg_temp.relay_check(not has_function_privilege(role, fn, 'EXECUTE'), role || ' ' || fn)
from unnest(array['anon', 'authenticated']) role,
     unnest(array['public.automation_kakao_actor(text,text)', 'public.automation_kakao_receive(text,text,text)',
                  'public.automation_kakao_claim(integer)', 'public.automation_kakao_ack(uuid,uuid,text,text)',
                  'public.automation_kakao_publish(jsonb)', 'public.automation_kakao_status(text,text,text)']) fn;
select pg_temp.relay_check((select bool_and(relrowsecurity) from pg_class
  where oid in ('public.automation_kakao_inbox'::regclass, 'public.automation_kakao_tasks'::regclass)), 'RLS enabled');
set local role authenticated;
do $$ begin perform public.automation_kakao_receive('bot-1', 'user-1', 'x'); raise exception 'FAILED: app user stored relay item';
exception when insufficient_privilege then null; end $$;
do $$ begin perform count(*) from public.automation_kakao_inbox; raise exception 'FAILED: app user read mailbox';
exception when insufficient_privilege then null; end $$;
reset role;

set local role service_role;
-- Actor hash is byte-identical to automation/ingress/kakao.py (sha256(bot NUL user)).
select pg_temp.relay_check(public.automation_kakao_actor('bot-1', 'user-1')
  = 'kakao:027c2fc75ecd9de1f2afdfe5e58747d0e5a93a9fc633e3444d933031dd384c27', 'Actor matches Python (ASCII)');
select pg_temp.relay_check(public.automation_kakao_actor('봇', '사용자')
  = 'kakao:bc6f4f5dd5a6fe2ddc2fb56ee73547c340da3742d075c89a320d6d17e2895b64', 'Actor matches Python (UTF-8)');

create temp table relay_ids (label text primary key, id uuid, claim uuid);
grant all on relay_ids to service_role;
insert into relay_ids(label, id) values ('first', public.automation_kakao_receive('bot-1', 'user-1', '메모 첫 아이디어'));
insert into relay_ids(label, id) values ('second', public.automation_kakao_receive('bot-1', 'user-1', '실행 key-1 문서 수정'));
select pg_temp.relay_check((select count(*) = 2 from relay_ids where id is not null), 'Items stored while PC is off');

create temp table relay_claimed as select * from public.automation_kakao_claim(10);
select pg_temp.relay_check((select count(*) = 2 from relay_claimed), 'Claim returns waiting items');
select pg_temp.relay_check((select bool_and(item_claim is not null and item_utterance is not null) from relay_claimed), 'Claim gives lease and text');
select pg_temp.relay_check((select count(*) = 0 from public.automation_kakao_claim(10)), 'Leased items are not handed out twice');
update relay_ids r set claim = c.item_claim from relay_claimed c where c.item_id = r.id;

select pg_temp.relay_check(not public.automation_kakao_ack((select id from relay_ids where label = 'first'),
  gen_random_uuid(), null, '거짓 확인'), 'Wrong lease cannot acknowledge');
select pg_temp.relay_check(public.automation_kakao_ack((select id from relay_ids where label = 'first'),
  (select claim from relay_ids where label = 'first'), 'task-1', '아이디어 저장'), 'Lease holder acknowledges');
select pg_temp.relay_check(public.automation_kakao_ack((select id from relay_ids where label = 'first'),
  (select claim from relay_ids where label = 'first'), 'task-1', '아이디어 저장'), 'Repeated acknowledgement is harmless');
select pg_temp.relay_check((select utterance is null and processed_at is not null and task_id = 'task-1'
  from public.automation_kakao_inbox where id = (select id from relay_ids where label = 'first')), 'Processed text is dropped');
do $$ begin
  update public.automation_kakao_inbox set processed_at = null where id = (select id from relay_ids where label = 'first');
  raise exception 'FAILED: processed row reopened without text';
exception when check_violation then null; end $$;

-- An expired lease is handed out again with a new lease; the stale holder can no longer acknowledge.
update public.automation_kakao_inbox set claimed_at = now() - interval '6 minutes'
where id = (select id from relay_ids where label = 'second');
create temp table relay_reclaimed as select * from public.automation_kakao_claim(10);
select pg_temp.relay_check((select count(*) = 1 and bool_and(item_id = (select id from relay_ids where label = 'second'))
  from relay_reclaimed), 'Expired lease is claimed again');
select pg_temp.relay_check((select item_claim <> (select claim from relay_ids where label = 'second') from relay_reclaimed), 'New lease ID');
select pg_temp.relay_check(not public.automation_kakao_ack((select id from relay_ids where label = 'second'),
  (select claim from relay_ids where label = 'second'), null, '늦은 확인'), 'Stale lease rejected');
select pg_temp.relay_check(public.automation_kakao_ack((select item_id from relay_reclaimed),
  (select item_claim from relay_reclaimed), null, '자동 작업 실행이 꺼져 있습니다.'), 'Current lease acknowledges');

do $$ begin perform public.automation_kakao_claim(0); raise exception 'FAILED: zero claim limit';
exception when invalid_parameter_value then null; end $$;
do $$ begin perform public.automation_kakao_claim(21); raise exception 'FAILED: oversized claim limit';
exception when invalid_parameter_value then null; end $$;

-- Per-sender cap bounds storage while the PC stays off; other senders are unaffected.
select public.automation_kakao_receive('bot-1', 'user-full', '메모 ' || n) from generate_series(1, 100) n;
select pg_temp.relay_check(public.automation_kakao_receive('bot-1', 'user-full', '101번째') is null, 'Sender cap enforced');
select pg_temp.relay_check(public.automation_kakao_receive('bot-1', 'user-2', '다른 사용자') is not null, 'Cap is per sender');
do $$ begin perform public.automation_kakao_receive('bot-1', 'user-1', ''); raise exception 'FAILED: empty utterance stored';
exception when check_violation then null; end $$;

-- Status snapshots: upsert, never move a task ID to another actor, bounded batch.
select pg_temp.relay_check(public.automation_kakao_publish(jsonb_build_array(
  jsonb_build_object('id', 'task-1', 'actor', public.automation_kakao_actor('bot-1', 'user-1'),
                     'statusText', 'task-1' || chr(10) || '상태: 메모 저장', 'created', now()))) = 1, 'Snapshot stored');
select pg_temp.relay_check(public.automation_kakao_publish(jsonb_build_array(
  jsonb_build_object('id', 'task-1', 'actor', public.automation_kakao_actor('bot-1', 'user-1'),
                     'statusText', 'task-1' || chr(10) || '상태: 중지 완료', 'created', now()))) = 1, 'Snapshot updated');
select pg_temp.relay_check(public.automation_kakao_publish(jsonb_build_array(
  jsonb_build_object('id', 'task-1', 'actor', public.automation_kakao_actor('bot-1', 'user-2'),
                     'statusText', 'hijack', 'created', now()))) = 0, 'Other actor cannot take a task ID');
select pg_temp.relay_check((select status_text like '%중지 완료' from public.automation_kakao_tasks where id = 'task-1'), 'Owner text kept');
do $$ begin perform public.automation_kakao_publish('{}'::jsonb); raise exception 'FAILED: non-array snapshots';
exception when invalid_parameter_value then null; end $$;
do $$ begin
  perform public.automation_kakao_publish((select jsonb_agg(jsonb_build_object('id', 't' || n, 'actor', 'kakao:x',
    'statusText', 's', 'created', now())) from generate_series(1, 201) n));
  raise exception 'FAILED: oversized snapshot batch';
exception when invalid_parameter_value then null; end $$;

-- Status view is scoped to the sender.
select pg_temp.relay_check((public.automation_kakao_status('bot-1', 'user-1', null)->'tasks'->0->>'id') = 'task-1', 'Own task listed');
select pg_temp.relay_check(jsonb_array_length(public.automation_kakao_status('bot-1', 'user-2', null)->'tasks') = 0, 'Other sender sees no task');
select pg_temp.relay_check(jsonb_array_length(public.automation_kakao_status('bot-1', 'user-1', 'missing')->'tasks') = 0, 'Unknown task ID empty');
select pg_temp.relay_check((public.automation_kakao_status('bot-1', 'user-1', null)->>'waitingCount')::int = 0, 'Nothing waiting for user-1');
select pg_temp.relay_check((public.automation_kakao_status('bot-1', 'user-1', null)->'replies'->0->>'text') like '자동 작업%', 'Untasked reply shown');
select pg_temp.relay_check((public.automation_kakao_status('bot-1', 'user-full', null)->>'waitingCount')::int = 100, 'Waiting count');
select pg_temp.relay_check(jsonb_array_length(public.automation_kakao_status('bot-1', 'user-full', null)->'waiting') = 3, 'Waiting preview bounded');

-- Retention: processed mailbox rows older than 30 days are removed on the next claim.
update public.automation_kakao_inbox set processed_at = now() - interval '31 days'
where id = (select id from relay_ids where label = 'first');
select count(*) from public.automation_kakao_claim(1);
select pg_temp.relay_check(not exists (select 1 from public.automation_kakao_inbox
  where id = (select id from relay_ids where label = 'first')), 'Old processed rows purged');
reset role;
rollback;
\echo 'Kakao relay checks passed: app-role isolation, leases, acknowledgements, sender cap, snapshots, status scope, retention'
