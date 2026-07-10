// PG Management — `delete-customer` Edge Function.
//
// Permanently deletes a customer: its relational + workspace data (via the
// atomic admin_delete_customer RPC), its Storage objects, and every auth user
// (owner + tenants). Platform-admin only.
//
// Deploy (Supabase dashboard): Edge Functions → `delete-customer` → paste →
// Deploy. Run supabase/008_delete_customer.sql first. No extra secret.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "content-type": "application/json" } });

  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const authed = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
    );
    const { data: userData } = await authed.auth.getUser();
    const caller = userData?.user;
    if (!caller) return json({ error: "code:unauthorized" }, 401);

    const { data: prof } = await admin.from("profiles").select("platform_admin").eq("id", caller.id).maybeSingle();
    if (!prof?.platform_admin) return json({ error: "code:not_admin" }, 403);

    const { customerId } = await req.json().catch(() => ({}));
    if (!customerId) return json({ error: "code:missing_fields" }, 400);

    // Atomic DB cascade; returns every auth user id under the customer.
    const { data: userIds, error: rpcErr } = await admin.rpc("admin_delete_customer", { target: customerId });
    if (rpcErr) return json({ error: "code:server_error" }, 500);
    const ids: string[] = (userIds as string[] | null) ?? [];

    // Storage: purge the payment-proofs workspace folder for each user id
    // (only the owner's prefix actually holds objects; the rest are no-ops).
    for (const id of ids) await purgePrefix(admin, "payment-proofs", id);

    // Auth users last (cascades any residual push_tokens too).
    for (const id of ids) {
      try { await admin.auth.admin.deleteUser(id); } catch (_e) { /* best effort */ }
    }

    return json({ ok: true, deletedUsers: ids.length });
  } catch (_e) {
    return json({ error: "code:server_error" }, 500);
  }
});

// deno-lint-ignore no-explicit-any
async function purgePrefix(admin: any, bucket: string, prefix: string): Promise<void> {
  const { data } = await admin.storage.from(bucket).list(prefix, { limit: 1000 });
  if (!data || data.length === 0) return;
  const files: string[] = [];
  for (const entry of data) {
    const path = `${prefix}/${entry.name}`;
    if (entry.id === null) {
      await purgePrefix(admin, bucket, path); // nested folder
    } else {
      files.push(path);
    }
  }
  if (files.length) await admin.storage.from(bucket).remove(files);
}
