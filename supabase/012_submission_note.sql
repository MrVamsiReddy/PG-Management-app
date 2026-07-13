-- PG Management — optional tenant note on UPI submissions.
-- Run once in the Supabase dashboard AFTER 007. Re-runnable.

alter table public.upi_submissions
  add column if not exists note text;
