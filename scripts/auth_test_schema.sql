-- Minimal Supabase Auth contract for isolated PostgreSQL regression tests. NOT a production migration.
create role anon nologin;
create role authenticated nologin;
-- Supabase's server-side role (Edge Functions with the service key). Bypasses RLS like production.
create role service_role nologin bypassrls;
create schema auth;
create table auth.users (id uuid primary key);
create table auth.sessions (id uuid primary key, user_id uuid references auth.users(id) on delete cascade);
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
$$;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(auth.jwt()->>'sub', '')::uuid;
$$;
grant usage on schema public, auth to anon, authenticated;
grant usage on schema public to service_role;
grant execute on function auth.jwt(), auth.uid() to anon, authenticated;
