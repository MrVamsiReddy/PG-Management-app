-- PG Management — permanent customer deletion (Improvements batch, task 1).
-- Run once in the Supabase dashboard AFTER 004/006/007.
--
-- Atomic DB cascade for a customer. A plpgsql function runs in a single
-- transaction, so the DB half of the delete is all-or-nothing (no orphans).
-- Auth users and Storage objects are cleaned up by the `delete-customer` Edge
-- Function using the returned user ids (those APIs live outside Postgres).
--
-- Callable by the service role only (the Edge Function verifies the caller is
-- a platform admin first). Direct client access is revoked.

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
  select array_agg(id) into user_ids from profiles where customer_id = target;
  select array_agg(id) into owner_ids
    from profiles where customer_id = target and role = 'owner';

  -- Live workspace model (keyed by the owner's user id).
  if owner_ids is not null then
    delete from app_data        where owner_id = any(owner_ids);
    delete from members         where owner_id = any(owner_ids);
    delete from invites         where owner_id = any(owner_ids);
    delete from pg_upi_settings  where owner_id = any(owner_ids);
    delete from upi_submissions  where owner_id = any(owner_ids);
  end if;
  if user_ids is not null then
    delete from push_tokens where user_id = any(user_ids);
  end if;

  -- Platform + relational data. Deleting the customers row cascades every
  -- 004 table (pgs → floors → rooms → beds → tenants → payment_dues →
  -- payment_submissions → payment_proof_files, plus rent_rules,
  -- pg_payment_settings, notices, complaints, visitors, tenant_invites).
  delete from audit_logs where customer_id = target;
  delete from profiles   where customer_id = target;
  delete from customers  where id = target;

  return coalesce(user_ids, array[]::uuid[]);
end;
$$;

revoke all on function public.admin_delete_customer(uuid) from public;
revoke all on function public.admin_delete_customer(uuid) from authenticated;
