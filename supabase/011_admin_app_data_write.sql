-- PG Management — platform-admin write access to app_data.
-- Run once in the Supabase dashboard AFTER 010. Re-runnable.
--
-- Admins can delete a customer's PG from the console; that edit rewrites the
-- owner's app_data blob, so admins need update on it (010 added read).

drop policy if exists "admin updates all app_data" on public.app_data;
create policy "admin updates all app_data" on public.app_data
  for update to authenticated
  using (public.is_platform_admin())
  with check (public.is_platform_admin());
