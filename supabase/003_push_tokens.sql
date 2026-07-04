-- PG Management — device tokens for push notifications (run AFTER 002_members.sql).
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.
--
-- Each signed-in device stores its FCM token here; the `push` Edge Function
-- reads them (with the service role) to deliver notifications.

create table if not exists public.push_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  email      text not null,
  updated_at timestamptz not null default now()
);

alter table public.push_tokens enable row level security;

create policy "own tokens" on public.push_tokens
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
