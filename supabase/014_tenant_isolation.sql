-- PG Management — tenant data isolation inside a workspace.
-- Run once in the Supabase dashboard AFTER schema.sql, 002, 006, 007, 013,
-- then run 015 and 016. Re-runnable: functions that 015/016 replaced are
-- skipped, so running this file again never brings back the older versions.
--
-- Before: 002_members.sql let any linked tenant SELECT every app_data row of
-- the workspace (the whole `tenants` blob with every resident's phone, email
-- and KYC image) and INSERT/UPDATE whole tenant-facing blobs, so one tenant
-- could rewrite or wipe other tenants' visitors/maintenance/notifications.
-- The app only filtered in Dart.
--
-- After: tenants have NO direct access to app_data. They go through two
-- SECURITY DEFINER functions that filter and merge on the server:
--   * tenant_collection(owner, key) — returns only the items of that
--     collection the calling tenant may see.
--   * tenant_save(owner, key, items) — merges the tenant's changes into the
--     stored blob under a row lock: tenants may append their own new
--     requests/visitors/attendance, alert managers, mark visible
--     notifications read, and edit their own name/phone/KYC document.
--     Everything else in the blob is kept exactly as stored.
-- Payment-proof screenshots are narrowed the same way (own folder only), and
-- tenants get live-sync pings through `workspace_changes` instead of
-- subscribing to app_data rows.

-- ---------------------------------------------------------------------------
-- 1. Remove direct tenant access to app_data.
-- ---------------------------------------------------------------------------

drop policy if exists "member reads workspace" on public.app_data;
drop policy if exists "member inserts tenant collections" on public.app_data;
drop policy if exists "member updates tenant collections" on public.app_data;

-- ---------------------------------------------------------------------------
-- 2. Who is the calling tenant? (tenant id, their room, their PG)
-- ---------------------------------------------------------------------------

-- Skipped once 015 has replaced it.
do $guard$
begin
  if to_regprocedure('public._tenant_new_item(text,jsonb,text,text)') is null then
    execute $def$
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

  select t ->> 'roomId' into room_id
  from public.app_data a, jsonb_array_elements(a.data) t
  where a.owner_id = p_owner and a.key = 'tenants' and t ->> 'id' = tenant_id
  limit 1;

  select r ->> 'pgId' into pg_id
  from public.app_data a, jsonb_array_elements(a.data) r
  where a.owner_id = p_owner and a.key = 'rooms' and r ->> 'id' = room_id
  limit 1;
end
$$
$def$;
  end if;
end $guard$;

-- Whether item `e` of collection `p_key` is visible to that tenant.
create or replace function public._tenant_can_see(p_key text, e jsonb,
  p_tenant text, p_room text, p_pg text) returns boolean
language sql immutable as
$$
  select coalesce(case p_key
    when 'tenants'       then e ->> 'id' = p_tenant
    when 'pgs'           then e ->> 'id' = p_pg
    when 'rooms'         then e ->> 'id' = p_room
    when 'payments'      then e ->> 'tenantId' = p_tenant
    when 'visitors'      then e ->> 'tenantId' = p_tenant
    when 'attendance'    then e ->> 'tenantId' = p_tenant
    when 'maintenance'   then e ->> 'roomId' = p_room
    when 'utilities'     then e ->> 'roomId' = p_room
    when 'announcements' then e ->> 'pgId' is null or e ->> 'pgId' = p_pg
    when 'notifications' then
      (e ->> 'roleScope' = 'everyone' and (e ->> 'pgId' is null or e ->> 'pgId' = p_pg))
      or (e ->> 'roleScope' = 'tenant' and e ->> 'tenantId' = p_tenant)
    else false
  end, false)
$$;

-- ---------------------------------------------------------------------------
-- 3. Tenant reads: one collection, filtered server-side.
-- ---------------------------------------------------------------------------

-- Skipped once 016 has replaced it.
do $guard$
begin
  if to_regprocedure('public._migration_016()') is null then
    execute $def$
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
    select jsonb_agg(x.e order by x.ord)
    from jsonb_array_elements(coalesce(stored, '[]'::jsonb)) with ordinality x(e, ord)
    where public._tenant_can_see(p_key, x.e, ctx.tenant_id, ctx.room_id, ctx.pg_id)
  ), '[]'::jsonb);
end
$$
$def$;
  end if;
end $guard$;

-- ---------------------------------------------------------------------------
-- 4. Tenant writes: merge, never replace.
-- ---------------------------------------------------------------------------

-- Skipped once 015 has replaced it.
do $guard$
begin
  if to_regprocedure('public._tenant_new_item(text,jsonb,text,text)') is null then
    execute $def$
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
  e jsonb;
  s jsonb;
begin
  if p_key not in ('tenants', 'maintenance', 'visitors', 'attendance', 'notifications') then
    raise exception 'tenants cannot write %', p_key using errcode = '42501';
  end if;
  if ((select auth.jwt()) -> 'user_metadata' ->> 'must_change_password')::boolean is true then
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
        e := jsonb_set(e, '{read}', 'true'::jsonb);
      elsif p_key = 'tenants' and e ->> 'id' = ctx.tenant_id then
        if jsonb_typeof(s -> 'name') = 'string' and length(trim(s ->> 'name')) > 0 then
          e := jsonb_set(e, '{name}', to_jsonb(trim(s ->> 'name')));
        end if;
        if jsonb_typeof(s -> 'phone') = 'string' then
          e := jsonb_set(e, '{phone}', to_jsonb(trim(s ->> 'phone')));
        end if;
        if jsonb_typeof(s -> 'kycDoc') in ('string', 'null') then
          e := jsonb_set(e, '{kycDoc}', s -> 'kycDoc');
        end if;
      end if;
    end if;
    kept := kept || jsonb_build_array(e);
  end loop;

  -- New items: only the tenant's own, in their initial state.
  for s in
    select i from jsonb_array_elements(p_items) with ordinality x(i, ord)
    where jsonb_typeof(i) = 'object'
      and i ->> 'id' is not null
      and not exists (
        select 1 from jsonb_array_elements(stored) o where o ->> 'id' = i ->> 'id')
    order by ord
  loop
    if (p_key = 'maintenance'
          and s ->> 'roomId' = ctx.room_id and s ->> 'status' = 'open')
       or (p_key = 'visitors'
          and s ->> 'tenantId' = ctx.tenant_id and s ->> 'status' = 'awaitingApproval')
       or (p_key = 'attendance'
          and s ->> 'tenantId' = ctx.tenant_id)
       or (p_key = 'notifications'
          and s ->> 'roleScope' = 'managers'
          and coalesce(s ->> 'tenantId', ctx.tenant_id) = ctx.tenant_id)
    then
      added := added || jsonb_build_array(s);
    end if;
  end loop;

  update public.app_data
  set data = added || kept
  where owner_id = p_owner and key = p_key;
end
$$
$def$;
  end if;
end $guard$;

revoke all on function public._tenant_context(uuid) from public, anon;
revoke all on function public.tenant_collection(uuid, text) from public, anon;
revoke all on function public.tenant_save(uuid, text, jsonb) from public, anon;
grant execute on function public.tenant_collection(uuid, text) to authenticated;
grant execute on function public.tenant_save(uuid, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Live sync for tenants: a per-workspace "something changed" ping.
--    Realtime only delivers rows a subscriber can SELECT, and tenants can no
--    longer select app_data, so they listen here and re-fetch via the RPC.
-- ---------------------------------------------------------------------------

create table if not exists public.workspace_changes (
  owner_id   uuid primary key references auth.users (id) on delete cascade,
  changed_at timestamptz not null default now()
);

alter table public.workspace_changes enable row level security;

drop policy if exists "workspace reads changes" on public.workspace_changes;
create policy "workspace reads changes" on public.workspace_changes
  for select to authenticated
  using ((select auth.uid()) = owner_id
    or exists (
      select 1 from public.members m
      where m.owner_id = workspace_changes.owner_id
        and m.member_email = lower((select auth.email()))
    ));

-- Skipped once 016 has replaced it.
do $guard$
begin
  if to_regprocedure('public._migration_016()') is null then
    execute $def$
create or replace function public.touch_workspace_changes()
returns trigger language plpgsql security definer set search_path = public as
$$
begin
  insert into public.workspace_changes (owner_id, changed_at)
  values (coalesce(new.owner_id, old.owner_id), now())
  on conflict (owner_id) do update set changed_at = excluded.changed_at;
  return null;
end
$$
$def$;
  end if;
end $guard$;

drop trigger if exists app_data_workspace_changes on public.app_data;
create trigger app_data_workspace_changes
  after insert or update or delete on public.app_data
  for each row execute function public.touch_workspace_changes();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and tablename = 'workspace_changes'
     ) then
    alter publication supabase_realtime add table public.workspace_changes;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Payment-proof screenshots: tenants see only their own folder.
--    Path: {owner_id}/{pg_id}/{tenant_id}/{payment_id}/{filename}
-- ---------------------------------------------------------------------------

-- Skipped once 016 has replaced it.
do $guard$
begin
  if to_regprocedure('public._migration_016()') is null then
    execute $def$
create or replace function public.can_access_proof(ws text, tenant text) returns boolean
language sql stable security definer set search_path = public, auth as
$$
  select (select auth.uid())::text = ws
    or exists (
      select 1 from public.members m
      where m.owner_id::text = ws
        and m.tenant_id = tenant
        and m.member_email = lower((select auth.email()))
    )
$$
$def$;
  end if;
end $guard$;

drop policy if exists "proofs workspace read" on storage.objects;
create policy "proofs workspace read" on storage.objects
  for select to authenticated
  using (bucket_id = 'payment-proofs'
    and public.can_access_proof((storage.foldername(name))[1],
                                (storage.foldername(name))[3]));

drop policy if exists "proofs workspace insert" on storage.objects;
create policy "proofs workspace insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'payment-proofs'
    and public.can_access_proof((storage.foldername(name))[1],
                                (storage.foldername(name))[3]));
