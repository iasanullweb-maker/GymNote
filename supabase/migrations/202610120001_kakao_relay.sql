-- Kakao channel relay mailbox (2026-10-12).
-- The kakao-skill Edge Function (service_role) stores Kakao requests here even while the PC is off.
-- The PC automation service later claims them through the same function and publishes safe status text.
-- App users (anon/authenticated) get no table or function access. Agents never run in the cloud.

create table if not exists public.automation_kakao_inbox (
  id uuid primary key default gen_random_uuid(),
  bot_id text not null check (char_length(bot_id) between 1 and 100),
  user_key text not null check (char_length(user_key) between 1 and 100),
  -- Kept only until the PC copies it into the local queue; cleared on acknowledgement.
  utterance text check (utterance is null or char_length(utterance) between 1 and 8200),
  received_at timestamptz not null default now(),
  claimed_at timestamptz,
  claim_id uuid,
  processed_at timestamptz,
  task_id text check (task_id is null or char_length(task_id) between 1 and 100),
  reply_text text check (reply_text is null or char_length(reply_text) between 1 and 1000),
  constraint automation_kakao_inbox_payload_lifecycle check ((processed_at is null) = (utterance is not null))
);
create index if not exists automation_kakao_inbox_waiting
  on public.automation_kakao_inbox (received_at, id) where processed_at is null;
create index if not exists automation_kakao_inbox_sender
  on public.automation_kakao_inbox (bot_id, user_key, received_at desc);

create table if not exists public.automation_kakao_tasks (
  id text primary key check (char_length(id) between 1 and 100),
  actor text not null check (char_length(actor) between 1 and 200),
  status_text text not null check (char_length(status_text) between 1 and 1000),
  created_at timestamptz not null,
  updated_at timestamptz not null default now()
);
create index if not exists automation_kakao_tasks_actor
  on public.automation_kakao_tasks (actor, created_at desc);

alter table public.automation_kakao_inbox enable row level security;
alter table public.automation_kakao_tasks enable row level security;
revoke all on table public.automation_kakao_inbox, public.automation_kakao_tasks from public, anon, authenticated;
grant select, insert, update, delete on table public.automation_kakao_inbox, public.automation_kakao_tasks to service_role;

-- Same actor as automation/ingress/kakao.py: 'kakao:' || sha256(bot || NUL || user).
create or replace function public.automation_kakao_actor(p_bot text, p_user text)
returns text language sql immutable set search_path = public as $$
  select 'kakao:' || encode(sha256(convert_to(p_bot, 'UTF8') || '\x00'::bytea || convert_to(p_user, 'UTF8')), 'hex');
$$;

-- Store one request. Returns null when this sender already has 100 unprocessed items (PC off for long).
create or replace function public.automation_kakao_receive(p_bot text, p_user text, p_utterance text)
returns uuid language plpgsql set search_path = public as $$
declare
  v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtext('automation_kakao_inbox:' || p_bot || ':' || p_user));
  if (select count(*) from public.automation_kakao_inbox
      where bot_id = p_bot and user_key = p_user and processed_at is null) >= 100 then
    return null;
  end if;
  insert into public.automation_kakao_inbox (bot_id, user_key, utterance)
  values (p_bot, p_user, p_utterance)
  returning id into v_id;
  return v_id;
end $$;

-- Lease up to p_limit waiting items for five minutes. An unacknowledged lease is claimed again later;
-- the PC deduplicates replays by mailbox ID (memo) or request key (run/retry).
create or replace function public.automation_kakao_claim(p_limit integer)
returns table (item_id uuid, item_claim uuid, item_bot text, item_user text, item_utterance text, item_received timestamptz)
language plpgsql set search_path = public as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 20 then
    raise exception 'invalid claim limit' using errcode = '22023';
  end if;
  delete from public.automation_kakao_inbox where processed_at < now() - interval '30 days';
  delete from public.automation_kakao_tasks where updated_at < now() - interval '90 days';
  return query
  with picked as (
    select inbox.id
    from public.automation_kakao_inbox inbox
    where inbox.processed_at is null
      and (inbox.claimed_at is null or inbox.claimed_at < now() - interval '5 minutes')
    order by inbox.received_at, inbox.id
    limit p_limit
    for update skip locked
  )
  update public.automation_kakao_inbox inbox
  set claimed_at = now(), claim_id = gen_random_uuid()
  from picked
  where inbox.id = picked.id
  returning inbox.id, inbox.claim_id, inbox.bot_id, inbox.user_key, inbox.utterance, inbox.received_at;
end $$;

-- Mark a leased item processed and drop its text. Repeating the same acknowledgement is harmless;
-- an expired lease (claimed again by a newer pull) is rejected.
create or replace function public.automation_kakao_ack(p_id uuid, p_claim uuid, p_task text, p_reply text)
returns boolean language plpgsql set search_path = public as $$
begin
  update public.automation_kakao_inbox
  set processed_at = now(), utterance = null, task_id = p_task, reply_text = left(p_reply, 1000)
  where id = p_id and claim_id = p_claim and processed_at is null;
  if found then
    return true;
  end if;
  return exists (select 1 from public.automation_kakao_inbox
                 where id = p_id and claim_id = p_claim and processed_at is not null);
end $$;

-- Upsert safe status text rendered by the PC. A task ID is never moved to another actor.
create or replace function public.automation_kakao_publish(p_tasks jsonb)
returns integer language plpgsql set search_path = public as $$
declare
  v_count integer;
begin
  if p_tasks is null or jsonb_typeof(p_tasks) <> 'array' or jsonb_array_length(p_tasks) > 200 then
    raise exception 'invalid task snapshots' using errcode = '22023';
  end if;
  insert into public.automation_kakao_tasks (id, actor, status_text, created_at, updated_at)
  select item->>'id', item->>'actor', item->>'statusText', (item->>'created')::timestamptz, now()
  from jsonb_array_elements(p_tasks) item
  on conflict (id) do update
    set status_text = excluded.status_text, updated_at = now()
    where public.automation_kakao_tasks.actor = excluded.actor;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- What the sender sees for '상태': their latest task snapshots, waiting items and recent untasked replies.
create or replace function public.automation_kakao_status(p_bot text, p_user text, p_task text)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'tasks', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'text', t.status_text, 'updated', t.updated_at)
                       order by t.created_at desc)
      from (select * from public.automation_kakao_tasks
            where actor = public.automation_kakao_actor(p_bot, p_user) and (p_task is null or id = p_task)
            order by created_at desc limit 5) t), '[]'::jsonb),
    'waitingCount', (select count(*) from public.automation_kakao_inbox
                     where bot_id = p_bot and user_key = p_user and processed_at is null),
    'waiting', coalesce((
      select jsonb_agg(jsonb_build_object('received', w.received_at, 'preview', left(w.utterance, 40))
                       order by w.received_at)
      from (select * from public.automation_kakao_inbox
            where bot_id = p_bot and user_key = p_user and processed_at is null
            order by received_at limit 3) w), '[]'::jsonb),
    'replies', coalesce((
      select jsonb_agg(jsonb_build_object('processed', r.processed_at, 'text', r.reply_text)
                       order by r.processed_at desc)
      from (select * from public.automation_kakao_inbox
            where bot_id = p_bot and user_key = p_user and processed_at > now() - interval '1 day'
              and task_id is null and reply_text is not null
            order by processed_at desc limit 3) r), '[]'::jsonb));
$$;

revoke all on function public.automation_kakao_actor(text, text) from public, anon, authenticated;
revoke all on function public.automation_kakao_receive(text, text, text) from public, anon, authenticated;
revoke all on function public.automation_kakao_claim(integer) from public, anon, authenticated;
revoke all on function public.automation_kakao_ack(uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function public.automation_kakao_publish(jsonb) from public, anon, authenticated;
revoke all on function public.automation_kakao_status(text, text, text) from public, anon, authenticated;
grant execute on function public.automation_kakao_actor(text, text) to service_role;
grant execute on function public.automation_kakao_receive(text, text, text) to service_role;
grant execute on function public.automation_kakao_claim(integer) to service_role;
grant execute on function public.automation_kakao_ack(uuid, uuid, text, text) to service_role;
grant execute on function public.automation_kakao_publish(jsonb) to service_role;
grant execute on function public.automation_kakao_status(text, text, text) to service_role;
