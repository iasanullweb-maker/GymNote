-- 친구·그룹·공통 종목 기록 공개·순위.
-- 앱은 테이블에 직접 접근하지 않고 아래 함수만 호출한다. 모든 함수는 활성 세션(gymnote_session_valid)과
-- auth.uid()로 호출자를 정하며, 요청 본문의 사용자 ID로 다른 사람의 데이터를 바꿀 수 없다.
-- 공개되는 정보: 닉네임, 친구 코드(본인에게만), 공통 종목 최고기록. 이메일은 노출하지 않는다.
begin;

create table public.social_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    nickname text not null check (length(btrim(nickname)) between 1 and 20),
    friend_code text not null unique check (friend_code ~ '^[A-HJ-NP-Z2-9]{8}$'),
    share_records boolean not null default true,
    created_at timestamptz not null default now()
);

create table public.social_friendships (
    requester uuid not null references auth.users(id) on delete cascade,
    addressee uuid not null references auth.users(id) on delete cascade,
    accepted boolean not null default false,
    created_at timestamptz not null default now(),
    primary key (requester, addressee),
    check (requester <> addressee)
);
-- 한 쌍에는 한 방향 행만 존재한다.
create unique index social_friendships_pair
    on public.social_friendships (least(requester, addressee), greatest(requester, addressee));

create table public.social_groups (
    id uuid primary key default gen_random_uuid(),
    name text not null check (length(btrim(name)) between 1 and 30),
    owner uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now()
);

create table public.social_group_members (
    group_id uuid not null references public.social_groups(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    joined boolean not null default false, -- false: 초대받고 아직 수락 전
    invited_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now(),
    primary key (group_id, user_id)
);

create table public.social_records (
    user_id uuid not null references auth.users(id) on delete cascade,
    type_id text not null references public.record_catalog(id) on delete cascade,
    value double precision not null check (value >= 0 and value <= 100000),
    extra_reps integer not null default 0 check (extra_reps between 0 and 10000),
    achieved_at date not null,
    updated_at timestamptz not null default now(),
    primary key (user_id, type_id)
);

alter table public.social_profiles enable row level security;
alter table public.social_friendships enable row level security;
alter table public.social_groups enable row level security;
alter table public.social_group_members enable row level security;
alter table public.social_records enable row level security;
revoke all on public.social_profiles, public.social_friendships, public.social_groups,
    public.social_group_members, public.social_records from public, anon, authenticated;

-- 활성 세션의 사용자. 로그아웃으로 폐기된 세션·익명 요청은 거부한다.
create function public.social_caller() returns uuid
language plpgsql stable security definer set search_path = '' as $$
begin
    if auth.uid() is null or not public.gymnote_session_valid() then
        raise insufficient_privilege using message = 'Authentication required';
    end if;
    return auth.uid();
end;
$$;

create function public.social_are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select exists (select 1 from public.social_friendships f where f.accepted
        and ((f.requester = a and f.addressee = b) or (f.requester = b and f.addressee = a)));
$$;

create function public.social_new_code() returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
    alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- 헷갈리는 I·O·0·1 제외, 32자
    bytes bytea;
    code text;
begin
    loop
        bytes := uuid_send(gen_random_uuid());
        code := '';
        for i in 0..7 loop
            code := code || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1);
        end loop;
        exit when not exists (select 1 from public.social_profiles where friend_code = code);
    end loop;
    return code;
end;
$$;

-- 닉네임 설정(처음이면 친구 코드 생성). 공개 설정을 끄면 올린 기록을 즉시 지운다.
create function public.social_save_profile(p_nickname text, p_share boolean)
returns table(nickname text, friend_code text, share_records boolean)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare me uuid := public.social_caller();
begin
    if p_nickname is null or length(btrim(p_nickname)) not between 1 and 20 or p_share is null then
        raise invalid_parameter_value using message = 'Invalid profile';
    end if;
    insert into public.social_profiles as p (user_id, nickname, friend_code, share_records)
    values (me, btrim(p_nickname), public.social_new_code(), p_share)
    on conflict (user_id) do update set nickname = excluded.nickname, share_records = excluded.share_records;
    if not p_share then delete from public.social_records r where r.user_id = me; end if;
    return query select p.nickname, p.friend_code, p.share_records from public.social_profiles p where p.user_id = me;
end;
$$;

-- 친구 코드로 요청. 상대가 이미 나에게 요청했다면 바로 친구가 된다.
create function public.social_send_friend_request(p_code text) returns text
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := public.social_caller();
    target uuid;
begin
    if not exists (select 1 from public.social_profiles where user_id = me) then
        raise invalid_parameter_value using message = 'Profile required';
    end if;
    select user_id into target from public.social_profiles where friend_code = upper(btrim(coalesce(p_code, '')));
    if target is null then return 'not_found'; end if;
    if target = me then return 'self'; end if;
    if public.social_are_friends(me, target) then return 'already_friends'; end if;
    if exists (select 1 from public.social_friendships where requester = target and addressee = me) then
        update public.social_friendships set accepted = true where requester = target and addressee = me;
        return 'accepted';
    end if;
    if (select count(*) from public.social_friendships where requester = me and not accepted) >= 50 then
        raise invalid_parameter_value using message = 'Too many pending requests';
    end if;
    insert into public.social_friendships(requester, addressee) values (me, target) on conflict do nothing;
    return 'sent';
end;
$$;

-- 나에게 온 요청만 수락·거절할 수 있다.
create function public.social_respond_friend_request(p_requester uuid, p_accept boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
declare me uuid := public.social_caller();
begin
    if p_accept then
        update public.social_friendships set accepted = true
        where requester = p_requester and addressee = me and not accepted;
    else
        delete from public.social_friendships where requester = p_requester and addressee = me and not accepted;
    end if;
    return found;
end;
$$;

-- 친구 끊기 또는 보낸 요청 취소.
create function public.social_remove_friend(p_user uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare me uuid := public.social_caller();
begin
    delete from public.social_friendships
    where (requester = me and addressee = p_user) or (requester = p_user and addressee = me);
    return found;
end;
$$;

create function public.social_create_group(p_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := public.social_caller();
    created uuid;
begin
    if not exists (select 1 from public.social_profiles where user_id = me) then
        raise invalid_parameter_value using message = 'Profile required';
    end if;
    if p_name is null or length(btrim(p_name)) not between 1 and 30 then
        raise invalid_parameter_value using message = 'Invalid group name';
    end if;
    if (select count(*) from public.social_group_members where user_id = me) >= 20 then
        raise invalid_parameter_value using message = 'Too many groups';
    end if;
    insert into public.social_groups(name, owner) values (btrim(p_name), me) returning id into created;
    insert into public.social_group_members(group_id, user_id, joined, invited_by) values (created, me, true, me);
    return created;
end;
$$;

-- 그룹에 가입한 사람이 자기 친구만 초대할 수 있다.
create function public.social_invite_to_group(p_group uuid, p_user uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare me uuid := public.social_caller();
begin
    if not exists (select 1 from public.social_group_members where group_id = p_group and user_id = me and joined) then
        raise insufficient_privilege using message = 'Group member required';
    end if;
    if not public.social_are_friends(me, p_user) then
        raise insufficient_privilege using message = 'Only friends can be invited';
    end if;
    if (select count(*) from public.social_group_members where group_id = p_group) >= 50 then
        raise invalid_parameter_value using message = 'Group is full';
    end if;
    insert into public.social_group_members(group_id, user_id, joined, invited_by)
    values (p_group, p_user, false, me) on conflict do nothing;
    return found;
end;
$$;

create function public.social_respond_group_invite(p_group uuid, p_accept boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
declare me uuid := public.social_caller();
begin
    if p_accept then
        update public.social_group_members set joined = true where group_id = p_group and user_id = me and not joined;
    else
        delete from public.social_group_members where group_id = p_group and user_id = me and not joined;
    end if;
    return found;
end;
$$;

-- 나가기. 그룹장이 나가면 가장 먼저 가입한 다른 그룹원에게 넘기고, 아무도 없으면 그룹을 지운다.
create function public.social_leave_group(p_group uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := public.social_caller();
    successor uuid;
begin
    delete from public.social_group_members where group_id = p_group and user_id = me;
    if not found then return false; end if;
    if exists (select 1 from public.social_groups where id = p_group and owner = me) then
        select user_id into successor from public.social_group_members
        where group_id = p_group and joined order by created_at, user_id limit 1;
        if successor is null then
            delete from public.social_groups where id = p_group;
        else
            update public.social_groups set owner = successor where id = p_group;
        end if;
    end if;
    return true;
end;
$$;

-- 내 공통 종목 최고기록 전체를 올린다(없어진 종목은 지움). 공개를 끈 상태면 모두 지운다.
create function public.social_publish_records(p_records jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := public.social_caller();
    sharing boolean;
    item jsonb;
    definition public.record_catalog;
    kept text[] := '{}';
begin
    select share_records into sharing from public.social_profiles where user_id = me;
    if sharing is null then return 0; end if; -- 닉네임을 정하기 전에는 아무것도 공개하지 않는다
    if not sharing then
        delete from public.social_records where user_id = me;
        return 0;
    end if;
    if p_records is null or jsonb_typeof(p_records) <> 'array' or jsonb_array_length(p_records) > 200 then
        raise invalid_parameter_value using message = 'Invalid records';
    end if;
    for item in select * from jsonb_array_elements(p_records) loop
        select * into definition from public.record_catalog where id = item->>'type_id' and active;
        if not found or jsonb_typeof(item) <> 'object'
           or jsonb_typeof(item->'value') <> 'number' or (item->>'value')::double precision not between 0 and 100000
           or coalesce((item->>'extra_reps')::integer, 0) not between 0 and 10000
           or (definition.style = 'rounds' and coalesce((item->>'extra_reps')::integer, 0) >= definition."repsPerRound")
           or (item->>'achieved_at')::date > current_date + 1 then
            raise invalid_parameter_value using message = 'Invalid record';
        end if;
        insert into public.social_records(user_id, type_id, value, extra_reps, achieved_at, updated_at)
        values (me, definition.id, (item->>'value')::double precision, coalesce((item->>'extra_reps')::integer, 0),
                (item->>'achieved_at')::date, now())
        on conflict (user_id, type_id) do update set value = excluded.value, extra_reps = excluded.extra_reps,
            achieved_at = excluded.achieved_at, updated_at = now();
        kept := kept || definition.id;
    end loop;
    delete from public.social_records where user_id = me and not (type_id = any(kept));
    return coalesce(array_length(kept, 1), 0);
end;
$$;

-- 화면에 필요한 내 정보·친구·요청·그룹·초대를 한 번에 돌려준다.
create function public.social_overview() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare me uuid := public.social_caller();
begin
    return jsonb_build_object(
        'profile', (select jsonb_build_object('nickname', p.nickname, 'friend_code', p.friend_code,
                    'share_records', p.share_records) from public.social_profiles p where p.user_id = me),
        'friends', coalesce((select jsonb_agg(jsonb_build_object(
                    'user_id', other.user_id, 'nickname', other.nickname,
                    'status', case when f.accepted then 'friend' when f.requester = me then 'outgoing' else 'incoming' end)
                    order by other.nickname)
                from public.social_friendships f
                join public.social_profiles other
                  on other.user_id = case when f.requester = me then f.addressee else f.requester end
                where f.requester = me or f.addressee = me), '[]'::jsonb),
        'groups', coalesce((select jsonb_agg(jsonb_build_object(
                    'id', g.id, 'name', g.name, 'is_owner', g.owner = me, 'joined', mine.joined,
                    'members', (select coalesce(jsonb_agg(jsonb_build_object(
                                    'user_id', m.user_id, 'nickname', coalesce(p.nickname, '알 수 없음'), 'joined', m.joined)
                                    order by m.created_at), '[]'::jsonb)
                                from public.social_group_members m
                                left join public.social_profiles p on p.user_id = m.user_id
                                where m.group_id = g.id and (mine.joined or m.user_id = me or m.user_id = g.owner)))
                    order by g.created_at)
                from public.social_groups g
                join public.social_group_members mine on mine.group_id = g.id and mine.user_id = me), '[]'::jsonb)
    );
end;
$$;

-- 순위표 원자료. p_group이 없으면 나와 친구, 있으면 가입한 그룹원. 공개를 끈 사람은 기록이 없으므로 나오지 않는다.
create function public.social_leaderboard(p_group uuid default null)
returns table(user_id uuid, nickname text, is_me boolean, type_id text, value double precision,
              extra_reps integer, achieved_at date)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare me uuid := public.social_caller();
begin
    if p_group is not null and not exists (
        select 1 from public.social_group_members m where m.group_id = p_group and m.user_id = me and m.joined) then
        raise insufficient_privilege using message = 'Group member required';
    end if;
    return query
        select r.user_id, p.nickname, r.user_id = me, r.type_id, r.value, r.extra_reps, r.achieved_at
        from public.social_records r
        join public.social_profiles p on p.user_id = r.user_id and p.share_records
        join public.record_catalog c on c.id = r.type_id and c.active
        where case when p_group is null
            then r.user_id = me or public.social_are_friends(me, r.user_id)
            else exists (select 1 from public.social_group_members m
                         where m.group_id = p_group and m.user_id = r.user_id and m.joined) end;
end;
$$;

revoke all on function public.social_caller(), public.social_are_friends(uuid, uuid), public.social_new_code(),
    public.social_save_profile(text, boolean), public.social_send_friend_request(text),
    public.social_respond_friend_request(uuid, boolean), public.social_remove_friend(uuid),
    public.social_create_group(text), public.social_invite_to_group(uuid, uuid),
    public.social_respond_group_invite(uuid, boolean), public.social_leave_group(uuid),
    public.social_publish_records(jsonb), public.social_overview(), public.social_leaderboard(uuid)
    from public, anon, authenticated;
grant execute on function public.social_save_profile(text, boolean), public.social_send_friend_request(text),
    public.social_respond_friend_request(uuid, boolean), public.social_remove_friend(uuid),
    public.social_create_group(text), public.social_invite_to_group(uuid, uuid),
    public.social_respond_group_invite(uuid, boolean), public.social_leave_group(uuid),
    public.social_publish_records(jsonb), public.social_overview(), public.social_leaderboard(uuid)
    to authenticated;

commit;
