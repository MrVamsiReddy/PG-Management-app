import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function tempPassword(): string {
  const chars = "abcdefghjkmnpqrstuvwxyzACDEFGHJKLMNPQRSTUVWXYZ23456789";
  const random = crypto.getRandomValues(new Uint8Array(12));
  let out = "";
  for (const byte of random) out += chars[byte % chars.length];
  return out;
}

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

    const { businessName, ownerName, ownerEmail, phone, plan, durationDays } =
      await req.json().catch(() => ({}));
    if (!businessName || !ownerEmail) return json({ error: "code:missing_fields" }, 400);

    // Subscription window: default 30 days from now (free plan default).
    const startsAt = new Date();
    const days = Number(durationDays) > 0 ? Number(durationDays) : 30;
    const expiresAt = new Date(startsAt.getTime() + days * 86400000);

    const { data: customer, error: custErr } = await admin.from("customers").insert({
      business_name: businessName,
      owner_name: ownerName ?? "",
      owner_email: ownerEmail,
      phone: phone ?? "",
      plan: plan ?? "free",
      starts_at: startsAt.toISOString(),
      expires_at: expiresAt.toISOString(),
    }).select("id").single();
    if (custErr || !customer) return json({ error: "code:server_error" }, 500);

    const password = tempPassword();
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email: ownerEmail,
      password,
      email_confirm: true,
      user_metadata: { full_name: ownerName ?? "", role: "owner", customer_id: customer.id, must_change_password: true },
    });
    if (createErr || !created?.user) {
      await admin.from("customers").delete().eq("id", customer.id);
      return json({ error: "code:email_in_use" }, 400);
    }

    await admin.from("profiles").upsert({ id: created.user.id, role: "owner", customer_id: customer.id, full_name: ownerName ?? "" });
    const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || null;
    const ua = req.headers.get("user-agent");
    await admin.from("audit_logs").insert([
      { customer_id: customer.id, actor_user_id: caller.id, actor_role: "admin", action: "customer_created", entity_type: "customer", entity_id: customer.id, after_json: { business_name: businessName }, ip, user_agent: ua },
      { customer_id: customer.id, actor_user_id: caller.id, actor_role: "admin", action: "owner_created", entity_type: "user", entity_id: created.user.id, after_json: { email: ownerEmail }, ip, user_agent: ua },
    ]);
    return json({ ok: true, customerId: customer.id, tempPassword: password });
  } catch (_e) {
    return json({ error: "code:server_error" }, 500);
  }
});
