// PG Management — `invite` Edge Function (roadmap Prompt 7).
//
// All tenant onboarding goes through here; tenants can never self-register.
// Actions (POST body `action`):
//   create   (owner)  — create the tenant's login with a temporary password,
//                       link it to the workspace, issue a one-time invite
//                       token. Supersedes any previous pending invite.
//   resend   (owner)  — same as create for an already-invited tenant; the
//                       temporary password is regenerated only while the
//                       tenant has not yet set their own password.
//   revoke   (owner)  — cancel the pending invite; a never-used temporary
//                       password is scrambled so shared credentials die.
//   validate (tenant) — called at first sign-in: reports whether the invite
//                       is still pending/accepted, or expired/revoked.
//   accept   (tenant) — consume the one-time invite after the tenant sets
//                       their own password. Only a pending, unexpired invite
//                       can be accepted, exactly once.
//
// Security: the temporary password is returned to the owner exactly once and
// is NEVER logged or stored. Errors are returned as `code:*` strings the app
// maps to localized text.
//
// Deploy (Supabase dashboard): Edge Functions → `invite` → paste → Deploy.
// Run supabase/006_invites.sql first. Optional secrets: GMAIL_USER +
// GMAIL_APP_PASSWORD (Google App Password, needs 2-Step Verification) —
// with them, create/resend deliver the invite email directly via Gmail SMTP
// (localized en/hi/te) and return `emailSent: true`; without them the app
// falls back to the share sheet.

import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const appWebUrl = "https://mrvamsireddy.github.io/PG-Management-app/";
const apkDownloadUrl =
  "https://github.com/MrVamsiReddy/PG-Management-app/releases/latest/download/PG-Management-Tenant.apk";

type InviteMail = {
  subject: (pg: string) => string;
  body: (p: {
    name: string;
    pg: string;
    email: string;
    tempPassword: string | null;
    inviteLink: string;
    expiresAt: string;
  }) => string;
};

// Reusable invite templates — mirror lib/src/invite_message.dart. The
// temporary password appears only in this one email and is never logged.
const inviteMails: Record<string, InviteMail> = {
  en: {
    subject: (pg) => `Your ${pg} resident account`,
    body: ({ name, pg, email, tempPassword, inviteLink, expiresAt }) =>
      `Hi ${name.split(" ")[0]}! Your room at ${pg} is now on PG Management.\n\n` +
      `Download the app (Android): ${apkDownloadUrl}\n` +
      `Or sign in on the web: ${appWebUrl}\n` +
      `Your invite link: ${inviteLink}\n\n` +
      (tempPassword
        ? `Sign in with:\nEmail: ${email}\nTemporary password: ${tempPassword}\n\n` +
          `You will be asked to set your own password the first time you sign in. ` +
          `The temporary password stops working after that.\n\n`
        : `Sign in with your existing password using this email: ${email}\n\n`) +
      `This invite expires on ${expiresAt}.\n\n— ${pg}, via PG Management`,
  },
  hi: {
    subject: (pg) => `आपका ${pg} निवासी खाता`,
    body: ({ name, pg, email, tempPassword, inviteLink, expiresAt }) =>
      `नमस्ते ${name.split(" ")[0]}! ${pg} में आपका कमरा अब PG Management पर है।\n\n` +
      `ऐप डाउनलोड करें (Android): ${apkDownloadUrl}\n` +
      `या वेब पर साइन इन करें: ${appWebUrl}\n` +
      `आपका निमंत्रण लिंक: ${inviteLink}\n\n` +
      (tempPassword
        ? `इनसे साइन इन करें:\nईमेल: ${email}\nअस्थायी पासवर्ड: ${tempPassword}\n\n` +
          `पहली बार साइन इन करने पर आपसे अपना पासवर्ड सेट करने को कहा जाएगा। ` +
          `उसके बाद अस्थायी पासवर्ड काम करना बंद कर देगा।\n\n`
        : `इस ईमेल के साथ अपने मौजूदा पासवर्ड से साइन इन करें: ${email}\n\n`) +
      `यह निमंत्रण ${expiresAt} को समाप्त हो जाएगा।\n\n— ${pg}, PG Management के माध्यम से`,
  },
  te: {
    subject: (pg) => `మీ ${pg} నివాసి ఖాతా`,
    body: ({ name, pg, email, tempPassword, inviteLink, expiresAt }) =>
      `నమస్తే ${name.split(" ")[0]}! ${pg}లో మీ గది ఇప్పుడు PG Managementలో ఉంది.\n\n` +
      `యాప్ డౌన్‌లోడ్ చేయండి (Android): ${apkDownloadUrl}\n` +
      `లేదా వెబ్‌లో సైన్ ఇన్ చేయండి: ${appWebUrl}\n` +
      `మీ ఆహ్వాన లింక్: ${inviteLink}\n\n` +
      (tempPassword
        ? `వీటితో సైన్ ఇన్ చేయండి:\nఇమెయిల్: ${email}\nతాత్కాలిక పాస్‌వర్డ్: ${tempPassword}\n\n` +
          `మొదటిసారి సైన్ ఇన్ చేసినప్పుడు మీ స్వంత పాస్‌వర్డ్ సెట్ చేయమని అడగబడుతుంది. ` +
          `ఆ తర్వాత తాత్కాలిక పాస్‌వర్డ్ పనిచేయదు.\n\n`
        : `ఈ ఇమెయిల్‌తో మీ ప్రస్తుత పాస్‌వర్డ్ ఉపయోగించి సైన్ ఇన్ చేయండి: ${email}\n\n`) +
      `ఈ ఆహ్వానం ${expiresAt}న గడువు ముగుస్తుంది.\n\n— ${pg}, PG Management ద్వారా`,
  },
};

// Best-effort transactional email via Gmail SMTP; returns delivery success.
async function sendMail(to: string, subject: string, text: string): Promise<boolean> {
  const user = Deno.env.get("GMAIL_USER");
  const pass = Deno.env.get("GMAIL_APP_PASSWORD");
  if (!user || !pass) return false;
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
      to,
      subject,
      content: text,
    });
    return true;
  } catch (_e) {
    return false;
  } finally {
    try {
      await client.close();
    } catch (_e) { /* already closed */ }
  }
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });

function tempPassword(length = 10): string {
  // Unambiguous characters only — this gets retyped from a phone screen.
  const chars = "abcdefghjkmnpqrstuvwxyzACDEFGHJKLMNPQRSTUVWXYZ23456789";
  const random = crypto.getRandomValues(new Uint8Array(length));
  let out = "";
  for (const byte of random) out += chars[byte % chars.length];
  return out;
}

type InviteRow = {
  id: string;
  user_id: string | null;
  email: string;
  status: string;
  expires_at: string;
};

Deno.serve(async (req) => {
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

    const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || null;
    const ua = req.headers.get("user-agent");
    const audit = (action: string, customerId: string | null, entityId: string, after?: unknown) =>
      admin.from("audit_logs").insert({
        customer_id: customerId, actor_user_id: caller.id, actor_role: "owner",
        action, entity_type: "tenant", entity_id: entityId, after_json: after ?? null, ip, user_agent: ua,
      });

    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "create");

    // ---- Tenant-side actions -----------------------------------------------

    if (action === "validate" || action === "accept") {
      const callerEmail = (caller.email ?? "").toLowerCase();
      let invite: InviteRow | null = null;
      if (body.token) {
        const { data } = await admin.from("invites")
          .select("id, user_id, email, status, expires_at")
          .eq("token", String(body.token)).maybeSingle();
        // A token belongs to exactly one email — never honour someone else's.
        if (data && data.email !== callerEmail) return json({ error: "code:unauthorized" }, 403);
        invite = data;
      } else {
        const { data } = await admin.from("invites")
          .select("id, user_id, email, status, expires_at")
          .eq("email", callerEmail)
          .order("created_at", { ascending: false })
          .limit(1).maybeSingle();
        invite = data;
      }
      if (!invite) return json({ ok: true, status: "none" });

      if (invite.status === "pending" && Date.parse(invite.expires_at) < Date.now()) {
        await admin.from("invites")
          .update({ status: "expired" })
          .eq("id", invite.id).eq("status", "pending");
        invite.status = "expired";
      }
      if (invite.status === "expired") return json({ error: "code:invite_expired" }, 403);
      if (invite.status === "revoked" || invite.status === "resent") {
        return json({ error: "code:invite_revoked" }, 403);
      }
      if (invite.status === "accepted") {
        // validate: an accepted invite is a completed onboarding — fine.
        // accept: the one-time token cannot be consumed twice.
        return action === "validate"
          ? json({ ok: true, status: "accepted" })
          : json({ error: "code:invite_used" }, 409);
      }
      if (action === "validate") return json({ ok: true, status: "pending" });

      // Single-use consumption: only the pending → accepted transition exists,
      // and the status guard makes a concurrent double-accept impossible.
      const { data: consumed } = await admin.from("invites")
        .update({ status: "accepted", accepted_at: new Date().toISOString() })
        .eq("id", invite.id).eq("status", "pending")
        .select("id");
      if (!consumed || consumed.length === 0) return json({ error: "code:invite_used" }, 409);
      return json({ ok: true, status: "accepted" });
    }

    // ---- Owner-side actions ------------------------------------------------

    const tenantId = String(body.tenantId ?? "");
    if (!tenantId) return json({ error: "code:missing_fields" }, 400);

    if (action === "revoke") {
      const { data: revoked } = await admin.from("invites")
        .update({ status: "revoked", revoked_at: new Date().toISOString() })
        .eq("owner_id", caller.id).eq("tenant_id", tenantId).eq("status", "pending")
        .select("user_id");
      if (!revoked || revoked.length === 0) return json({ error: "code:invite_not_found" }, 404);
      // Kill the shared temporary password — but never touch a password the
      // tenant already set themselves.
      for (const row of revoked) {
        if (!row.user_id) continue;
        const { data: got } = await admin.auth.admin.getUserById(row.user_id);
        if (got?.user?.user_metadata?.must_change_password === true) {
          await admin.auth.admin.updateUserById(row.user_id, { password: tempPassword(32) });
        }
      }
      const { data: rp } = await admin.from("profiles").select("customer_id").eq("id", caller.id).maybeSingle();
      await audit("tenant_invite_revoked", rp?.customer_id ?? null, tenantId);
      return json({ ok: true, status: "revoked" });
    }

    if (action !== "create" && action !== "resend") {
      return json({ error: "code:missing_fields" }, 400);
    }

    const address = String(body.email ?? "").trim().toLowerCase();
    if (!address.includes("@")) return json({ error: "code:missing_fields" }, 400);
    const tenantName = String(body.tenantName ?? "");
    const pgId = String(body.pgId ?? "");
    const roomId = String(body.roomId ?? "");
    const bedLabel = String(body.bedLabel ?? "");

    // The inviting owner's resolved SaaS customer, when one exists.
    const { data: prof } = await admin.from("profiles")
      .select("customer_id").eq("id", caller.id).maybeSingle();
    const customerId = prof?.customer_id ?? null;

    // A new invite supersedes any previous pending one for this tenant.
    const { data: superseded } = await admin.from("invites")
      .update({ status: "resent", resent_at: new Date().toISOString() })
      .eq("owner_id", caller.id).eq("tenant_id", tenantId).eq("status", "pending")
      .select("user_id");

    // Create the tenant's account with a one-time password. If the email is
    // already registered we regenerate the temporary password only while the
    // tenant has never set their own — otherwise we just (re)link the account.
    let password: string | null = tempPassword();
    let existing = false;
    let userId: string | null = null;
    const metadata = {
      role: "tenant",
      full_name: tenantName,
      must_change_password: true,
      customer_id: customerId,
      tenant_id: tenantId,
      pg_id: pgId,
      room_id: roomId,
      bed_id: bedLabel,
    };
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email: address,
      password,
      email_confirm: true,
      user_metadata: metadata,
    });
    if (createError || !created?.user) {
      existing = true;
      password = null;
      userId = (superseded ?? []).find((r) => r.user_id)?.user_id ?? null;
      if (userId) {
        const { data: got } = await admin.auth.admin.getUserById(userId);
        if (got?.user?.user_metadata?.must_change_password === true) {
          password = tempPassword();
          await admin.auth.admin.updateUserById(userId, {
            password,
            user_metadata: { ...got.user.user_metadata, ...metadata },
          });
        }
      }
    } else {
      userId = created.user.id;
    }

    const { error: memberError } = await admin.from("members").upsert({
      owner_id: caller.id,
      member_email: address,
      tenant_id: tenantId,
    }, { onConflict: "owner_id,member_email" });
    if (memberError) return json({ error: "code:server_error" }, 500);

    // Give invited tenants a profiles row so the customer-status login gate
    // applies to them too (disabled customer ⇒ tenant blocked).
    if (userId && customerId) {
      await admin.from("profiles").upsert({
        id: userId,
        role: "tenant",
        customer_id: customerId,
        full_name: tenantName,
      });
    }

    const { data: invite, error: inviteError } = await admin.from("invites").insert({
      owner_id: caller.id,
      customer_id: customerId,
      user_id: userId,
      tenant_id: tenantId,
      email: address,
      pg_id: pgId,
      room_id: roomId,
      bed_label: bedLabel,
    }).select("token, expires_at").single();
    if (inviteError || !invite) return json({ error: "code:server_error" }, 500);

    await audit(action === "resend" ? "tenant_invite_resent" : "tenant_invited", customerId, tenantId, { email: address });

    const mail = inviteMails[String(body.lang ?? "en")] ?? inviteMails.en;
    const pgName = String(body.pgName ?? "").trim() || "your PG";
    const emailSent = await sendMail(
      address,
      mail.subject(pgName),
      mail.body({
        name: tenantName || "resident",
        pg: pgName,
        email: address,
        tempPassword: password,
        inviteLink: `${appWebUrl}?invite=${invite.token}`,
        expiresAt: new Date(invite.expires_at).toDateString(),
      }),
    );

    return json({
      ok: true,
      tempPassword: password,
      existing,
      token: invite.token,
      expiresAt: invite.expires_at,
      emailSent,
    });
  } catch (_e) {
    return json({ error: "code:server_error" }, 500);
  }
});
