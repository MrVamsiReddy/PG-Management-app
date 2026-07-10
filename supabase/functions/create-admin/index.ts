import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const WINDOW_MS = 15 * 60 * 1000;
const MAX_FAILURES = 5;

function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "content-type": "application/json" } });

  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";

    const since = new Date(Date.now() - WINDOW_MS).toISOString();
    const { count } = await admin.from("admin_setup_attempts")
      .select("id", { count: "exact", head: true })
      .eq("ip", ip).eq("success", false).gte("created_at", since);
    if ((count ?? 0) >= MAX_FAILURES) return json({ error: "code:rate_limited" }, 429);

    const { fullName, email, password, setupKey } = await req.json().catch(() => ({}));
    const fail = async (code: string, status = 400) => {
      await admin.from("admin_setup_attempts").insert({ ip, email: email ?? null, success: false });
      return json({ error: code }, status);
    };

    if (!email || !password || !setupKey) return fail("code:missing_fields");
    if (String(password).length < 8) return fail("code:weak_password");

    const expiresAt = Deno.env.get("ADMIN_SETUP_KEY_EXPIRES_AT");
    if (expiresAt && Date.now() > Date.parse(expiresAt)) return fail("code:key_expired", 403);

    const current = Deno.env.get("ADMIN_SETUP_KEY") ?? "";
    const previous = Deno.env.get("ADMIN_SETUP_KEY_PREVIOUS") ?? "";
    const ok = (current.length > 0 && timingSafeEqual(String(setupKey), current)) ||
      (previous.length > 0 && timingSafeEqual(String(setupKey), previous));
    if (!ok) return fail("code:invalid_key", 403);

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName ?? "", role: "admin", platform_admin: true, must_change_password: false },
    });
    if (createError || !created?.user) return fail("code:create_failed", 400);

    await admin.from("profiles").upsert({ id: created.user.id, role: "admin", platform_admin: true, full_name: fullName ?? "" });
    await admin.from("admin_setup_attempts").insert({ ip, email, success: true });
    await admin.from("audit_logs").insert({ customer_id: null, actor_user_id: created.user.id, actor_role: "admin", action: "admin_created", entity_type: "user", entity_id: created.user.id, after_json: { email }, ip, user_agent: req.headers.get("user-agent") });
    return json({ ok: true });
  } catch (_e) {
    return json({ error: "code:server_error" }, 500);
  }
});
