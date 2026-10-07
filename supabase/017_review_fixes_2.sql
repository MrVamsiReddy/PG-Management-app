-- PG Management — fixes from the second 2026-10-08 review.
-- Run once in the Supabase dashboard AFTER schema.sql and 002–016.
-- Re-runnable.
--
-- 1. Payment-proof uploads: images only, at most 5 MB each. The app uploads
--    one compressed JPEG (≈100 KB); anything else is not a screenshot.
-- 2. UPI submissions are audited by the database. Tenants can't insert into
--    audit_logs (only owners/admins can), so the app's own audit call never
--    recorded a tenant's submission.

-- ---------------------------------------------------------------------------
-- 1. payment-proofs bucket limits.
-- ---------------------------------------------------------------------------

update storage.buckets
set file_size_limit = 5 * 1024 * 1024,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
where id = 'payment-proofs';

-- ---------------------------------------------------------------------------
-- 2. Audit every new UPI submission.
-- ---------------------------------------------------------------------------

create or replace function public.audit_upi_submission()
returns trigger language plpgsql security definer set search_path = public as
$$
begin
  insert into public.audit_logs
    (customer_id, actor_user_id, actor_role, action, entity_type, entity_id, after_json)
  values (
    -- The workspace owner's customer, never the client-supplied column.
    (select p.customer_id from public.profiles p where p.id = new.owner_id),
    (select auth.uid()),
    'tenant',
    'payment_submitted',
    'payment',
    new.payment_id,
    jsonb_build_object('utr', new.utr, 'amount', new.amount,
                       'tenant_id', new.tenant_id, 'submission_id', new.id));
  return null;
end
$$;

revoke all on function public.audit_upi_submission() from public, anon, authenticated;

drop trigger if exists upi_submissions_audit on public.upi_submissions;
create trigger upi_submissions_audit
  after insert on public.upi_submissions
  for each row execute function public.audit_upi_submission();
