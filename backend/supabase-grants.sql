-- ============================================================
-- Chrono – table permissions for the Supabase Data API
-- Newer Supabase projects don't grant API roles access to tables
-- created in the SQL Editor. Run this once after supabase-schema.sql.
-- ============================================================

grant usage on schema public to anon, authenticated, service_role;

-- Backend (secret / service_role key): full access, RLS bypassed
grant all on table preferences, courses, blocks, deadlines, chat_messages to service_role;

-- Signed-in users (RLS policies still limit them to their own rows)
grant select, insert, update, delete on table preferences, courses, blocks, deadlines, chat_messages to authenticated;

-- Make the API pick up the change right away
notify pgrst, 'reload schema';
