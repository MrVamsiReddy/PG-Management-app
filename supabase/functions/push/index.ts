// PG Management — `push` Edge Function.
//
// Sends an FCM notification to every registered device in a workspace
// (the owner + linked tenants), excluding the caller's own devices.
//
// Deploy (Supabase dashboard): Edge Functions → Deploy new function →
// name it exactly `push` → paste this file → Deploy.
// Secret required (Edge Functions → Secrets):
//   FIREBASE_SERVICE_ACCOUNT = contents of the Firebase service-account JSON
//   (Firebase console → Project settings → Service accounts → Generate new private key)

import { createClient } from "npm:@supabase/supabase-js@2";

const sa = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "{}");

// Browsers (the web app) preflight cross-origin calls; every response must
// carry CORS headers or the invoke fails silently on web.
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

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const raw = atob(b64);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function fcmAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)),
  );
  const jwt = `${header}.${claims}.${b64url(signature)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: `grant_type=${encodeURIComponent("urn:ietf:params:oauth:grant-type:jwt-bearer")}&assertion=${jwt}`,
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(`OAuth failed: ${JSON.stringify(json)}`);
  return json.access_token;
}

Deno.serve(async (req) => {
  const corsHeaders = corsHeadersFor(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { workspaceOwnerId, title, body, scope, tenantId, pgId } = await req.json();
    if (!workspaceOwnerId || !title) return new Response("bad request", { status: 400, headers: corsHeaders });

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Identify the caller (their devices are excluded from delivery).
    const authed = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
    );
    const { data: userData } = await authed.auth.getUser();
    const caller = userData?.user;
    if (!caller) return new Response("unauthorized", { status: 401, headers: corsHeaders });

    // The caller must belong to the workspace: owner or invited member.
    const callerEmail = (caller.email ?? "").toLowerCase();
    const isOwner = caller.id === workspaceOwnerId;
    if (!isOwner) {
      const { data: membership } = await admin.from("members").select("tenant_id")
        .eq("owner_id", workspaceOwnerId).eq("member_email", callerEmail).maybeSingle();
      if (!membership) return new Response("forbidden", { status: 403, headers: corsHeaders });
    }

    // Recipients depend on the notification's scope so banners respect the
    // same privacy as the in-app list:
    //   managers -> the owner's devices only
    //   tenant   -> the invited member whose tenant_id matches
    //   everyone -> the owner + every invited member (only the members
    //               living in `pgId` when one is given)
    // Tenants may only alert the managers; addressing other residents is an
    // owner action.
    const effectiveScope = isOwner ? scope : "managers";
    const { data: members } = await admin.from("members")
      .select("member_email, tenant_id").eq("owner_id", workspaceOwnerId);
    const allMembers = members ?? [];

    let ownerIds: string[] = [];
    let emails: string[] = [];
    if (effectiveScope === "managers") {
      ownerIds = [workspaceOwnerId];
    } else if (effectiveScope === "tenant") {
      emails = allMembers
        .filter((m: { tenant_id: string }) => m.tenant_id === tenantId)
        .map((m: { member_email: string }) => m.member_email);
    } else {
      ownerIds = [workspaceOwnerId];
      // A message for one PG reaches only the tenants living in that PG.
      let inPg: Set<string> | null = null;
      if (typeof pgId === "string" && pgId) {
        const blob = async (key: string): Promise<Record<string, unknown>[]> => {
          const { data } = await admin.from("app_data").select("data")
            .eq("owner_id", workspaceOwnerId).eq("key", key).maybeSingle();
          return Array.isArray(data?.data) ? data.data : [];
        };
        const roomIds = new Set((await blob("rooms"))
          .filter((r) => r.pgId === pgId).map((r) => String(r.id)));
        inPg = new Set((await blob("tenants"))
          .filter((t) => roomIds.has(String(t.roomId))).map((t) => String(t.id)));
      }
      emails = allMembers
        .filter((m: { tenant_id: string }) => inPg === null || inPg.has(m.tenant_id))
        .map((m: { member_email: string }) => m.member_email);
    }

    // Two plain filters, never a hand-built filter string: member emails are
    // data and must not be able to widen the query.
    type TokenRow = { token: string; user_id: string };
    const tokens: TokenRow[] = [];
    if (ownerIds.length) {
      const { data } = await admin.from("push_tokens").select("token, user_id").in("user_id", ownerIds);
      tokens.push(...(data ?? []));
    }
    if (emails.length) {
      const { data } = await admin.from("push_tokens").select("token, user_id").in("email", emails);
      tokens.push(...(data ?? []));
    }
    const seen = new Set<string>();
    const targets = tokens.filter((t) => t.user_id !== caller.id && !seen.has(t.token) && seen.add(t.token));
    if (targets.length === 0) return Response.json({ sent: 0 }, { headers: corsHeaders });

    const pushTitle = String(title).slice(0, 200);
    const pushBody = String(body ?? "").slice(0, 1000);
    const accessToken = await fcmAccessToken();
    let sent = 0;
    for (const t of targets) {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
        body: JSON.stringify({ message: { token: t.token, notification: { title: pushTitle, body: pushBody } } }),
      });
      if (res.ok) {
        sent++;
      } else if (res.status === 404 || res.status === 410) {
        await admin.from("push_tokens").delete().eq("token", t.token); // stale device
      }
    }
    return Response.json({ sent }, { headers: corsHeaders });
  } catch (e) {
    console.error("push failed", e);
    return new Response("error", { status: 500, headers: corsHeaders });
  }
});
