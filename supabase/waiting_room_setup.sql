-- Run once in Supabase SQL Editor for the waiting_room_app project.
-- The app uses the existing public.clients table shown in the dashboard.

create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  email text not null default '',
  role text not null default 'user' check (role in ('user', 'admin')),
  status text not null default 'pending' check (status in ('pending', 'approved')),
  created_at timestamptz not null default now()
);

alter table public.clients
  add column if not exists user_id uuid references auth.users(id) on delete set null;

create index if not exists clients_created_at_id_idx
  on public.clients (created_at asc, id asc);
create index if not exists user_profiles_status_idx
  on public.user_profiles (status, created_at);

-- Enable live queue updates when Supabase Realtime's publication is available.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'clients'
     ) then
    alter publication supabase_realtime add table public.clients;
  end if;
end;
$$;

create or replace function public.is_waiting_room_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_profiles
    where id = (select auth.uid()) and role = 'admin' and status = 'approved'
  );
$$;

create or replace function public.handle_new_waiting_room_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profiles (id, display_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', ''),
    coalesce(new.email, '')
  )
  on conflict (id) do update
    set email = excluded.email,
        display_name = case when public.user_profiles.display_name = ''
          then excluded.display_name else public.user_profiles.display_name end;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_waiting_room on auth.users;
create trigger on_auth_user_created_waiting_room
  after insert on auth.users
  for each row execute procedure public.handle_new_waiting_room_user();

-- Backfill accounts that already existed before the profile trigger was installed.
insert into public.user_profiles (id, display_name, email)
select id, coalesce(raw_user_meta_data ->> 'display_name', ''), coalesce(email, '')
from auth.users
on conflict (id) do nothing;

alter table public.user_profiles enable row level security;
alter table public.clients enable row level security;

-- The existing clients table may have permissive policies from its earlier setup.
-- Policies combine with OR, so remove all of them before applying the role rules below.
do $$
declare old_policy record;
begin
  for old_policy in
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'clients'
  loop
    execute format('drop policy %I on public.clients', old_policy.policyname);
  end loop;
end;
$$;

revoke all on public.clients from public, anon, authenticated;

drop policy if exists "profiles_read_self_or_admin" on public.user_profiles;
create policy "profiles_read_self_or_admin" on public.user_profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.is_waiting_room_admin());

drop policy if exists "profiles_admin_update" on public.user_profiles;
create policy "profiles_admin_update" on public.user_profiles
  for update to authenticated
  using (public.is_waiting_room_admin())
  with check (public.is_waiting_room_admin());

drop policy if exists "clients_read_approved_users" on public.clients;
create policy "clients_read_approved_users" on public.clients
  for select to authenticated
  using (
    exists (
      select 1 from public.user_profiles p
      where p.id = (select auth.uid()) and p.status = 'approved'
    )
  );

drop policy if exists "clients_insert_own_approved" on public.clients;
create policy "clients_insert_own_approved" on public.clients
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.user_profiles p
      where p.id = (select auth.uid()) and p.status = 'approved'
    )
  );

drop policy if exists "clients_admin_delete" on public.clients;
create policy "clients_admin_delete" on public.clients
  for delete to authenticated
  using (public.is_waiting_room_admin());

-- Authenticated registration always associates the queue entry with the caller.
create or replace function public.register_queue_client_secure(
  p_id uuid,
  p_name text,
  p_lat double precision,
  p_lng double precision,
  p_accuracy double precision,
  p_created_at timestamptz
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  insert into public.clients (id, name, lat, lng, location_accuracy_m, created_at, user_id)
  values (p_id, p_name, p_lat, p_lng, p_accuracy, p_created_at, auth.uid())
  on conflict (id) do nothing;
end;
$$;

revoke all on function public.register_queue_client_secure(uuid, text, double precision, double precision, double precision, timestamptz) from public, anon;
grant execute on function public.register_queue_client_secure(uuid, text, double precision, double precision, double precision, timestamptz) to authenticated;

-- Revoke older RPCs with the same purpose so they cannot bypass the new RLS rules.
do $$
declare old_rpc record;
begin
  for old_rpc in
    select p.oid::regprocedure as signature
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'register_queue_client'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', old_rpc.signature);
  end loop;
end;
$$;

create or replace function public.call_next_queue_client()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare next_id uuid;
begin
  if not public.is_waiting_room_admin() then
    raise exception 'Administrator role required';
  end if;

  delete from public.clients
  where id = (
    select id from public.clients order by created_at asc, id asc limit 1 for update
  )
  returning id into next_id;
  return next_id;
end;
$$;

revoke all on function public.call_next_queue_client() from public, anon;
grant execute on function public.call_next_queue_client() to authenticated;

grant select on public.user_profiles to authenticated;
grant update (status) on public.user_profiles to authenticated;
grant select, insert, delete on public.clients to authenticated;

-- Promote the intended administrator after applying this file:
-- update public.user_profiles
-- set role = 'admin', status = 'approved'
-- where email = 'YOUR_ADMIN_EMAIL';
