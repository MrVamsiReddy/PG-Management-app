// PG Management — `remove-tenant` Edge Function.
//
// Called by the owner after they permanently remove a tenant from their PG.
// Server-side cleanup the app itself cannot do:
//   - delete the tenant's login (auth user), profiles row and push tokens
//   - delete the members link and every invite row
//   (rent records and UPI submissions are kept: they are the PG's books)
//   - email the tenant that they are no longer part of the PG and that
//     their data has been permanently deleted (English/Hindi/Telugu)
//
// Email needs the GMAIL_USER + GMAIL_APP_PASSWORD secrets (a Google App
// Password; the account needs 2-Step Verification). Without them the
// cleanup still runs and `emailSent: false` is returned so the app can
// tell the owner.
//
// Deploy (Supabase dashboard): Edge Functions → `remove-tenant` → paste →
// Deploy. Secrets: GMAIL_USER, GMAIL_APP_PASSWORD.

import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

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


const emails: Record<string, { subject: (pg: string) => string; body: (name: string, pg: string) => string }> = {
  en: {
    subject: (pg) => `You are no longer a resident of ${pg}`,
    body: (name, pg) =>
      `Hi ${name},\n\nThis is to let you know that you are no longer a part of ${pg}. ` +
      `Your account, profile and visitor records have been permanently deleted, ` +
      `and your login no longer works. The PG keeps its record of the rent you paid.\n\n` +
      `If you believe this was a mistake, please contact your PG owner directly.\n\n— ${pg}, via PG Management`,
  },
  hi: {
    subject: (pg) => `अब आप ${pg} के निवासी नहीं हैं`,
    body: (name, pg) =>
      `नमस्ते ${name},\n\nयह सूचित किया जाता है कि अब आप ${pg} का हिस्सा नहीं हैं। ` +
      `आपका खाता और आपका डेटा — प्रोफ़ाइल और विज़िटर — ` +
      `स्थायी रूप से हटा दिया गया है, और आपका लॉगिन अब काम नहीं करेगा।\n\n` +
      `यदि आपको लगता है कि यह गलती से हुआ है, तो कृपया सीधे अपने पीजी मालिक से संपर्क करें।\n\n— ${pg}, PG Management के माध्यम से`,
  },
  te: {
    subject: (pg) => `మీరు ఇకపై ${pg} నివాసి కారు`,
    body: (name, pg) =>
      `నమస్తే ${name},\n\nమీరు ఇకపై ${pg}లో భాగం కాదని తెలియజేస్తున్నాము. ` +
      `మీ ఖాతా మరియు మీ డేటా — ప్రొఫైల్ మరియు సందర్శకులు — ` +
      `శాశ్వతంగా తొలగించబడ్డాయి, మీ లాగిన్ ఇకపై పనిచేయదు.\n\n` +
      `ఇది పొరపాటున జరిగిందని మీరు భావిస్తే, దయచేసి మీ పీజీ యజమానిని నేరుగా సంప్రదించండి.\n\n— ${pg}, PG Management ద్వారా`,
  },
};

Deno.serve(async (req) => {
  const corsHeaders = corsHeadersFor(req);
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "content-type": "application/json" },
    });
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
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
    if (!caller) return json({ error: "code:unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const tenantId = String(body.tenantId ?? "");
    if (!tenantId) return json({ error: "code:missing_fields" }, 400);
    const tenantName = String(body.tenantName ?? "").trim() || "resident";
    const pgName = String(body.pgName ?? "").trim() || "your PG";
    const lang = String(body.lang ?? "en");

    // The tenant's login, when one was ever invited for this tenant record.
    const { data: member } = await admin.from("members")
      .select("member_email")
      .eq("owner_id", caller.id).eq("tenant_id", tenantId).maybeSingle();
    const { data: inviteRows } = await admin.from("invites")
      .select("user_id, email")
      .eq("owner_id", caller.id).eq("tenant_id", tenantId);
    const email: string | null =
      member?.member_email ?? (inviteRows ?? []).find((r) => r.email)?.email ?? null;
    const userId: string | null =
      (inviteRows ?? []).find((r) => r.user_id)?.user_id ?? null;

    await admin.from("invites")
      .delete().eq("owner_id", caller.id).eq("tenant_id", tenantId);
    await admin.from("members")
      .delete().eq("owner_id", caller.id).eq("tenant_id", tenantId);

    // Delete the login itself — but only a tenant account tied to this tenant
    // record, and never the caller. A shared/owner account is left alone.
    if (userId && userId !== caller.id) {
      const { data: got } = await admin.auth.admin.getUserById(userId);
      const meta = got?.user?.user_metadata ?? {};
      if (meta.role === "tenant" && meta.tenant_id === tenantId) {
        await admin.from("push_tokens").delete().eq("user_id", userId);
        await admin.from("profiles").delete().eq("id", userId);
        await admin.auth.admin.deleteUser(userId);
      }
    }

    // Farewell email — best-effort, via Gmail SMTP when secrets are set.
    let emailSent = false;
    const user = Deno.env.get("GMAIL_USER");
    const pass = Deno.env.get("GMAIL_APP_PASSWORD");
    if (email && user && pass) {
      const t = emails[lang] ?? emails.en;
      const client = new SMTPClient({
        connection: {
          hostname: "smtp.gmail.com",
          port: 465,
          tls: true,
          auth: { username: user, password: pass },
        },
      });
      try {
        await client.send({
          from: `PG Management <${user}>`,
          to: email,
          subject: t.subject(pgName),
          content: t.body(tenantName, pgName),
        });
        emailSent = true;
      } catch (_e) {
        emailSent = false;
      } finally {
        try {
          await client.close();
        } catch (_e) { /* already closed */ }
      }
    }

    const { data: prof } = await admin.from("profiles")
      .select("customer_id").eq("id", caller.id).maybeSingle();
    await admin.from("audit_logs").insert({
      customer_id: prof?.customer_id ?? null,
      actor_user_id: caller.id,
      actor_role: "owner",
      action: "tenant_removed",
      entity_type: "tenant",
      entity_id: tenantId,
      after_json: { email, login_deleted: !!userId, email_sent: emailSent },
      ip: (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || null,
      user_agent: req.headers.get("user-agent"),
    });

    return json({ ok: true, email, emailSent });
  } catch (_e) {
    return json({ error: "code:server_error" }, 500);
  }
});
