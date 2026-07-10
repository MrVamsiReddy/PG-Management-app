-- PG Management — tenant invite lifecycle (roadmap Prompt 7).
-- Run once in the Supabase dashboard AFTER schema.sql, 002_members.sql and
-- 004_saas_core.sql: SQL Editor → New query → paste → Run.
--
-- Invites for the live workspace model (app_data + members). Tenant record
-- ids inside app_data are strings, so this table intentionally has no FK to
-- the relational public.tenants table; customer_id is stamped when the
-- inviting owner has a resolved SaaS customer.
--
-- Lifecycle: pending → accepted | expired | revoked | resent.
--  * accepted — the tenant finished onboarding (set their own password).
--  * expired  — expires_at passed before acceptance.
--  * revoked  — the owner cancelled the invite; the temp password is
--               scrambled server-side so shared credentials stop working.
--  * resent   — superseded by a newer invite for the same tenant.
-- Tokens are single-use: only a 'pending' row can transition to 'accepted',
-- and the transition is guarded by `where status = 'pending'`.

create table if not exists public.invites (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users (id) on delete cascade,
  customer_id uuid,           -- resolved SaaS customer of the owner, if any
  user_id     uuid,           -- auth user created for the tenant (null when a
                              -- pre-existing account was linked instead)
  tenant_id   text not null,  -- Tenant record id inside the owner's app_data
  email       text not null,
  pg_id       text not null default '',
  room_id     text not null default '',
  bed_label   text not null default '',
  token       text not null unique default encode(gen_random_bytes(24), 'hex'),
  status      text not null default 'pending'
              check (status in ('pending', 'accepted', 'expired', 'revoked', 'resent')),
  expires_at  timestamptz not null default now() + interval '7 days',
  created_at  timestamptz not null default now(),
  accepted_at timestamptz,
  revoked_at  timestamptz,
  resent_at   timestamptz
);

create index if not exists invites_owner_idx on public.invites (owner_id);
create index if not exists invites_email_idx on public.invites (email);
create index if not exists invites_tenant_idx on public.invites (owner_id, tenant_id);

-- RLS: owners see their own invites (status/expiry in the app). All writes —
-- and all acceptance/validation — happen server-side in the `invite` Edge
-- Function with the service role, so tokens and lifecycle transitions can
-- never be forged from a client. Tenants cannot read invites at all (the
-- token is a secret delivered out-of-band).
alter table public.invites enable row level security;

create policy "owner reads own invites" on public.invites
  for select to authenticated
  using ((select auth.uid()) = owner_id);

-- The relational SaaS mirror gains the same lifecycle vocabulary.
alter table public.tenant_invites drop constraint if exists tenant_invites_status_check;
alter table public.tenant_invites add constraint tenant_invites_status_check
  check (status in ('pending', 'accepted', 'expired', 'revoked', 'resent'));

-- ---------------------------------------------------------------------------
-- must_change_password — backend enforcement.
-- A user still carrying a temporary password may sign in and read, but may
-- not write any business data until they set their own password. Restrictive
-- policies AND with the existing permissive ones. The claim clears (and the
-- app refreshes the session) as soon as the password is changed.
-- ---------------------------------------------------------------------------

create policy "temp password blocks inserts" on public.app_data
  as restrictive for insert to authenticated
  with check (
    (((select auth.jwt()) -> 'user_metadata' ->> 'must_change_password')::boolean is not true)
  );

create policy "temp password blocks updates" on public.app_data
  as restrictive for update to authenticated
  using (
    (((select auth.jwt()) -> 'user_metadata' ->> 'must_change_password')::boolean is not true)
  );

create policy "temp password blocks deletes" on public.app_data
  as restrictive for delete to authenticated
  using (
    (((select auth.jwt()) -> 'user_metadata' ->> 'must_change_password')::boolean is not true)
  );
