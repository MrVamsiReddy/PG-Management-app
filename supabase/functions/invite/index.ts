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


function tempPassword(length = 10): string {
  // Unambiguous characters only — this gets retyped from a phone screen.
  const chars = "abcdefghjkmnpqrstuvwxyzACDEFGHJKLMNPQRSTUVWXYZ23456789";
  const random = crypto.getRandomValues(new Uint8Array(length));
  let out = "";
  for (const byte of random) out += chars[byte % chars.length];
  return out;
}

const MAX_INVITES_PER_HOUR = 30;

// Control characters out, length capped: names end up in an email.
function cleanText(value: unknown, max: number): string {
  return String(value ?? "").replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, max);
}

// deno-lint-ignore no-explicit-any
function hasTempPassword(user: any): boolean {
  return user?.app_metadata?.must_change_password === true ||
    user?.user_metadata?.must_change_password === true;
}

// True when the caller's session came from a password-reset (or OTP/magic)
// link in the last 15 minutes. The JWT was already verified by getUser().
function recentResetSignIn(req: Request): boolean {
  try {
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const part = token.split(".")[1] ?? "";
    const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(b64.padEnd(Math.ceil(b64.length / 4) * 4, "=")));
    const amr: { method?: string; timestamp?: number }[] = Array.isArray(payload.amr) ? payload.amr : [];
    const now = Date.now() / 1000;
    return amr.some((m) =>
      ["recovery", "otp", "magiclink"].includes(m.method ?? "") &&
      typeof m.timestamp === "number" && now - m.timestamp < 15 * 60
    );
  } catch (_e) {
    return false;
  }
}

type InviteRow = {
  id: string;
  user_id: string | null;
  email: string;
  status: string;
  expires_at: string;
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

    // Password change that clears the temporary-password flag, done with the
    // service role so it works even when the project's "secure password
    // change" auth setting is on. The caller proves it is them with either
    // the temporary password (first sign-in) or a fresh password-reset
    // sign-in (the reset-link flow). The password is never logged.
    if (action === "set-password") {
      const tempPassword = String(body.tempPassword ?? "");
      const newPassword = String(body.newPassword ?? "");
      if (newPassword.length < 6) return json({ error: "code:weak_password" }, 400);
      if (!caller.email) return json({ error: "code:temp_wrong" }, 403);
      if (tempPassword) {
        const verifier = createClient(
          Deno.env.get("SUPABASE_URL")!,
          Deno.env.get("SUPABASE_ANON_KEY")!,
        );
        const { error: pwError } = await verifier.auth.signInWithPassword({
          email: caller.email,
          password: tempPassword,
        });
        if (pwError) return json({ error: "code:temp_wrong" }, 403);
      } else if (!recentResetSignIn(req)) {
        return json({ error: "code:temp_wrong" }, 403);
      }
      // The flag that the database enforces lives in app_metadata, which only
      // the service role can write; user_metadata is kept in step for older
      // app versions.
      const { error: upError } = await admin.auth.admin.updateUserById(caller.id, {
        password: newPassword,
        user_metadata: { ...caller.user_metadata, must_change_password: false },
        app_metadata: { ...caller.app_metadata, must_change_password: false },
      });
      if (upError) return json({ error: "code:server_error" }, 500);
      return json({ ok: true });
    }

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

    // Only PG owners may invite, resend or revoke: an owner profile on an
    // enabled, unexpired customer. An account without a profile (e.g. one
    // created through open sign-up) is never an owner (016_review_fixes.sql).
    const { data: callerProfile } = await admin.from("profiles")
      .select("role, customer_id").eq("id", caller.id).maybeSingle();
    if (!callerProfile || callerProfile.role !== "owner") {
      return json({ error: "code:not_owner" }, 403);
    }
    const { data: active } = await admin.rpc("workspace_active", { p_owner: caller.id });
    if (active !== true) return json({ error: "code:not_owner" }, 403);
    const customerId: string | null = callerProfile.customer_id ?? null;

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
        if (hasTempPassword(got?.user)) {
          await admin.auth.admin.updateUserById(row.user_id, { password: tempPassword(32) });
        }
      }
      await audit("tenant_invite_revoked", customerId, tenantId);
      return json({ ok: true, status: "revoked" });
    }

    if (action !== "create" && action !== "resend") {
      return json({ error: "code:missing_fields" }, 400);
    }

    // Each invite creates a login and sends an email, so cap the rate.
    const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count: recentInvites } = await admin.from("invites")
      .select("id", { count: "exact", head: true })
      .eq("owner_id", caller.id).gte("created_at", hourAgo);
    if ((recentInvites ?? 0) >= MAX_INVITES_PER_HOUR) return json({ error: "code:rate_limited" }, 429);

    // The tenant, room and PG come from the owner's own stored data, never
    // from the request, so the email can't carry arbitrary text.
    const blob = async (key: string): Promise<Record<string, unknown>[]> => {
      const { data } = await admin.from("app_data").select("data")
        .eq("owner_id", caller.id).eq("key", key).maybeSingle();
      return Array.isArray(data?.data) ? data.data : [];
    };
    const tenant = (await blob("tenants")).find((t) => t.id === tenantId);
    if (!tenant) return json({ error: "code:tenant_not_found" }, 404);

    const address = String(body.email ?? "").trim().toLowerCase();
    if (!/^[^\s,()"\\@]+@[^\s,()"\\@]+$/.test(address)) return json({ error: "code:missing_fields" }, 400);
    const storedEmail = String(tenant.email ?? "").trim().toLowerCase();
    if (storedEmail) {
      if (storedEmail !== address) return json({ error: "code:email_mismatch" }, 400);
    } else {
      // Older tenant records have no email; only re-use one already invited.
      const { data: prior } = await admin.from("invites").select("id")
        .eq("owner_id", caller.id).eq("tenant_id", tenantId).eq("email", address)
        .limit(1).maybeSingle();
      if (!prior) return json({ error: "code:email_mismatch" }, 400);
    }

    const roomId = String(tenant.roomId ?? "");
    const room = (await blob("rooms")).find((r) => r.id === roomId);
    const pgId = String(room?.pgId ?? "");
    const pg = (await blob("pgs")).find((r) => r.id === pgId);
    const tenantName = cleanText(tenant.name, 100);
    const bedLabel = cleanText(tenant.bed, 20);
    const pgName = cleanText(pg?.name, 100) || "your PG";

    // One workspace per login: never pull a resident out of another PG, and
    // never turn another business's owner or a platform admin into a tenant.
    const { data: elsewhere } = await admin.from("members").select("owner_id")
      .eq("member_email", address).neq("owner_id", caller.id).limit(1).maybeSingle();
    if (elsewhere) return json({ error: "code:email_in_other_pg" }, 409);
    const { data: sameWorkspace } = await admin.from("members").select("tenant_id")
      .eq("owner_id", caller.id).eq("member_email", address).maybeSingle();
    if (sameWorkspace && sameWorkspace.tenant_id !== tenantId) {
      return json({ error: "code:email_in_use_tenant" }, 409);
    }
    const { data: existingId } = await admin.rpc("auth_user_id_by_email", { p_email: address });
    let existingProfile: { role: string; platform_admin: boolean } | null = null;
    if (existingId) {
      const { data: prof } = await admin.from("profiles")
        .select("role, platform_admin").eq("id", existingId).maybeSingle();
      existingProfile = prof;
      const { count: ownsData } = await admin.from("app_data")
        .select("key", { count: "exact", head: true }).eq("owner_id", existingId);
      if ((prof && (prof.platform_admin || prof.role !== "tenant")) || (ownsData ?? 0) > 0) {
        return json({ error: "code:email_is_owner" }, 409);
      }
      // Only re-link a login this workspace already invited or linked. A
      // login nobody here created could belong to someone who registered the
      // address first, and they would get this tenant's data.
      const { data: ownInvite } = await admin.from("invites").select("id")
        .eq("owner_id", caller.id).eq("user_id", existingId).limit(1).maybeSingle();
      if (!sameWorkspace && !ownInvite) return json({ error: "code:email_taken" }, 409);
    }

    // A new invite supersedes any previous pending one for this tenant.
    await admin.from("invites")
      .update({ status: "resent", resent_at: new Date().toISOString() })
      .eq("owner_id", caller.id).eq("tenant_id", tenantId).eq("status", "pending");

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
    if (!existingId) {
      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email: address,
        password,
        email_confirm: true,
        user_metadata: metadata,
        app_metadata: { must_change_password: true },
      });
      if (createError || !created?.user) return json({ error: "code:server_error" }, 500);
      userId = created.user.id;
    } else {
      existing = true;
      password = null;
      userId = existingId;
      const { data: got } = await admin.auth.admin.getUserById(existingId);
      if (got?.user && hasTempPassword(got.user)) {
        password = tempPassword();
        await admin.auth.admin.updateUserById(existingId, {
          password,
          user_metadata: { ...got.user.user_metadata, ...metadata },
          app_metadata: { ...got.user.app_metadata, must_change_password: true },
        });
      }
    }

    const { error: memberError } = await admin.from("members").upsert({
      owner_id: caller.id,
      member_email: address,
      tenant_id: tenantId,
    }, { onConflict: "owner_id,member_email" });
    if (memberError) return json({ error: "code:server_error" }, 500);

    // Give invited tenants a profiles row so the customer-status login gate
    // applies to them too (disabled customer ⇒ tenant blocked).
    if (userId && customerId && (!existingProfile || existingProfile.role === "tenant")) {
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
