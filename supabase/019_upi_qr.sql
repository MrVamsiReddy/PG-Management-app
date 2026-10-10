-- PG Management — simple UPI payments with the owner's own QR.
-- Run once in the Supabase dashboard AFTER schema.sql and 002–018.
-- Re-runnable.
--
-- 1. pg_upi_settings.qr_image: the owner's own UPI QR picture (base64),
--    shown to tenants to scan. Tenants can already read their workspace's
--    UPI settings (007). Capped at ~1.5 MB.
-- 2. A submission's proof is a screenshot, a UTR, or both: utr may be empty
--    when a screenshot is attached (some UPI apps hide the UTR).

alter table public.pg_upi_settings add column if not exists qr_image text;

alter table public.pg_upi_settings drop constraint if exists pg_upi_settings_qr_size;
alter table public.pg_upi_settings add constraint pg_upi_settings_qr_size
  check (qr_image is null or length(qr_image) <= 2000000);

alter table public.upi_submissions alter column utr drop not null;

-- Every submission carries some proof. NOT VALID keeps existing rows.
alter table public.upi_submissions drop constraint if exists upi_submissions_proof;
alter table public.upi_submissions add constraint upi_submissions_proof
  check ((utr is not null and utr <> '') or screenshot_path is not null) not valid;
