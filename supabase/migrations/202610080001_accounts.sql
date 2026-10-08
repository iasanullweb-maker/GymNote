begin;

create table public.workout_backups (
    user_id uuid primary key references auth.users(id) on delete cascade,
    version bigint not null check (version > 0),
    payload jsonb not null check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 2000000),
    updated_at timestamptz not null default now()
);
alter table public.workout_backups enable row level security;
revoke all on public.workout_backups from public, anon, authenticated;
grant select on public.workout_backups to authenticated;

-- Checking auth.sessions also rejects still-unexpired JWTs after server logout.
create function public.gymnote_session_valid() returns boolean
language sql stable security definer set search_path = '' as $$
    select exists (
        select 1 from auth.sessions s
        where s.id = nullif(auth.jwt()->>'session_id', '')::uuid
          and s.user_id = auth.uid()
    );
$$;
revoke all on function public.gymnote_session_valid() from public, anon;
grant execute on function public.gymnote_session_valid() to authenticated;

create policy own_workout on public.workout_backups for select to authenticated
using ((select auth.uid()) = user_id and (select public.gymnote_session_valid()));

create function public.load_workout()
returns table(version bigint, payload jsonb)
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null or not public.gymnote_session_valid() then
        raise insufficient_privilege using message = 'Authentication required';
    end if;
    return query select b.version, b.payload from public.workout_backups b where b.user_id = auth.uid();
end;
$$;

-- No client-supplied user ID. CAS prevents one device from silently overwriting another.
create function public.save_workout(p_payload jsonb, p_expected_version bigint)
returns table(version bigint, payload jsonb)
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null or not public.gymnote_session_valid() then
        raise insufficient_privilege using message = 'Authentication required';
    end if;
    if p_expected_version < 0 or p_expected_version is null
        or p_payload is null or jsonb_typeof(p_payload) <> 'object'
        or not (p_payload ?& array['week','recordTypes','records','logs','scheduledPlans','exerciseLibrary','defaultRest','restSound'])
        or octet_length(p_payload::text) > 2000000 then
        raise invalid_parameter_value using message = 'Invalid workout snapshot';
    end if;
    if p_expected_version = 0 then
        return query
            insert into public.workout_backups as b(user_id, version, payload)
            values (auth.uid(), 1, p_payload)
            on conflict (user_id) do nothing
            returning b.version, b.payload;
    else
        return query
            update public.workout_backups b
            set version = b.version + 1, payload = p_payload, updated_at = now()
            where b.user_id = auth.uid() and b.version = p_expected_version
            returning b.version, b.payload;
    end if;
end;
$$;
revoke all on function public.load_workout() from public, anon;
revoke all on function public.save_workout(jsonb, bigint) from public, anon;
grant execute on function public.load_workout() to authenticated;
grant execute on function public.save_workout(jsonb, bigint) to authenticated;

commit;
