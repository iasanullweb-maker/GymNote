-- Apply after 202610090001_social.sql. Integer repetitions and completed rounds only.
-- Existing private backups are preserved; invalid published rows are hidden, not rounded.
begin;

create or replace function public.social_publish_records(p_records jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := public.social_caller();
    sharing boolean;
    item jsonb;
    definition public.record_catalog;
    record_value numeric;
    record_extra numeric;
    kept text[] := '{}';
begin
    select share_records into sharing from public.social_profiles where user_id = me;
    if sharing is null then return 0; end if;
    if not sharing then
        delete from public.social_records where user_id = me;
        return 0;
    end if;
    if p_records is null or jsonb_typeof(p_records) <> 'array' or jsonb_array_length(p_records) > 200 then
        raise invalid_parameter_value using message = 'Invalid records';
    end if;
    for item in select * from jsonb_array_elements(p_records) loop
        if jsonb_typeof(item) <> 'object'
           or jsonb_typeof(item->'value') is distinct from 'number'
           or (item ? 'extra_reps' and jsonb_typeof(item->'extra_reps') is distinct from 'number') then
            raise invalid_parameter_value using message = 'Invalid record';
        end if;
        select * into definition from public.record_catalog where id = item->>'type_id' and active;
        if not found then raise invalid_parameter_value using message = 'Invalid record'; end if;
        record_value := (item->>'value')::numeric;
        record_extra := coalesce((item->>'extra_reps')::numeric, 0);
        if record_value not between 0 and 100000
           or record_extra not between 0 and 10000 or record_extra <> trunc(record_extra)
           or ((definition.style = 'rounds' or btrim(definition.unit) in ('회', ''))
               and record_value <> trunc(record_value))
           or (definition.style = 'rounds' and record_extra >= definition."repsPerRound")
           or (definition.style = 'count' and record_extra <> 0)
           or (item->>'achieved_at')::date > current_date + 1 then
            raise invalid_parameter_value using message = 'Invalid record';
        end if;
        insert into public.social_records(user_id, type_id, value, extra_reps, achieved_at, updated_at)
        values (me, definition.id, record_value::double precision, record_extra::integer,
                (item->>'achieved_at')::date, now())
        on conflict (user_id, type_id) do update set value = excluded.value, extra_reps = excluded.extra_reps,
            achieved_at = excluded.achieved_at, updated_at = now();
        kept := kept || definition.id;
    end loop;
    delete from public.social_records where user_id = me and not (type_id = any(kept));
    return coalesce(array_length(kept, 1), 0);
end;
$$;

create or replace function public.social_leaderboard(p_group uuid default null)
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
        where (case when p_group is null
            then r.user_id = me or public.social_are_friends(me, r.user_id)
            else exists (select 1 from public.social_group_members m
                         where m.group_id = p_group and m.user_id = r.user_id and m.joined) end)
          and ((c.style <> 'rounds' and btrim(c.unit) not in ('회', '')) or r.value = trunc(r.value))
          and (case when c.style = 'rounds' then r.extra_reps < c."repsPerRound" else r.extra_reps = 0 end);
end;
$$;

-- Keep the original RPC permission boundary explicit on upgrade.
revoke all on function public.social_publish_records(jsonb), public.social_leaderboard(uuid)
    from public, anon, authenticated;
grant execute on function public.social_publish_records(jsonb), public.social_leaderboard(uuid)
    to authenticated;

commit;
