-- PG Management — security hardening (review of 2026-10-07).
-- Run once in the Supabase dashboard AFTER schema.sql and 002–014.
-- Re-runnable.
--
-- 1. profiles: users may edit only their own name/phone (no self-promotion
--    to platform admin, no switching role or customer).
-- 2. Security-definer functions are not callable by anonymous users;
--    admin_delete_customer is service-role only.
-- 3. members: rows are written only by the `invite` Edge Function (service
--    role). Owners read and delete their own. One workspace per email.
-- 4. "Temporary password" enforcement reads app_metadata (only the service
--    role can write it), not user-editable user_metadata.
-- 5. Disabled or expired customers lose data access on the server, not
--    just in the app.
-- 6. tenant_save builds new items from whitelisted, typed fields with
--    server timestamps, caps sizes, resets KYC to pending when the document
--    changes, and tracks per-reader read state on workspace-wide
--    notifications.
-- 7. UPI submissions are bound to the submitting tenant; UTRs are unique per
--    workspace (except rejected ones).
-- 8. admin_delete_customer also finds tenant logins that have no profile.

-- ---------------------------------------------------------------------------
-- 1. profiles: column-level update rights.
-- ---------------------------------------------------------------------------

revoke update on public.profiles from anon, authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Function privileges. Supabase grants EXECUTE on new public functions to
--    anon explicitly, so revoking from PUBLIC alone is not enough.
-- ---------------------------------------------------------------------------

revoke all on function public.admin_delete_customer(uuid) from public, anon, authenticated;

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
  loop
    execute format('revoke execute on function %s from anon', f.sig);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 3. members: no direct client writes.
-- ---------------------------------------------------------------------------

drop policy if exists "owner manages own members" on public.members;
drop policy if exists "owner reads own members" on public.members;
create policy "owner reads own members" on public.members
  for select to authenticated
  using ((select auth.uid()) = owner_id);

drop policy if exists "owner deletes own members" on public.members;
create policy "owner deletes own members" on public.members
  for delete to authenticated
  using ((select auth.uid()) = owner_id);

-- Plain email shape: no spaces, commas, quotes or brackets. NOT VALID keeps
-- existing rows; new rows are checked.
alter table public.members drop constraint if exists members_email_shape;
alter table public.members add constraint members_email_shape
  check (member_email ~ '^[^[:space:],()"\\@]+@[^[:space:],()"\\@]+$') not valid;

-- One workspace per login. Skipped (with a notice) if existing data already
-- has the same email in two workspaces; the invite function enforces it for
-- new links either way.
do $$
begin
  create unique index if not exists members_one_workspace_idx
    on public.members (member_email);
exception when unique_violation then
  raise notice 'members_one_workspace_idx skipped: an email is linked to more than one workspace. Remove the duplicate rows, then re-run.';
end $$;

-- ---------------------------------------------------------------------------
-- 4. Temporary-password flag lives in app_metadata.
-- ---------------------------------------------------------------------------

update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
                        || '{"must_change_password": true}'::jsonb
where (raw_user_meta_data ->> 'must_change_password')::boolean is true
  and (raw_app_meta_data ->> 'must_change_password') is null;

create or replace function public.has_temp_password() returns boolean
language sql stable as
$$
  select coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'must_change_password')::boolean, false)
$$;

drop policy if exists "temp password blocks inserts" on public.app_data;
create policy "temp password blocks inserts" on public.app_data
  as restrictive for insert to authenticated
  with check (not public.has_temp_password());

drop policy if exists "temp password blocks updates" on public.app_data;
create policy "temp password blocks updates" on public.app_data
  as restrictive for update to authenticated
  using (not public.has_temp_password());

drop policy if exists "temp password blocks deletes" on public.app_data;
create policy "temp password blocks deletes" on public.app_data
  as restrictive for delete to authenticated
  using (not public.has_temp_password());

-- ---------------------------------------------------------------------------
-- 5. Customer status and subscription enforced on the server.
-- ---------------------------------------------------------------------------

-- True when the workspace's customer is enabled and unexpired. Workspaces
-- with no customer (legacy owners without a profile) stay active.
create or replace function public.workspace_active(p_owner uuid) returns boolean
language sql stable security definer set search_path = public as
$$
  select coalesce((
    select c.status = 'enabled' and (c.expires_at is null or c.expires_at > now())
    from profiles p
    join customers c on c.id = p.customer_id
    where p.id = p_owner
    limit 1
  ), true)
$$;

revoke all on function public.workspace_active(uuid) from public, anon;
grant execute on function public.workspace_active(uuid) to authenticated;

drop policy if exists "active workspace only" on public.app_data;
create policy "active workspace only" on public.app_data
  as restrictive for all to authenticated
  using (public.is_platform_admin() or public.workspace_active(owner_id))
  with check (public.is_platform_admin() or public.workspace_active(owner_id));

drop policy if exists "active workspace only" on public.upi_submissions;
create policy "active workspace only" on public.upi_submissions
  as restrictive for all to authenticated
  using (public.is_platform_admin() or public.workspace_active(owner_id))
  with check (public.is_platform_admin() or public.workspace_active(owner_id));

drop policy if exists "active workspace only" on public.pg_upi_settings;
create policy "active workspace only" on public.pg_upi_settings
  as restrictive for all to authenticated
  using (public.is_platform_admin() or public.workspace_active(owner_id))
  with check (public.is_platform_admin() or public.workspace_active(owner_id));

-- Tenant context now also requires an active workspace.
create or replace function public._tenant_context(p_owner uuid,
  out tenant_id text, out room_id text, out pg_id text)
language plpgsql stable security definer set search_path = public as
$$
begin
  select m.tenant_id into tenant_id
  from public.members m
  where m.owner_id = p_owner
    and m.member_email = lower((select auth.email()));
  if tenant_id is null then
    raise exception 'not a member of this workspace' using errcode = '42501';
  end if;
  if not public.workspace_active(p_owner) then
    raise exception 'this PG account is disabled or expired' using errcode = '42501';
  end if;

  select t ->> 'roomId' into room_id
  from public.app_data a, jsonb_array_elements(a.data) t
  where a.owner_id = p_owner and a.key = 'tenants' and t ->> 'id' = tenant_id
  limit 1;

  select r ->> 'pgId' into pg_id
  from public.app_data a, jsonb_array_elements(a.data) r
  where a.owner_id = p_owner and a.key = 'rooms' and r ->> 'id' = room_id
  limit 1;
end
$$;

revoke all on function public._tenant_context(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. tenant_save: typed new items, size caps, KYC reset, per-reader reads.
-- ---------------------------------------------------------------------------

-- Server "now" in the ISO-8601 form the app parses.
create or replace function public._iso_now() returns jsonb
language sql stable as
$$ select to_jsonb(to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')) $$;

-- A trimmed string field of length 1..max (or 0..max when p_optional), else null.
create or replace function public._str(v jsonb, p_max int, p_optional boolean default false)
returns text language sql immutable as
$$
  select case
    when jsonb_typeof(v) = 'string'
         and length(trim(v #>> '{}')) <= p_max
         and (p_optional or length(trim(v #>> '{}')) > 0)
      then trim(v #>> '{}')
    when p_optional and (v is null or jsonb_typeof(v) = 'null') then ''
  end
$$;

-- The item a tenant may add to collection p_key, rebuilt from whitelisted
-- fields, or null when the submission is not acceptable.
create or replace function public._tenant_new_item(p_key text, s jsonb,
  p_tenant text, p_room text) returns jsonb
language plpgsql stable as
$$
declare
  id text := public._str(s -> 'id', 80);
  customer jsonb := case when jsonb_typeof(s -> 'customerId') = 'string'
                         then s -> 'customerId' else 'null'::jsonb end;
begin
  if id is null then
    return null;
  end if;

  if p_key = 'maintenance' then
    if s ->> 'roomId' is distinct from p_room or p_room is null
       or s ->> 'status' is distinct from 'open'
       or public._str(s -> 'title', 200) is null
       or public._str(s -> 'category', 60) is null
       or coalesce(s ->> 'priority', '') not in ('low', 'medium', 'high')
       or not (s -> 'photo' is null or jsonb_typeof(s -> 'photo') = 'null'
               or (jsonb_typeof(s -> 'photo') = 'string'
                   and length(s ->> 'photo') <= 3000000)) then
      return null;
    end if;
    return jsonb_build_object(
      'id', id, 'roomId', p_room,
      'title', public._str(s -> 'title', 200),
      'category', public._str(s -> 'category', 60),
      'status', 'open', 'priority', s ->> 'priority',
      'createdAt', public._iso_now(), 'assignee', null,
      'photo', coalesce(s -> 'photo', 'null'::jsonb), 'customerId', customer);

  elsif p_key = 'visitors' then
    if s ->> 'tenantId' is distinct from p_tenant
       or s ->> 'status' is distinct from 'awaitingApproval'
       or public._str(s -> 'name', 100) is null
       or public._str(s -> 'purpose', 200, true) is null then
      return null;
    end if;
    return jsonb_build_object(
      'id', id, 'tenantId', p_tenant,
      'name', public._str(s -> 'name', 100),
      'purpose', public._str(s -> 'purpose', 200, true),
      'status', 'awaitingApproval', 'expectedAt', public._iso_now(),
      'customerId', customer);

  elsif p_key = 'attendance' then
    if s ->> 'tenantId' is distinct from p_tenant then
      return null;
    end if;
    return jsonb_build_object(
      'id', id, 'tenantId', p_tenant,
      'checkIn', public._iso_now(), 'checkOut', null);

  elsif p_key = 'notifications' then
    if s ->> 'roleScope' is distinct from 'managers'
       or coalesce(s ->> 'tenantId', p_tenant) is distinct from p_tenant
       or public._str(s -> 'title', 200) is null
       or public._str(s -> 'body', 1000, true) is null
       or coalesce(s ->> 'type', '') not in
          ('payment', 'visitor', 'maintenance', 'announcement', 'attendance') then
      return null;
    end if;
    return jsonb_build_object(
      'id', id, 'title', public._str(s -> 'title', 200),
      'body', public._str(s -> 'body', 1000, true),
      'type', s ->> 'type', 'createdAt', public._iso_now(), 'read', false,
      'roleScope', 'managers', 'tenantId', s -> 'tenantId',
      'pgId', case when jsonb_typeof(s -> 'pgId') = 'string' then s -> 'pgId' else 'null'::jsonb end,
      'relatedEntityId', case when jsonb_typeof(s -> 'relatedEntityId') = 'string'
                              then s -> 'relatedEntityId' else 'null'::jsonb end,
      'customerId', customer);
  end if;

  return null;
end
$$;

create or replace function public.tenant_save(p_owner uuid, p_key text, p_items jsonb)
returns void
language plpgsql volatile security definer set search_path = public as
$$
declare
  ctx record;
  stored jsonb;
  submitted jsonb;   -- id -> submitted item
  kept jsonb := '[]'::jsonb;
  added jsonb := '[]'::jsonb;
  seen text[] := '{}';
  e jsonb;
  s jsonb;
  item jsonb;
begin
  if p_key not in ('tenants', 'maintenance', 'visitors', 'attendance', 'notifications') then
    raise exception 'tenants cannot write %', p_key using errcode = '42501';
  end if;
  if public.has_temp_password() then
    raise exception 'set your own password first' using errcode = '42501';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'items must be an array' using errcode = '22023';
  end if;

  ctx := public._tenant_context(p_owner);

  -- Serialise with every other writer of this blob.
  insert into public.app_data (owner_id, key, data)
  values (p_owner, p_key, '[]'::jsonb)
  on conflict (owner_id, key) do nothing;
  select a.data into stored
  from public.app_data a
  where a.owner_id = p_owner and a.key = p_key
  for update;

  select coalesce(jsonb_object_agg(i ->> 'id', i), '{}'::jsonb) into submitted
  from jsonb_array_elements(p_items) i
  where jsonb_typeof(i) = 'object' and i ->> 'id' is not null;

  -- Existing items: kept as stored, except the few fields a tenant may change.
  for e in select x from jsonb_array_elements(stored) x loop
    s := submitted -> (e ->> 'id');
    if s is not null then
      if p_key = 'notifications'
         and public._tenant_can_see(p_key, e, ctx.tenant_id, ctx.room_id, ctx.pg_id)
         and s -> 'read' = 'true'::jsonb then
        if e ->> 'roleScope' = 'everyone' then
          -- Shared notification: record this reader only.
          if not coalesce(e -> 'readBy', '[]'::jsonb) ? ctx.tenant_id then
            e := jsonb_set(e, '{readBy}',
                   coalesce(e -> 'readBy', '[]'::jsonb) || to_jsonb(ctx.tenant_id));
          end if;
        else
          e := jsonb_set(e, '{read}', 'true'::jsonb);
        end if;
      elsif p_key = 'tenants' and e ->> 'id' = ctx.tenant_id then
        if public._str(s -> 'name', 100) is not null then
          e := jsonb_set(e, '{name}', to_jsonb(public._str(s -> 'name', 100)));
        end if;
        if jsonb_typeof(s -> 'phone') = 'string' and length(trim(s ->> 'phone')) <= 20 then
          e := jsonb_set(e, '{phone}', to_jsonb(trim(s ->> 'phone')));
        end if;
        if (jsonb_typeof(s -> 'kycDoc') = 'null'
            or (jsonb_typeof(s -> 'kycDoc') = 'string' and length(s ->> 'kycDoc') <= 3000000))
           and (s -> 'kycDoc') is distinct from (e -> 'kycDoc') then
          -- A new or removed document must be verified again.
          e := jsonb_set(e, '{kycDoc}', s -> 'kycDoc');
          e := jsonb_set(e, '{kyc}', '"pending"'::jsonb);
        end if;
      end if;
    end if;
    kept := kept || jsonb_build_array(e);
  end loop;

  -- New items: only the tenant's own, rebuilt from whitelisted fields.
  for s in
    select i from jsonb_array_elements(p_items) with ordinality x(i, ord)
    where jsonb_typeof(i) = 'object'
      and i ->> 'id' is not null
      and not exists (
        select 1 from jsonb_array_elements(stored) o where o ->> 'id' = i ->> 'id')
    order by ord
  loop
    if s ->> 'id' = any(seen) then
      continue;
    end if;
    item := public._tenant_new_item(p_key, s, ctx.tenant_id, ctx.room_id);
    if item is not null then
      added := added || jsonb_build_array(item);
      seen := seen || (s ->> 'id');
    end if;
  end loop;

  update public.app_data
  set data = added || kept
  where owner_id = p_owner and key = p_key;
end
$$;

revoke all on function public.tenant_save(uuid, text, jsonb) from public, anon;
grant execute on function public.tenant_save(uuid, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 6b. Owner saves: merge instead of replace.
--     The app sends the list it last loaded (p_base) and the list it has now
--     (p_items). Only what this device changed is applied to the stored list,
--     under a row lock, so two devices editing the same collection no longer
--     overwrite each other. Runs as the caller: RLS still decides access.
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
  for e in select x from jsonb_array_elements(stored) x loop
    id := e ->> 'id';
    if id is not null and id = any(removed) then
      continue;
    elsif id is not null and changed ? id then
      result := result || jsonb_build_array(changed -> id);
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
-- 7. UPI submissions bound to the submitting tenant; unique UTRs.
-- ---------------------------------------------------------------------------

drop policy if exists "member submits payment" on public.upi_submissions;
create policy "member submits payment" on public.upi_submissions
  for insert to authenticated
  with check (
    status = 'pending_confirmation'
    and confirmed_by is null
    and confirmed_at is null
    and rejection_reason is null
    and amount > 0
    and member_email = lower((select auth.email()))
    and exists (
      select 1 from public.members m
      where m.owner_id = upi_submissions.owner_id
        and m.member_email = lower((select auth.email()))
        and m.tenant_id = upi_submissions.tenant_id
    )
    and (screenshot_path is null or (
      split_part(screenshot_path, '/', 1) = owner_id::text
      and split_part(screenshot_path, '/', 3) = tenant_id))
  );

-- Tenants see only submissions from their current PG link (an email reused
-- in a later PG doesn't reveal the old PG's records).
drop policy if exists "member reads own submissions" on public.upi_submissions;
create policy "member reads own submissions" on public.upi_submissions
  for select to authenticated
  using (
    member_email = lower((select auth.email()))
    and exists (
      select 1 from public.members m
      where m.owner_id = upi_submissions.owner_id
        and m.member_email = lower((select auth.email()))
        and m.tenant_id = upi_submissions.tenant_id
    )
  );

drop policy if exists "temp password blocks submissions" on public.upi_submissions;
create policy "temp password blocks submissions" on public.upi_submissions
  as restrictive for insert to authenticated
  with check (not public.has_temp_password());

do $$
begin
  create unique index if not exists upi_submissions_utr_idx
    on public.upi_submissions (owner_id, utr)
    where status <> 'rejected';
exception when unique_violation then
  raise notice 'upi_submissions_utr_idx skipped: the same UTR is already used twice in a workspace. Reject the duplicate, then re-run.';
end $$;

-- ---------------------------------------------------------------------------
-- 8. Customer deletion also removes tenant logins without a profile row.
-- ---------------------------------------------------------------------------

create or replace function public.admin_delete_customer(target uuid)
returns uuid[]
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_ids uuid[];
  user_ids  uuid[];
begin
  select array_agg(id) into owner_ids
    from profiles where customer_id = target and role = 'owner';

  -- Every login under the customer: profiles, plus tenant logins created by
  -- the owners' invites (legacy tenants have no profile row).
  select array_agg(distinct u) into user_ids from (
    select id as u from profiles where customer_id = target
    union
    select user_id from invites
    where owner_ids is not null and owner_id = any(owner_ids) and user_id is not null
    union
    select au.id from auth.users au
    join members m on lower(au.email) = m.member_email
    where owner_ids is not null and m.owner_id = any(owner_ids)
  ) s
  -- Never a login that belongs to another customer or to a platform admin.
  where not exists (
    select 1 from profiles p
    where p.id = s.u and (p.customer_id is distinct from target or p.platform_admin)
  );

  if owner_ids is not null then
    delete from app_data         where owner_id = any(owner_ids);
    delete from workspace_changes where owner_id = any(owner_ids);
    delete from members          where owner_id = any(owner_ids);
    delete from invites          where owner_id = any(owner_ids);
    delete from pg_upi_settings  where owner_id = any(owner_ids);
    delete from upi_submissions  where owner_id = any(owner_ids);
  end if;
  if user_ids is not null then
    delete from push_tokens where user_id = any(user_ids);
  end if;

  delete from audit_logs where customer_id = target;
  delete from profiles   where customer_id = target;
  delete from customers  where id = target;

  return coalesce(user_ids, array[]::uuid[]);
end;
$$;

revoke all on function public.admin_delete_customer(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9. Lookup used by the `invite` Edge Function (service role only): the auth
--    user behind an email, so an owner can never invite another business's
--    owner or a platform admin, and an existing tenant login is reused.
-- ---------------------------------------------------------------------------

create or replace function public.auth_user_id_by_email(p_email text) returns uuid
language sql stable security definer set search_path = public, auth as
$$ select id from auth.users where lower(email) = lower(p_email) limit 1 $$;

revoke all on function public.auth_user_id_by_email(text) from public, anon, authenticated;
grant execute on function public.auth_user_id_by_email(text) to service_role;
