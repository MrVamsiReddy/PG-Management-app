-- PG Management — tenant self-registration, approved by the owner.
-- Run once in the Supabase dashboard AFTER schema.sql and 002–019.
-- Re-runnable.
--
-- A new tenant has no login yet, so they register from the tenant login
-- screen with the PG's registration code (the owner shares it as a link or
-- code). That only creates a REQUEST. No account exists and no email is
-- sent until the owner accepts: accepting runs the normal onboarding, which
-- creates the login and emails the temporary password (`invite` function).
-- Sign-ups stay off; strangers cannot create accounts.
--
-- 1. pg_join_codes     — one registration code per PG, managed by its owner.
-- 2. tenant_requests   — pending registrations; only the owner can read them.
-- 3. pg_for_join_code  — (anyone) which PG a code belongs to, name only.
-- 4. register_tenant   — (anyone) files a request and tells the owner.

-- ---------------------------------------------------------------------------
-- 1. Registration codes.
-- ---------------------------------------------------------------------------

create table if not exists public.pg_join_codes (
  owner_id   uuid not null references auth.users (id) on delete cascade,
  pg_id      text not null,
  pg_name    text not null default '',
  code       text not null unique
             default upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 8)),
  enabled    boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (owner_id, pg_id)
);

alter table public.pg_join_codes enable row level security;

drop policy if exists "owner manages own join codes" on public.pg_join_codes;
create policy "owner manages own join codes" on public.pg_join_codes
  for all to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

-- ---------------------------------------------------------------------------
-- 2. Registration requests.
-- ---------------------------------------------------------------------------

create table if not exists public.tenant_requests (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references auth.users (id) on delete cascade,
  pg_id      text not null,
  name       text not null,
  phone      text not null,
  email      text not null,
  kyc_doc    text,
  status     text not null default 'pending'
             check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

create index if not exists tenant_requests_owner_idx
  on public.tenant_requests (owner_id, status);

alter table public.tenant_requests enable row level security;

-- Owners read and decide their own requests. There is no insert policy:
-- requests are only created by register_tenant below.
drop policy if exists "owner reads own requests" on public.tenant_requests;
create policy "owner reads own requests" on public.tenant_requests
  for select to authenticated
  using ((select auth.uid()) = owner_id);

drop policy if exists "owner decides own requests" on public.tenant_requests;
create policy "owner decides own requests" on public.tenant_requests
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

drop policy if exists "owner deletes own requests" on public.tenant_requests;
create policy "owner deletes own requests" on public.tenant_requests
  for delete to authenticated
  using ((select auth.uid()) = owner_id);

-- ---------------------------------------------------------------------------
-- 3. Which PG is this code for? (name only)
-- ---------------------------------------------------------------------------

create or replace function public.pg_for_join_code(p_code text) returns text
language sql stable security definer set search_path = public as
$$
  select c.pg_name
  from pg_join_codes c
  where c.code = upper(trim(p_code))
    and c.enabled
    and public.workspace_active(c.owner_id)
  limit 1
$$;

-- ---------------------------------------------------------------------------
-- 4. File a registration request.
-- ---------------------------------------------------------------------------

create or replace function public.register_tenant(p_code text, p_name text,
  p_phone text, p_email text, p_kyc_doc text) returns text
language plpgsql volatile security definer set search_path = public as
$$
declare
  jc record;
  v_name text := trim(coalesce(p_name, ''));
  v_phone text := trim(coalesce(p_phone, ''));
  v_email text := lower(trim(coalesce(p_email, '')));
  v_request uuid;
  v_note jsonb;
begin
  select c.owner_id, c.pg_id, c.pg_name into jc
  from pg_join_codes c
  where c.code = upper(trim(coalesce(p_code, '')))
    and c.enabled
    and public.workspace_active(c.owner_id);
  if not found then
    raise exception 'code:bad_code' using errcode = 'P0001';
  end if;

  if length(v_name) < 2 or length(v_name) > 100
     or length(regexp_replace(v_phone, '[^0-9]', '', 'g')) < 10 or length(v_phone) > 20
     or v_email !~ '^[^[:space:],()"\\@]+@[^[:space:],()"\\@]+\.[^[:space:],()"\\@]+$'
     or length(v_email) > 200
     or p_kyc_doc is null or length(p_kyc_doc) < 100 or length(p_kyc_doc) > 3000000 then
    raise exception 'code:missing_fields' using errcode = 'P0001';
  end if;

  -- Already a resident somewhere: they sign in instead.
  if exists (select 1 from members m where m.member_email = v_email) then
    raise exception 'code:already_registered' using errcode = 'P0001';
  end if;

  -- A code can't be used to flood an owner.
  if (select count(*) from tenant_requests r
      where r.owner_id = jc.owner_id and r.status = 'pending') >= 50 then
    raise exception 'code:too_many' using errcode = 'P0001';
  end if;

  -- Registering twice updates the pending request instead of adding one.
  select r.id into v_request
  from tenant_requests r
  where r.owner_id = jc.owner_id and r.email = v_email and r.status = 'pending'
  limit 1;
  if v_request is not null then
    update tenant_requests
    set pg_id = jc.pg_id, name = v_name, phone = v_phone,
        kyc_doc = p_kyc_doc, created_at = now()
    where id = v_request;
    return jc.pg_name;
  end if;

  insert into tenant_requests (owner_id, pg_id, name, phone, email, kyc_doc)
  values (jc.owner_id, jc.pg_id, v_name, v_phone, v_email, p_kyc_doc)
  returning id into v_request;

  -- Tell the owner in the app's notification list (this write also pings
  -- the owner's open apps through realtime).
  v_note := jsonb_build_object(
    'id', 'n-reg-' || v_request::text,
    'title', 'New tenant registration',
    'body', v_name || ' asked to join ' || jc.pg_name || '. Review it under Tenants.',
    'type', 'announcement',
    'createdAt', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'read', false,
    'roleScope', 'managers',
    'tenantId', null,
    'pgId', jc.pg_id,
    'relatedEntityId', v_request::text,
    'customerId', null);
  insert into app_data (owner_id, key, data)
  values (jc.owner_id, 'notifications', '[]'::jsonb)
  on conflict (owner_id, key) do nothing;
  update app_data
  set data = jsonb_build_array(v_note) || data
  where owner_id = jc.owner_id and key = 'notifications';

  return jc.pg_name;
end
$$;

-- Callable before sign-in (the tenant has no account yet).
revoke all on function public.pg_for_join_code(text) from public;
revoke all on function public.register_tenant(text, text, text, text, text) from public;
grant execute on function public.pg_for_join_code(text) to anon, authenticated;
grant execute on function public.register_tenant(text, text, text, text, text) to anon, authenticated;
