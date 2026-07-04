// PG Management — `invite` Edge Function.
//
// Called by an owner when adding a tenant. Creates the tenant's login with a
// temporary password (returned to the owner to share) and links the email to
// the owner's workspace. If the email already has an account, it is linked
// without touching its password.
//
// Deploy (Supabase dashboard): Edge Functions → Deploy new function →
// name it exactly `invite` → paste this file → Deploy.
// No extra secrets needed (uses the built-in service role).

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function tempPassword(): string {
  // Unambiguous characters only — this gets retyped from a phone screen.
  const chars = "abcdefghjkmnpqrstuvwxyzACDEFGHJKLMNPQRSTUVWXYZ23456789";
  const random = crypto.getRandomValues(new Uint8Array(10));
  let out = "";
  for (const byte of random) out += chars[byte % chars.length];
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { email, tenantId, tenantName } = await req.json();
    const address = String(email ?? "").trim().toLowerCase();
    if (!address.includes("@") || !tenantId) {
      return new Response("bad request", { status: 400, headers: corsHeaders });
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const authed = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
    );
    const { data: userData } = await authed.auth.getUser();
    const caller = userData?.user;
    if (!caller) return new Response("unauthorized", { status: 401, headers: corsHeaders });

    // Try to create the tenant's account with a one-time password. If the
    // email is already registered we only link it — never reset a password
    // the owner doesn't control.
    let password: string | null = tempPassword();
    let existing = false;
    const { error: createError } = await admin.auth.admin.createUser({
      email: address,
      password,
      email_confirm: true,
      user_metadata: {
        role: "tenant",
        full_name: tenantName ?? "",
        must_change_password: true,
      },
    });
    if (createError) {
      password = null;
      existing = true;
    }

    const { error: memberError } = await admin.from("members").upsert({
      owner_id: caller.id,
      member_email: address,
      tenant_id: tenantId,
    }, { onConflict: "owner_id,member_email" });
    if (memberError) {
      return new Response(`membership failed: ${memberError.message}`, { status: 500, headers: corsHeaders });
    }

    return Response.json({ tempPassword: password, existing }, { headers: corsHeaders });
  } catch (e) {
    return new Response(`error: ${e}`, { status: 500, headers: corsHeaders });
  }
});
