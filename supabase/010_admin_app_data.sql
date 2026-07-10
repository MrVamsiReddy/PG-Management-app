-- PG Management — platform-admin read access to app_data (bugfix).
-- Run once in the Supabase dashboard AFTER schema.sql + 004. Re-runnable.
--
-- Owner/tenant business data lives in the app_data blob keyed by owner_id.
-- Platform admins need to inspect a customer's data (e.g. "View PGs" in the
-- admin console), but the base policies only allow the owner and linked
-- members. This adds a read-only policy for platform admins.

drop policy if exists "admin reads all app_data" on public.app_data;
create policy "admin reads all app_data" on public.app_data
  for select to authenticated
  using (public.is_platform_admin());
