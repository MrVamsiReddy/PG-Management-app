-- PG Management — fixes from the 2026-10-08 code review.
-- Run once in the Supabase dashboard AFTER schema.sql and 002–015.
-- Re-runnable. 014 and 015 skip the definitions this file replaces, so
-- re-running an older file later no longer undoes these fixes.
--
-- ALSO REQUIRED (dashboard, not SQL): Authentication → Sign In / Providers →
-- turn OFF "Allow new users to sign up". Accounts are created only by the
-- Edge Functions (admin API), which keep working with sign-ups off.
--
-- 1. Accounts with no profile get no workspace. Every owner without a profile
--    today ("legacy owners") is first turned into a customer, so nobody
--    who uses the app now is locked out.
-- 2. push_tokens: a device can only be registered under the signed-in
--    user's own email.
-- 3. owner_save keeps fields an older app version doesn't know about.
-- 4. Deleting an owner's login no longer trips the workspace_changes trigger.
-- 5. Payment proofs follow the account's enabled/expired status.
-- 6. tenant_workspace: a tenant's whole filtered view in one call, and
--    shared notifications no longer reveal which other tenants read them.

-- Marker the older files check before (re)defining functions replaced here.
create or replace function public._migration_016() returns boolean
language sql immutable as $$ select true $$;

-- ---------------------------------------------------------------------------
-- 1. No profile, no workspace.
-- ---------------------------------------------------------------------------

-- Legacy owners: own workspace data, have no profile, and are not a tenant
-- anywhere. Each becomes an enabled customer with no expiry (as today).
do $$
declare
  u record;
  new_customer uuid;
  converted int := 0;
begin
  for u in
    select au.id, coalesce(au.email, '') as email,
           coalesce(au.raw_user_meta_data ->> 'full_name', '') as full_name
    from auth.users au
    where exists (select 1 from public.app_data a where a.owner_id = au.id)
      and not exists (select 1 from public.profiles p where p.id = au.id)
      and not exists (
        select 1 from public.members m where m.member_email = lower(au.email))
  loop
    insert into public.customers (business_name, owner_name, owner_email, plan, expires_at)
    values (coalesce(nullif(u.full_name, ''), split_part(u.email, '@', 1)),
            u.full_name, u.email, 'legacy', null)
    returning id into new_customer;
    insert into public.profiles (id, role, customer_id, full_name)
    values (u.id, 'owner', new_customer, u.full_name);
    converted := converted + 1;
  end loop;
  if converted > 0 then
    raise notice '% legacy owner(s) converted to customers (plan "legacy"). Review them in the admin console and delete any you do not recognise.', converted;
  end if;
end $$;

-- Active only with a profile whose customer is enabled and unexpired.
-- (Platform admins are allowed separately by the policies.)
create or replace function public.workspace_active(p_owner uuid) returns boolean
language sql stable security definer set search_path = public as
$$
  select coalesce((
    select c.status = 'enabled' and (c.expires_at is null or c.expires_at > now())
    from profiles p
    join customers c on c.id = p.customer_id
    where p.id = p_owner
    limit 1
  ), false)
$$;

revoke all on function public.workspace_active(uuid) from public, anon;
grant execute on function public.workspace_active(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. push_tokens: own email only.
-- ---------------------------------------------------------------------------

delete from public.push_tokens t
using auth.users u
where u.id = t.user_id and t.email is distinct from lower(u.email);

drop policy if exists "own tokens" on public.push_tokens;
create policy "own tokens" on public.push_tokens
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id
    and email = lower((select auth.email())));

-- ---------------------------------------------------------------------------
-- 3. owner_save: an edited item keeps stored fields the app didn't send.
-- ---------------------------------------------------------------------------

create or replace function public.owner_save(p_owner uuid, p_key text,
  p_base jsonb, p_items jsonb) returns jsonb
language plpgsql volatile set search_path = public as
$$
declare
  stored jsonb;
  base jsonb;      -- id -> item as this device last saw it
  mine jsonb;      -- id -> item as this device has it now
  changed jsonb;   -- id -> item this device added or edited
  removed text[];  -- ids this device deleted
  result jsonb := '[]'::jsonb;
  e jsonb;
  id text;
begin
  if jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_typeof(p_base) is distinct from 'array' then
    raise exception 'items must be arrays' using errcode = '22023';
  end if;

  insert into public.app_data (owner_id, key, data)
  values (p_owner, p_key, '[]'::jsonb)
  on conflict (owner_id, key) do nothing;
  select a.data into stored
  from public.app_data a
  where a.owner_id = p_owner and a.key = p_key
  for update;
  if not found then
    raise exception 'no access to this workspace' using errcode = '42501';
  end if;

  select coalesce(jsonb_object_agg(i ->> 'id', i), '{}'::jsonb) into base
  from jsonb_array_elements(p_base) i where i ->> 'id' is not null;
  select coalesce(jsonb_object_agg(i ->> 'id', i), '{}'::jsonb) into mine
  from jsonb_array_elements(p_items) i where i ->> 'id' is not null;

  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into changed
  from jsonb_each(mine) as m(k, v)
  where (base -> k) is distinct from v;

  select coalesce(array_agg(k), '{}') into removed
  from jsonb_object_keys(base) as k
  where not mine ? k;

  -- New items (not stored yet) go first, in this device's order.
  for e in select i from jsonb_array_elements(p_items) i loop
    id := e ->> 'id';
    if id is not null and changed ? id
       and not exists (select 1 from jsonb_array_elements(stored) o where o ->> 'id' = id) then
      result := result || jsonb_build_array(e);
    end if;
  end loop;

  -- Stored items keep their order; this device's edits and deletes apply.
  -- An edit is merged over the stored item, so fields this app version
  -- doesn't know about survive.
  for e in select x from jsonb_array_elements(stored) x loop
    id := e ->> 'id';
    if id is not null and id = any(removed) then
      continue;
    elsif id is not null and changed ? id then
      result := result || jsonb_build_array(
        case when jsonb_typeof(e) = 'object' then e || (changed -> id)
             else changed -> id end);
    else
      result := result || jsonb_build_array(e);
    end if;
  end loop;

  update public.app_data
  set data = result
  where owner_id = p_owner and key = p_key;
  return result;
end
$$;

revoke all on function public.owner_save(uuid, text, jsonb, jsonb) from public, anon;
grant execute on function public.owner_save(uuid, text, jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. workspace_changes trigger: skip owners whose login is being deleted.
-- ---------------------------------------------------------------------------

create or replace function public.touch_workspace_changes()
returns trigger language plpgsql security definer set search_path = public as
$$
declare
  ws uuid := coalesce(new.owner_id, old.owner_id);
begin
  -- Cascade from deleting the owner's login: there is nobody left to ping,
  -- and the row would point at a user that no longer exists.
  if tg_op = 'DELETE' and not exists (select 1 from auth.users where id = ws) then
    return null;
  end if;
  insert into public.workspace_changes (owner_id, changed_at)
  values (ws, now())
  on conflict (owner_id) do update set changed_at = excluded.changed_at;
  return null;
end
$$;

-- ---------------------------------------------------------------------------
-- 5. Payment proofs: also require an active account.
-- ---------------------------------------------------------------------------

create or replace function public.can_access_proof(ws text, tenant text) returns boolean
language sql stable security definer set search_path = public, auth as
$$
  -- CASE, not AND: SQL may evaluate AND operands in any order, and the cast
  -- must never see a malformed folder name.
  select case
    when ws !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then false
    else public.workspace_active(ws::uuid)
    and ((select auth.uid())::text = ws
      or exists (
        select 1 from public.members m
        where m.owner_id::text = ws
          and m.tenant_id = tenant
          and m.member_email = lower((select auth.email()))
      ))
  end
$$;

revoke execute on function public.can_access_proof(text, text) from anon;

-- ---------------------------------------------------------------------------
-- 6. Tenant reads: one call for the whole view; private read receipts.
-- ---------------------------------------------------------------------------

-- What a tenant sees of a visible item: shared notifications show only
-- whether this tenant read them, not who else did.
create or replace function public._tenant_view(p_key text, e jsonb, p_tenant text)
returns jsonb language sql immutable as
$$
  select case
    when p_key = 'notifications' and e ? 'readBy' then
      jsonb_set(e, '{readBy}',
        case when coalesce(e -> 'readBy', '[]'::jsonb) ? p_tenant
             then jsonb_build_array(p_tenant) else '[]'::jsonb end)
    else e
  end
$$;

create or replace function public.tenant_collection(p_owner uuid, p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as
$$
declare
  ctx record;
  stored jsonb;
begin
  ctx := public._tenant_context(p_owner);
  select a.data into stored
  from public.app_data a
  where a.owner_id = p_owner and a.key = p_key;

  return coalesce((
    select jsonb_agg(public._tenant_view(p_key, x.e, ctx.tenant_id) order by x.ord)
    from jsonb_array_elements(coalesce(stored, '[]'::jsonb)) with ordinality x(e, ord)
    where public._tenant_can_see(p_key, x.e, ctx.tenant_id, ctx.room_id, ctx.pg_id)
  ), '[]'::jsonb);
end
$$;

-- Every collection a tenant may see, as {key: [items]}, with the tenant's
-- context worked out once instead of once per collection.
create or replace function public.tenant_workspace(p_owner uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as
$$
declare
  ctx record;
  result jsonb;
begin
  ctx := public._tenant_context(p_owner);
  select coalesce(jsonb_object_agg(k.key, coalesce((
    select jsonb_agg(public._tenant_view(k.key, x.e, ctx.tenant_id) order by x.ord)
    from public.app_data a,
         jsonb_array_elements(a.data) with ordinality x(e, ord)
    where a.owner_id = p_owner and a.key = k.key
      and public._tenant_can_see(k.key, x.e, ctx.tenant_id, ctx.room_id, ctx.pg_id)
  ), '[]'::jsonb)), '{}'::jsonb)
  into result
  from unnest(array['pgs', 'rooms', 'tenants', 'payments', 'maintenance',
                    'visitors', 'announcements', 'attendance', 'utilities',
                    'notifications']) k(key);
  return result;
end
$$;

revoke all on function public.tenant_collection(uuid, text) from public, anon;
grant execute on function public.tenant_collection(uuid, text) to authenticated;
revoke all on function public.tenant_workspace(uuid) from public, anon;
grant execute on function public.tenant_workspace(uuid) to authenticated;
