-- PG Management — manual UPI rent payments (roadmap Prompt 9).
-- Run once in the Supabase dashboard AFTER schema.sql, 002, 004, 006.
--
-- Live workspace model (app_data + members): owner_id is the workspace, tenant
-- ids are text. Security-critical transitions live in these dedicated tables so
-- RLS can enforce that a tenant can only ever create a pending_confirmation
-- submission and never flip a due to paid.

create table if not exists public.pg_upi_settings (
  owner_id   uuid not null references auth.users (id) on delete cascade,
  pg_id      text not null,
  upi_id     text not null default '',
  payee_name text not null default '',
  enabled    boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (owner_id, pg_id)
);

alter table public.pg_upi_settings enable row level security;

create policy "owner manages own upi" on public.pg_upi_settings
  for all to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

create policy "member reads workspace upi" on public.pg_upi_settings
  for select to authenticated
  using (exists (
    select 1 from public.members m
    where m.owner_id = pg_upi_settings.owner_id
      and m.member_email = lower((select auth.email()))
  ));

create table if not exists public.payment_submissions (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references auth.users (id) on delete cascade,
  customer_id     uuid,
  pg_id           text not null default '',
  tenant_id       text not null,
  member_email    text not null,
  payment_id      text not null,
  period          text not null default '',
  amount          integer not null,
  utr             text not null,
  screenshot_path text,
  status          text not null default 'pending_confirmation'
                  check (status in ('pending_confirmation', 'confirmed', 'rejected')),
  rejection_reason text,
  submitted_at    timestamptz not null default now(),
  confirmed_by    uuid,
  confirmed_at    timestamptz
);

create index if not exists payment_submissions_owner_idx on public.payment_submissions (owner_id);
create index if not exists payment_submissions_dup_idx on public.payment_submissions (owner_id, amount, utr);

alter table public.payment_submissions enable row level security;

-- Owner: full control over their workspace's submissions (confirm/reject).
create policy "owner manages submissions" on public.payment_submissions
  for all to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

-- Tenant (member): may create only their own pending submission…
create policy "member submits payment" on public.payment_submissions
  for insert to authenticated
  with check (
    status = 'pending_confirmation'
    and member_email = lower((select auth.email()))
    and exists (
      select 1 from public.members m
      where m.owner_id = payment_submissions.owner_id
        and m.member_email = lower((select auth.email()))
    )
  );

-- …and read only their own. No tenant UPDATE/DELETE policy exists, so a tenant
-- can never confirm a payment or edit one after submitting.
create policy "member reads own submissions" on public.payment_submissions
  for select to authenticated
  using (member_email = lower((select auth.email())));

-- Platform admin: read/audit only.
create policy "admin reads submissions" on public.payment_submissions
  for select to authenticated
  using (public.is_platform_admin());

-- ---------------------------------------------------------------------------
-- Tighten members write access: tenants may no longer write the payments blob,
-- so a tenant cannot mark a due paid via app_data. They keep tenant-facing
-- collections and go through payment_submissions for rent.
-- ---------------------------------------------------------------------------

drop policy if exists "member inserts tenant collections" on public.app_data;
create policy "member inserts tenant collections" on public.app_data
  for insert to authenticated
  with check (
    key in ('maintenance', 'visitors', 'attendance', 'notifications')
    and exists (
      select 1 from public.members m
      where m.owner_id = app_data.owner_id
        and m.member_email = lower((select auth.email()))
    )
  );

drop policy if exists "member updates tenant collections" on public.app_data;
create policy "member updates tenant collections" on public.app_data
  for update to authenticated
  using (
    key in ('maintenance', 'visitors', 'attendance', 'notifications')
    and exists (
      select 1 from public.members m
      where m.owner_id = app_data.owner_id
        and m.member_email = lower((select auth.email()))
    )
  )
  with check (
    key in ('maintenance', 'visitors', 'attendance', 'notifications')
    and exists (
      select 1 from public.members m
      where m.owner_id = app_data.owner_id
        and m.member_email = lower((select auth.email()))
    )
  );

-- ---------------------------------------------------------------------------
-- Storage: payment-proofs screenshots, workspace model.
-- Path: {owner_id}/{pg_id}/{tenant_id}/{payment_id}/{filename}
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('payment-proofs', 'payment-proofs', false)
on conflict (id) do nothing;

create or replace function public.can_access_workspace(ws text) returns boolean
language sql stable security definer set search_path = public, auth as
$$
  select (select auth.uid())::text = ws
    or exists (
      select 1 from public.members m
      where m.owner_id::text = ws
        and m.member_email = lower((select auth.email()))
    )
$$;

create policy "proofs workspace read" on storage.objects
  for select to authenticated
  using (bucket_id = 'payment-proofs'
    and public.can_access_workspace((storage.foldername(name))[1]));

create policy "proofs workspace insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'payment-proofs'
    and public.can_access_workspace((storage.foldername(name))[1]));
