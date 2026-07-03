-- PG Management — cloud storage schema.
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.
--
-- Layout: one JSONB row per (user, collection), mirroring the app's local
-- store. Row-level security restricts every operation to the signed-in
-- user's own rows, so the publishable key shipped in the app grants no
-- access to anyone else's data.

create table if not exists public.app_data (
  owner_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  key        text not null,
  data       jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (owner_id, key)
);

alter table public.app_data enable row level security;

create policy "read own data" on public.app_data
  for select to authenticated
  using ((select auth.uid()) = owner_id);

create policy "insert own data" on public.app_data
  for insert to authenticated
  with check ((select auth.uid()) = owner_id);

create policy "update own data" on public.app_data
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

create policy "delete own data" on public.app_data
  for delete to authenticated
  using ((select auth.uid()) = owner_id);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

create trigger app_data_touch
  before update on public.app_data
  for each row execute function public.touch_updated_at();

-- For a fresh project, also run 002_members.sql (owner ↔ tenant linking).
