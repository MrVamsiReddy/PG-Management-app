-- PG Management — owner ↔ tenant linking (run AFTER schema.sql).
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.
--
-- An owner invites a tenant by email. When an account with that email signs
-- in, the app attaches it to the owner's workspace: the tenant reads the
-- owner's data and may write only the tenant-facing collections.

create table if not exists public.members (
  owner_id     uuid not null references auth.users (id) on delete cascade,
  member_email text not null,
  tenant_id    text not null, -- id of the Tenant record inside the owner's data
  created_at   timestamptz not null default now(),
  primary key (owner_id, member_email)
);

alter table public.members enable row level security;

create policy "owner manages own members" on public.members
  for all to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

create policy "member sees own membership" on public.members
  for select to authenticated
  using (member_email = lower((select auth.email())));

-- Members may read the whole workspace they belong to…
create policy "member reads workspace" on public.app_data
  for select to authenticated
  using (exists (
    select 1 from public.members m
    where m.owner_id = app_data.owner_id
      and m.member_email = lower((select auth.email()))
  ));

-- …but may write only tenant-facing collections (pay rent, raise issues,
-- visitors, attendance, notifications). Property/room/tenant/announcement/
-- utility data stays owner-only.
create policy "member inserts tenant collections" on public.app_data
  for insert to authenticated
  with check (
    key in ('payments', 'maintenance', 'visitors', 'attendance', 'notifications')
    and exists (
      select 1 from public.members m
      where m.owner_id = app_data.owner_id
        and m.member_email = lower((select auth.email()))
    )
  );

create policy "member updates tenant collections" on public.app_data
  for update to authenticated
  using (
    key in ('payments', 'maintenance', 'visitors', 'attendance', 'notifications')
    and exists (
      select 1 from public.members m
      where m.owner_id = app_data.owner_id
        and m.member_email = lower((select auth.email()))
    )
  )
  with check (
    key in ('payments', 'maintenance', 'visitors', 'attendance', 'notifications')
    and exists (
      select 1 from public.members m
      where m.owner_id = app_data.owner_id
        and m.member_email = lower((select auth.email()))
    )
  );
