-- PG Management — atomic UPI confirmation.
-- Run once in the Supabase dashboard AFTER schema.sql and 002–017.
-- Re-runnable.
--
-- Confirming a tenant's UPI submission used to be two separate writes: the
-- submission was marked confirmed, then the payments list was saved. If the
-- second write failed the two disagreed. owner_confirm_submission does both
-- in one transaction: the submission moves pending → confirmed and the
-- owner's payments list is merged (owner_save), or nothing changes.
-- Runs as the caller, so row-level security still decides access.

create or replace function public.owner_confirm_submission(p_owner uuid, p_key text,
  p_base jsonb, p_items jsonb, p_submission uuid) returns jsonb
language plpgsql volatile set search_path = public as
$$
begin
  if p_key is distinct from 'payments' then
    raise exception 'only payments can be saved with a confirmation' using errcode = '22023';
  end if;

  -- Only a pending submission of this workspace can be confirmed, once.
  update public.upi_submissions
  set status = 'confirmed',
      confirmed_by = (select auth.uid()),
      confirmed_at = now()
  where id = p_submission
    and owner_id = p_owner
    and status = 'pending_confirmation';
  if not found then
    raise exception 'already reviewed' using errcode = 'P0001';
  end if;

  return public.owner_save(p_owner, p_key, p_base, p_items);
end
$$;

revoke all on function public.owner_confirm_submission(uuid, text, jsonb, jsonb, uuid) from public, anon;
grant execute on function public.owner_confirm_submission(uuid, text, jsonb, jsonb, uuid) to authenticated;
