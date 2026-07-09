-- PG Management — 004_saas_core.sql
-- Multi-tenant SaaS core schema (roadmap Prompt 1).
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Run AFTER schema.sql, 002_members.sql and 003_push_tokens.sql.
--
-- This creates the NEW relational, customer-scoped schema ALONGSIDE the
-- legacy app_data/members tables that the current app still reads. Nothing
-- here is destructive; later roadmap steps move the app onto these tables.
--
-- Model: one customer (PG business) → many pgs → floors → rooms → beds.
-- A tenant is assigned to one bed. Rent comes from rent_rules by sharing
-- type (with optional room override) and is SNAPSHOTTED onto payment_dues
-- at creation, so changing rent never rewrites history. Manual UPI payments
-- are submitted by tenants (payment_submissions + proof files) and can only
-- be confirmed by the owner side. New customers start EMPTY — this schema
-- has no seed data.
--
-- Access rules enforced by RLS below:
--   * Platform admin (profiles.platform_admin) … everything.
--   * Owner … only rows with their own customer_id, and only while the
--     customer is enabled.
--   * Tenant … only their own tenant-scoped rows, and only while the
--     customer is enabled (plus reading their own customer/pg basics).
--   * Disabled customer … owners and tenants lose all business-data access
--     (they can still read the customers row itself so the client can show
--     "account disabled").

-- ---------------------------------------------------------------------------
-- 1. Core identity: customers and profiles
-- ---------------------------------------------------------------------------

create table if not exists public.customers (
  id             uuid primary key default gen_random_uuid(),
  business_name  text not null,
  owner_name     text not null default '',
  owner_email    text not null default '',
  phone          text not null default '',
  status         text not null default 'enabled' check (status in ('enabled', 'disabled')),
  plan           text not null default 'free',
  created_at     timestamptz not null default now(),
  disabled_at    timestamptz
);

create table if not exists public.profiles (
  id             uuid primary key references auth.users (id) on delete cascade,
  customer_id    uuid references public.customers (id) on delete cascade,
  role           text not null default 'owner' check (role in ('admin', 'owner', 'tenant')),
  platform_admin boolean not null default false,
  full_name      text not null default '',
  phone          text not null default '',
  created_at     timestamptz not null default now()
);
create index if not exists profiles_customer_idx on public.profiles (customer_id);

-- ---------------------------------------------------------------------------
-- 2. Helper functions (security definer: they bypass RLS to avoid recursion)
-- ---------------------------------------------------------------------------

create or replace function public.is_platform_admin() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from profiles where id = auth.uid() and platform_admin) $$;

-- The caller's customer id, but only when they are an owner of an ENABLED
-- customer. Returns null otherwise, which makes every comparison fail closed.
create or replace function public.my_owner_customer_id() returns uuid
language sql stable security definer set search_path = public as
$$
  select p.customer_id from profiles p
  join customers c on c.id = p.customer_id
  where p.id = auth.uid() and p.role = 'owner' and c.status = 'enabled'
$$;

-- Tenant rows belonging to the caller, active and under an enabled customer.
create or replace function public.my_tenant_ids() returns setof uuid
language sql stable security definer set search_path = public as
$$
  select t.id from tenants t
  join customers c on c.id = t.customer_id
  where t.user_id = auth.uid() and t.active and c.status = 'enabled'
$$;

create or replace function public.my_tenant_pg_ids() returns setof uuid
language sql stable security definer set search_path = public as
$$
  select t.pg_id from tenants t
  join customers c on c.id = t.customer_id
  where t.user_id = auth.uid() and t.active and c.status = 'enabled'
$$;

create or replace function public.my_tenant_room_ids() returns setof uuid
language sql stable security definer set search_path = public as
$$
  select t.room_id from tenants t
  join customers c on c.id = t.customer_id
  where t.user_id = auth.uid() and t.active and t.room_id is not null and c.status = 'enabled'
$$;

-- Enabled customers the caller belongs to in any role (profile or tenancy).
create or replace function public.my_member_customer_ids() returns setof uuid
language sql stable security definer set search_path = public as
$$
  select c.id from customers c
  where c.status = 'enabled' and (
    c.id in (select customer_id from profiles where id = auth.uid())
    or c.id in (select customer_id from tenants where user_id = auth.uid() and active))
$$;

grant execute on function
  public.is_platform_admin(),
  public.my_owner_customer_id(),
  public.my_tenant_ids(),
  public.my_tenant_pg_ids(),
  public.my_tenant_room_ids(),
  public.my_member_customer_ids()
to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Property structure: pgs → floors → rooms → beds
-- ---------------------------------------------------------------------------

create table if not exists public.pgs (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  name        text not null,
  address     text not null default '',
  amenities   text not null default '',
  photo_path  text,
  created_at  timestamptz not null default now()
);
create index if not exists pgs_customer_idx on public.pgs (customer_id);

create table if not exists public.floors (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  pg_id       uuid not null references public.pgs (id) on delete cascade,
  number      int not null,
  name        text not null default '',
  unique (pg_id, number)
);
create index if not exists floors_customer_idx on public.floors (customer_id);

create table if not exists public.rooms (
  id            uuid primary key default gen_random_uuid(),
  customer_id   uuid not null references public.customers (id) on delete cascade,
  pg_id         uuid not null references public.pgs (id) on delete cascade,
  floor_id      uuid not null references public.floors (id) on delete cascade,
  number        text not null,
  sharing_type  int not null default 2 check (sharing_type between 1 and 6),
  rent_override int check (rent_override >= 0), -- null: use rent_rules for the sharing type
  created_at    timestamptz not null default now(),
  unique (pg_id, number)
);
create index if not exists rooms_customer_idx on public.rooms (customer_id);

create table if not exists public.beds (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  pg_id       uuid not null references public.pgs (id) on delete cascade,
  room_id     uuid not null references public.rooms (id) on delete cascade,
  label       text not null,
  status      text not null default 'vacant' check (status in ('vacant', 'occupied')),
  unique (room_id, label)
);
create index if not exists beds_customer_idx on public.beds (customer_id);

-- ---------------------------------------------------------------------------
-- 4. Tenants and invites
-- ---------------------------------------------------------------------------

create table if not exists public.tenants (
  id           uuid primary key default gen_random_uuid(),
  customer_id  uuid not null references public.customers (id) on delete cascade,
  pg_id        uuid not null references public.pgs (id) on delete cascade,
  room_id      uuid references public.rooms (id) on delete set null,
  bed_id       uuid references public.beds (id) on delete set null,
  user_id      uuid references auth.users (id) on delete set null, -- set once invited/accepted
  name         text not null,
  phone        text not null default '',
  email        text not null default '',
  kyc_status   text not null default 'pending' check (kyc_status in ('pending', 'verified')),
  kyc_doc_path text,
  join_date    date not null default current_date,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);
create index if not exists tenants_customer_idx on public.tenants (customer_id);
create index if not exists tenants_user_idx on public.tenants (user_id);

create table if not exists public.tenant_invites (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  tenant_id   uuid not null references public.tenants (id) on delete cascade,
  email       text not null,
  token       text not null unique default encode(gen_random_bytes(24), 'hex'),
  status      text not null default 'pending' check (status in ('pending', 'accepted', 'expired', 'revoked')),
  expires_at  timestamptz not null default now() + interval '7 days',
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  accepted_at timestamptz,
  revoked_at  timestamptz
);
create index if not exists tenant_invites_customer_idx on public.tenant_invites (customer_id);

-- ---------------------------------------------------------------------------
-- 5. Money: rent rules, payment settings, dues, payments, submissions, proofs
-- ---------------------------------------------------------------------------

-- Rent history: never UPDATE a rule — INSERT a new row with a later
-- effective_from. The current rent for a sharing type is the newest rule
-- whose effective_from <= today.
create table if not exists public.rent_rules (
  id             uuid primary key default gen_random_uuid(),
  customer_id    uuid not null references public.customers (id) on delete cascade,
  pg_id          uuid not null references public.pgs (id) on delete cascade,
  sharing_type   int not null check (sharing_type between 1 and 6),
  amount         int not null check (amount >= 0),
  effective_from date not null default current_date,
  created_at     timestamptz not null default now()
);
create index if not exists rent_rules_customer_idx on public.rent_rules (customer_id);

create table if not exists public.pg_payment_settings (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  pg_id       uuid not null unique references public.pgs (id) on delete cascade,
  upi_id      text not null default '',
  payee_name  text not null default '',
  upi_enabled boolean not null default false,
  updated_at  timestamptz not null default now()
);
create index if not exists pg_payment_settings_customer_idx on public.pg_payment_settings (customer_id);

-- amount is a RENT SNAPSHOT copied from rent_rules/room override at creation;
-- it must never be recomputed from current rules.
create table if not exists public.payment_dues (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  pg_id       uuid not null references public.pgs (id) on delete cascade,
  tenant_id   uuid not null references public.tenants (id) on delete cascade,
  period      date not null, -- first day of the rent month
  amount      int not null check (amount >= 0),
  paid_amount int not null default 0 check (paid_amount >= 0),
  status      text not null default 'due'
              check (status in ('due', 'partial', 'pending_confirmation', 'paid')),
  due_date    date,
  paid_at     timestamptz,
  method      text,
  created_at  timestamptz not null default now(),
  unique (tenant_id, period) -- duplicate current-month dues are impossible
);
create index if not exists payment_dues_customer_idx on public.payment_dues (customer_id);

-- Actual money received (owner-recorded or confirmed UPI submissions).
create table if not exists public.payments (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  pg_id       uuid not null references public.pgs (id) on delete cascade,
  tenant_id   uuid not null references public.tenants (id) on delete cascade,
  due_id      uuid references public.payment_dues (id) on delete set null,
  amount      int not null check (amount > 0),
  method      text not null default '',
  reference   text not null default '', -- UTR or receipt reference
  paid_at     timestamptz not null default now(),
  recorded_by uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists payments_customer_idx on public.payments (customer_id);

create table if not exists public.payment_submissions (
  id               uuid primary key default gen_random_uuid(),
  customer_id      uuid not null references public.customers (id) on delete cascade,
  pg_id            uuid not null references public.pgs (id) on delete cascade,
  tenant_id        uuid not null references public.tenants (id) on delete cascade,
  due_id           uuid not null references public.payment_dues (id) on delete cascade,
  amount           int not null check (amount > 0),
  utr              text not null,
  note             text not null default '',
  status           text not null default 'pending_confirmation'
                   check (status in ('pending_confirmation', 'confirmed', 'rejected')),
  rejection_reason text,
  submitted_at     timestamptz not null default now(),
  confirmed_by     uuid references auth.users (id) on delete set null,
  confirmed_at     timestamptz
);
create index if not exists payment_submissions_customer_idx on public.payment_submissions (customer_id);
-- Supports the duplicate-UTR warning.
create index if not exists payment_submissions_utr_idx on public.payment_submissions (customer_id, utr, amount);

create table if not exists public.payment_proof_files (
  id            uuid primary key default gen_random_uuid(),
  customer_id   uuid not null references public.customers (id) on delete cascade,
  submission_id uuid not null references public.payment_submissions (id) on delete cascade,
  storage_path  text not null, -- payment-proofs/{customer_id}/{pg_id}/{tenant_id}/{due_id}/{file}
  uploaded_at   timestamptz not null default now()
);
create index if not exists payment_proof_files_customer_idx on public.payment_proof_files (customer_id);

-- ---------------------------------------------------------------------------
-- 6. Operations: complaints, notices, visitors
-- ---------------------------------------------------------------------------

create table if not exists public.complaints (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  pg_id       uuid not null references public.pgs (id) on delete cascade,
  room_id     uuid references public.rooms (id) on delete set null,
  tenant_id   uuid references public.tenants (id) on delete set null,
  title       text not null,
  category    text not null default 'Other',
  priority    text not null default 'medium' check (priority in ('low', 'medium', 'high')),
  status      text not null default 'open' check (status in ('open', 'in_progress', 'resolved')),
  assignee    text,
  photo_path  text,
  created_at  timestamptz not null default now()
);
create index if not exists complaints_customer_idx on public.complaints (customer_id);

create table if not exists public.notices (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  pg_id       uuid references public.pgs (id) on delete cascade, -- null: all the customer's PGs
  title       text not null,
  body        text not null default '',
  author_id   uuid references auth.users (id) on delete set null,
  send_push   boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists notices_customer_idx on public.notices (customer_id);

create table if not exists public.visitors (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  pg_id       uuid not null references public.pgs (id) on delete cascade,
  tenant_id   uuid not null references public.tenants (id) on delete cascade,
  name        text not null,
  purpose     text not null default '',
  status      text not null default 'awaiting_approval'
              check (status in ('awaiting_approval', 'inside', 'checked_out', 'declined')),
  expected_at timestamptz not null default now()
);
create index if not exists visitors_customer_idx on public.visitors (customer_id);

-- ---------------------------------------------------------------------------
-- 7. Audit logs (customer_id null = platform-level action)
-- ---------------------------------------------------------------------------

create table if not exists public.audit_logs (
  id            bigint generated always as identity primary key,
  customer_id   uuid references public.customers (id) on delete set null,
  actor_user_id uuid,
  actor_role    text,
  action        text not null,
  entity_type   text,
  entity_id     text,
  before_json   jsonb,
  after_json    jsonb,
  ip            text,
  user_agent    text,
  created_at    timestamptz not null default now()
);
create index if not exists audit_logs_customer_idx on public.audit_logs (customer_id);

-- ---------------------------------------------------------------------------
-- 8. Row level security
-- ---------------------------------------------------------------------------

-- customers: admin everything; members may READ their own customer row even
-- when disabled (so clients can show "account disabled"). No client writes.
alter table public.customers enable row level security;
create policy customers_admin on public.customers for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy customers_member_read on public.customers for select to authenticated
  using (
    id in (select customer_id from public.profiles where id = auth.uid())
    or id in (select customer_id from public.tenants where user_id = auth.uid())
  );

-- profiles: admin everything; users read/update their own; owners read the
-- profiles of their own (enabled) customer. Creation happens server-side.
alter table public.profiles enable row level security;
create policy profiles_admin on public.profiles for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy profiles_self_read on public.profiles for select to authenticated
  using (id = auth.uid());
create policy profiles_self_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_owner_read on public.profiles for select to authenticated
  using (customer_id is not null and customer_id = public.my_owner_customer_id());

-- pgs
alter table public.pgs enable row level security;
create policy pgs_admin on public.pgs for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy pgs_owner on public.pgs for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());
create policy pgs_tenant_read on public.pgs for select to authenticated
  using (id in (select public.my_tenant_pg_ids()));

-- floors (owner/admin only; tenants have no floor-level needs)
alter table public.floors enable row level security;
create policy floors_admin on public.floors for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy floors_owner on public.floors for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());

-- rooms: tenants read only their own room
alter table public.rooms enable row level security;
create policy rooms_admin on public.rooms for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy rooms_owner on public.rooms for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());
create policy rooms_tenant_read on public.rooms for select to authenticated
  using (id in (select public.my_tenant_room_ids()));

-- beds: tenants read the beds of their own room
alter table public.beds enable row level security;
create policy beds_admin on public.beds for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy beds_owner on public.beds for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());
create policy beds_tenant_read on public.beds for select to authenticated
  using (room_id in (select public.my_tenant_room_ids()));

-- tenants: tenants read only their own row
alter table public.tenants enable row level security;
create policy tenants_admin on public.tenants for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy tenants_owner on public.tenants for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());
create policy tenants_tenant_read on public.tenants for select to authenticated
  using (id in (select public.my_tenant_ids()));

-- tenant_invites: owner/admin only (acceptance is handled server-side)
alter table public.tenant_invites enable row level security;
create policy tenant_invites_admin on public.tenant_invites for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy tenant_invites_owner on public.tenant_invites for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());

-- rent_rules: owner/admin only
alter table public.rent_rules enable row level security;
create policy rent_rules_admin on public.rent_rules for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy rent_rules_owner on public.rent_rules for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());

-- pg_payment_settings: tenants may read their PG's UPI details to pay
alter table public.pg_payment_settings enable row level security;
create policy pg_payment_settings_admin on public.pg_payment_settings for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy pg_payment_settings_owner on public.pg_payment_settings for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());
create policy pg_payment_settings_tenant_read on public.pg_payment_settings for select to authenticated
  using (pg_id in (select public.my_tenant_pg_ids()));

-- payment_dues: tenants can only READ their own — a tenant can never mark
-- anything paid; owner-side writes only.
alter table public.payment_dues enable row level security;
create policy payment_dues_admin on public.payment_dues for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy payment_dues_owner on public.payment_dues for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());
create policy payment_dues_tenant_read on public.payment_dues for select to authenticated
  using (tenant_id in (select public.my_tenant_ids()));

-- payments: tenants read their own money records; owner-side writes only
alter table public.payments enable row level security;
create policy payments_admin on public.payments for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy payments_owner on public.payments for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());
create policy payments_tenant_read on public.payments for select to authenticated
  using (tenant_id in (select public.my_tenant_ids()));

-- payment_submissions: tenants submit proof (insert, pending only) and read
-- their own; confirming/rejecting is an owner-side update.
alter table public.payment_submissions enable row level security;
create policy payment_submissions_admin on public.payment_submissions for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy payment_submissions_owner on public.payment_submissions for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());
create policy payment_submissions_tenant_read on public.payment_submissions for select to authenticated
  using (tenant_id in (select public.my_tenant_ids()));
create policy payment_submissions_tenant_insert on public.payment_submissions for insert to authenticated
  with check (
    tenant_id in (select public.my_tenant_ids())
    and status = 'pending_confirmation'
    and confirmed_by is null and confirmed_at is null
  );

-- payment_proof_files: tenant may attach to and read their own submissions
alter table public.payment_proof_files enable row level security;
create policy payment_proof_files_admin on public.payment_proof_files for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy payment_proof_files_owner on public.payment_proof_files for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());
create policy payment_proof_files_tenant_read on public.payment_proof_files for select to authenticated
  using (exists (
    select 1 from public.payment_submissions s
    where s.id = submission_id and s.tenant_id in (select public.my_tenant_ids())
  ));
create policy payment_proof_files_tenant_insert on public.payment_proof_files for insert to authenticated
  with check (exists (
    select 1 from public.payment_submissions s
    where s.id = submission_id and s.tenant_id in (select public.my_tenant_ids())
  ));

-- complaints: tenants read their own and may raise new open ones
alter table public.complaints enable row level security;
create policy complaints_admin on public.complaints for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy complaints_owner on public.complaints for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());
create policy complaints_tenant_read on public.complaints for select to authenticated
  using (tenant_id in (select public.my_tenant_ids()));
create policy complaints_tenant_insert on public.complaints for insert to authenticated
  with check (tenant_id in (select public.my_tenant_ids()) and status = 'open');

-- notices: tenants read customer-wide (pg_id null) or their own PG's notices
alter table public.notices enable row level security;
create policy notices_admin on public.notices for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy notices_owner on public.notices for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());
create policy notices_tenant_read on public.notices for select to authenticated
  using (
    customer_id in (select public.my_member_customer_ids())
    and (pg_id is null or pg_id in (select public.my_tenant_pg_ids()))
  );

-- visitors: tenants manage only their own visitors (approval stays owner-side)
alter table public.visitors enable row level security;
create policy visitors_admin on public.visitors for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy visitors_owner on public.visitors for all to authenticated
  using (customer_id = public.my_owner_customer_id())
  with check (customer_id = public.my_owner_customer_id());
create policy visitors_tenant_read on public.visitors for select to authenticated
  using (tenant_id in (select public.my_tenant_ids()));
create policy visitors_tenant_insert on public.visitors for insert to authenticated
  with check (tenant_id in (select public.my_tenant_ids()) and status = 'awaiting_approval');

-- audit_logs: admin everything; owners read + append logs for their customer;
-- tenants nothing. No client updates/deletes — logs are append-only.
alter table public.audit_logs enable row level security;
create policy audit_logs_admin_read on public.audit_logs for select to authenticated
  using (public.is_platform_admin());
create policy audit_logs_admin_insert on public.audit_logs for insert to authenticated
  with check (public.is_platform_admin());
create policy audit_logs_owner_read on public.audit_logs for select to authenticated
  using (customer_id is not null and customer_id = public.my_owner_customer_id());
create policy audit_logs_owner_insert on public.audit_logs for insert to authenticated
  with check (
    customer_id is not null
    and customer_id = public.my_owner_customer_id()
    and actor_user_id = auth.uid()
  );

-- ---------------------------------------------------------------------------
-- 9. Storage: payment proof screenshots
--    Path convention: {customer_id}/{pg_id}/{tenant_id}/{due_id}/{filename}
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('payment-proofs', 'payment-proofs', false)
on conflict (id) do nothing;

create policy pp_admin_all on storage.objects for all to authenticated
  using (bucket_id = 'payment-proofs' and public.is_platform_admin())
  with check (bucket_id = 'payment-proofs' and public.is_platform_admin());

create policy pp_owner_all on storage.objects for all to authenticated
  using (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = public.my_owner_customer_id()::text
  )
  with check (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = public.my_owner_customer_id()::text
  );

create policy pp_tenant_read on storage.objects for select to authenticated
  using (
    bucket_id = 'payment-proofs'
    and exists (
      select 1 from public.tenants t
      join public.customers c on c.id = t.customer_id
      where t.user_id = auth.uid() and t.active and c.status = 'enabled'
        and t.customer_id::text = (storage.foldername(name))[1]
        and t.id::text = (storage.foldername(name))[3]
    )
  );

create policy pp_tenant_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'payment-proofs'
    and exists (
      select 1 from public.tenants t
      join public.customers c on c.id = t.customer_id
      where t.user_id = auth.uid() and t.active and c.status = 'enabled'
        and t.customer_id::text = (storage.foldername(name))[1]
        and t.id::text = (storage.foldername(name))[3]
    )
  );

-- ---------------------------------------------------------------------------
-- 10. Manual verification (run with two test users to prove isolation)
-- ---------------------------------------------------------------------------
-- 1. As service role, create customers A and B, an owner profile for each
--    (profiles.role='owner', customer_id set), and one pg per customer.
-- 2. Sign in as owner A (client/API):   select * from pgs;
--    → only customer A's pgs. Inserting a pg with customer_id = B must fail.
-- 3. Sign in as owner B: symmetric.
-- 4. Create tenants under A with user_id of a test tenant user; as that
--    tenant: select * from payment_dues; → only own rows.
--    update payment_dues set status='paid' … → 0 rows (no write policy).
-- 5. update customers set status='disabled' where id = A (service role);
--    owner A and tenant A now read 0 business rows everywhere.
