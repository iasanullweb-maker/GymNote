-- Isolated regression DB only. Mirrors Supabase's default grants for objects created in public, so
-- later migrations must revoke app-role access explicitly (as they must in the live project).
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
