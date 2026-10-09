-- Social withdrawal is separate from deleting the app account/private backup.
begin;

-- Profile foreign keys also prevent an in-flight request/publish from recreating
-- social data after withdrawal. Rejoining starts with fresh relationships.
alter table public.social_friendships add constraint social_requester_profile
    foreign key (requester) references public.social_profiles(user_id) on delete cascade;
alter table public.social_friendships add constraint social_addressee_profile
    foreign key (addressee) references public.social_profiles(user_id) on delete cascade;
alter table public.social_group_members add constraint social_member_profile
    foreign key (user_id) references public.social_profiles(user_id) on delete cascade;
alter table public.social_records add constraint social_record_profile
    foreign key (user_id) references public.social_profiles(user_id) on delete cascade;
alter table public.social_groups add constraint social_owner_profile
    foreign key (owner) references public.social_profiles(user_id) on delete cascade;

create or replace function public.social_leave_group(p_group uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := public.social_caller();
    successor uuid;
begin
    -- Serialize owner transfers, including two members leaving simultaneously.
    perform 1 from public.social_groups where id = p_group for update;
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

create function public.social_withdraw() returns boolean
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := public.social_caller();
    membership record;
begin
    -- Same order for every withdrawal to avoid conflicting group transfers.
    for membership in
        select g.id from public.social_groups g
        where exists (select 1 from public.social_group_members m
                      where m.group_id = g.id and m.user_id = me)
        order by g.id for update
    loop
        perform public.social_leave_group(membership.id);
    end loop;
    delete from public.social_profiles where user_id = me;
    return true;
end;
$$;

revoke all on function public.social_withdraw() from public, anon, authenticated;
grant execute on function public.social_withdraw() to authenticated;
commit;
