-- PG Management — live sync (Realtime) for workspace data.
-- Run once in the Supabase dashboard. Re-runnable.
--
-- The apps subscribe to postgres_changes on these tables so a write by the
-- owner or a tenant shows up on every device within a second — no restart.
-- Realtime respects RLS, so subscribers only receive rows they can select.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'app_data'
  ) then
    alter publication supabase_realtime add table public.app_data;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'upi_submissions'
  ) then
    alter publication supabase_realtime add table public.upi_submissions;
  end if;
end $$;
