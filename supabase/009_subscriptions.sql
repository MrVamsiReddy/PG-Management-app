-- PG Management — customer subscriptions (Improvements batch, task 6).
-- Run once in the Supabase dashboard AFTER 004. Idempotent.
--
-- Adds a subscription window to every customer. New customers default to the
-- free plan for 30 days; login is blocked once expires_at passes (enforced by
-- the app login gate and the schema-B RLS helpers below).

alter table public.customers
  add column if not exists starts_at  timestamptz not null default now();
alter table public.customers
  add column if not exists expires_at timestamptz;

-- Backfill existing rows: 30-day window from creation.
update public.customers
  set expires_at = created_at + interval '30 days'
  where expires_at is null;

-- Make the schema-B RLS helpers subscription-aware: an expired customer is
-- treated exactly like a disabled one (fails closed).
create or replace function public.my_owner_customer_id() returns uuid
language sql stable security definer set search_path = public as
$$
  select p.customer_id
  from profiles p
  join customers c on c.id = p.customer_id
  where p.id = auth.uid()
    and p.role = 'owner'
    and c.status = 'enabled'
    and (c.expires_at is null or c.expires_at > now())
$$;
