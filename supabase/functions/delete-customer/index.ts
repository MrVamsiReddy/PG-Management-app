// PG Management — `delete-customer` Edge Function.
//
// Permanently deletes a customer: its relational + workspace data (via the
// atomic admin_delete_customer RPC), its Storage objects, and every auth user
// (owner + tenants). Platform-admin only.
//
// Deploy (Supabase dashboard): Edge Functions → `delete-customer` → paste →
// Deploy. Run supabase/008_delete_customer.sql first. No extra secret.

import { createClient } from "npm:@supabase/supabase-js@2";

// Browsers may call this only from the web app (plus localhost for
// development). Mobile apps send no Origin and are unaffected. Override with
// the ALLOWED_ORIGINS secret (comma-separated) if the web app moves.
const allowedOrigins = (Deno.env.get("ALLOWED_ORIGINS") ?? "https://mrvamsireddy.github.io")
  .split(",").map((o) => o.trim()).filter(Boolean);

function corsHeadersFor(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  const local = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
  return {
    "Access-Control-Allow-Origin": allowedOrigins.includes(origin) || local ? origin : (allowedOrigins[0] ?? ""),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  };
}

Deno.serve(async (req) => {
  const corsHeaders = corsHeadersFor(req);
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
  const PAGE = 1000;
  const files: string[] = [];
  const folders: string[] = [];
  // List every page first; removing while paging would shift the offsets.
  for (let offset = 0; ; offset += PAGE) {
    const { data } = await admin.storage.from(bucket).list(prefix, { limit: PAGE, offset });
    if (!data || data.length === 0) break;
    for (const entry of data) {
      const path = `${prefix}/${entry.name}`;
      if (entry.id === null) folders.push(path); // nested folder
      else files.push(path);
    }
    if (data.length < PAGE) break;
  }
  for (const folder of folders) await purgePrefix(admin, bucket, folder);
  for (let i = 0; i < files.length; i += PAGE) {
    await admin.storage.from(bucket).remove(files.slice(i, i + PAGE));
  }
}
