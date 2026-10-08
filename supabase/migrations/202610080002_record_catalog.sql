begin;

-- Grant administrators only through trusted SQL, never through profile/user_metadata.
create table public.record_catalog_admins (
    user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.record_catalog_admins enable row level security;
revoke all on public.record_catalog_admins from public, anon, authenticated;

create table public.record_catalog (
    id text primary key check (id ~ '^common-[a-z0-9-]{1,100}$'),
    name text not null check (length(btrim(name)) between 1 and 80),
    unit text not null check (length(unit) <= 20),
    style text not null check (style in ('count', 'rounds')),
    "repsPerRound" integer not null check ("repsPerRound" between 1 and 500),
    "lowerIsBetter" boolean not null,
    hint text not null check (length(hint) <= 1000),
    active boolean not null,
    position integer not null check (position between 0 and 9999),
    revision bigint not null check (revision > 0)
);
alter table public.record_catalog enable row level security;
revoke all on public.record_catalog from public, anon, authenticated;

insert into public.record_catalog values
('common-pushup-v1', '푸쉬업', '회', 'count', 30, false, '한 세트 최대 반복 횟수', true, 0, 1),
('common-pullup-v1', '풀업', '회', 'count', 30, false, '한 세트 최대 반복 횟수', true, 1, 1),
('common-cindy-v1', '신디', '', 'rounds', 30, false, '20분 AMRAP (풀업 5 · 푸쉬업 10 · 에어 스쿼트 15). 완료한 라운드와 추가 횟수를 적어.', true, 2, 1);

create function public.list_record_catalog() returns setof public.record_catalog
language sql stable security definer set search_path = '' as $$
    select * from public.record_catalog order by position, id;
$$;
revoke all on function public.list_record_catalog() from public;
-- Definitions contain no private data; guests need the same catalog as signed-in users.
grant execute on function public.list_record_catalog() to anon, authenticated;

create function public.is_record_catalog_admin() returns boolean
language sql stable security definer set search_path = '' as $$
    select public.gymnote_session_valid() and exists (
        select 1 from public.record_catalog_admins where user_id = auth.uid()
    );
$$;
revoke all on function public.is_record_catalog_admin() from public, anon;
grant execute on function public.is_record_catalog_admin() to authenticated;

create function public.save_record_catalog_type(p_type jsonb, p_expected_revision bigint)
returns setof public.record_catalog
language plpgsql security definer set search_path = '' as $$
declare
    incoming public.record_catalog;
    previous public.record_catalog;
begin
    if not public.is_record_catalog_admin() then
        raise insufficient_privilege using message = 'Administrator required';
    end if;
    if p_type is null or jsonb_typeof(p_type) <> 'object'
       or p_expected_revision is null or p_expected_revision < 0
       or not (p_type ?& array['id','name','unit','style','repsPerRound','lowerIsBetter','hint','active','position']) then
        raise invalid_parameter_value using message = 'Invalid catalog definition';
    end if;
    incoming := jsonb_populate_record(null::public.record_catalog, p_type);
    incoming.name := btrim(incoming.name);
    select * into previous from public.record_catalog where id = incoming.id for update;
    if found then
        if previous.revision <> p_expected_revision then return; end if;
        if (previous.unit, previous.style, previous."repsPerRound", previous."lowerIsBetter")
           is distinct from (incoming.unit, incoming.style, incoming."repsPerRound", incoming."lowerIsBetter") then
            raise invalid_parameter_value using message = 'Create a new definition for different scoring rules';
        end if;
        return query update public.record_catalog set name = incoming.name, hint = incoming.hint,
            active = incoming.active, position = incoming.position, revision = previous.revision + 1
            where id = incoming.id returning *;
    elsif p_expected_revision = 0 then
        return query insert into public.record_catalog values
            (incoming.id, incoming.name, incoming.unit, incoming.style, incoming."repsPerRound",
             incoming."lowerIsBetter", incoming.hint, incoming.active, incoming.position, 1)
            on conflict (id) do nothing returning *;
    end if;
end;
$$;
revoke all on function public.save_record_catalog_type(jsonb,bigint) from public, anon;
grant execute on function public.save_record_catalog_type(jsonb,bigint) to authenticated;

commit;
