// LiveDrop push dispatcher (SA-NOT-001, ADR-015).
//
// Sends the messages queued in public.push_outbox (migration 041) to the sellers' phones through
// Firebase Cloud Messaging HTTP v1. Woken by the database (pg_net, right after a message is queued)
// and by a pg_cron backstop every minute. Calling it only drains the queue, so it needs no caller
// authentication (verify_jwt = false in supabase/config.toml).
//
// Secrets (Supabase -> Edge Functions -> Secrets):
//   FCM_SERVICE_ACCOUNT  the Firebase service-account JSON (Project settings -> Service accounts ->
//                        Generate new private key). Set by the owner; never committed.
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY are provided by Supabase automatically.

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

interface QueuedMessage {
  id: number;
  kind: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  tokens: string[];
}

export interface DispatchEnv {
  supabaseUrl: string;
  serviceRoleKey: string;
  serviceAccountJson: string | undefined;
}

type FetchFn = typeof fetch;

function base64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function googleAccessToken(sa: ServiceAccount, fetchFn: FetchFn): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const assertion = `${header}.${claims}.${base64url(signature)}`;
  const res = await fetchFn("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`Google token request failed: ${res.status}`);
  return (await res.json()).access_token as string;
}

async function rpc<T>(env: DispatchEnv, fetchFn: FetchFn, name: string, args: Record<string, unknown>): Promise<T> {
  const res = await fetchFn(`${env.supabaseUrl}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: env.serviceRoleKey,
      Authorization: `Bearer ${env.serviceRoleKey}`,
    },
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`${name} failed: ${res.status} ${await res.text()}`);
  const text = await res.text();
  return (text ? JSON.parse(text) : null) as T;
}

// FCM data values must be strings.
function stringData(data: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(data ?? {})) out[k] = typeof v === "string" ? v : JSON.stringify(v);
  return out;
}

async function sendOne(fetchFn: FetchFn, projectId: string, accessToken: string, token: string, msg: QueuedMessage) {
  const res = await fetchFn(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
    body: JSON.stringify({
      message: {
        token,
        notification: { title: msg.title, body: msg.body },
        data: stringData({ ...msg.data, kind: msg.kind }),
        android: {
          priority: "HIGH",
          notification: { channel_id: "livedrop_seller_alerts", tag: `${msg.kind}-${msg.data?.order_id ?? msg.id}` },
        },
      },
    }),
  });
  if (res.ok) return { ok: true, dead: false, error: "" };
  const text = await res.text();
  // The app was uninstalled or the token rotated: forget it.
  const dead = res.status === 404 || text.includes("UNREGISTERED") || text.includes("registration-token-not-registered");
  return { ok: false, dead, error: `${res.status} ${text.slice(0, 200)}` };
}

/** Sends due messages; returns an HTTP status and a summary. Exported for tests. */
export async function dispatch(env: DispatchEnv, fetchFn: FetchFn = fetch): Promise<{ status: number; body: Record<string, unknown> }> {
  if (!env.serviceAccountJson || !env.supabaseUrl || !env.serviceRoleKey) {
    return { status: 503, body: { error: "FCM_SERVICE_ACCOUNT secret is not set" } };
  }
  try {
    const sa = JSON.parse(env.serviceAccountJson) as ServiceAccount;
    const batch = await rpc<QueuedMessage[]>(env, fetchFn, "claim_push_batch", { p_limit: 50 });
    if (!batch || batch.length === 0) return { status: 200, body: { claimed: 0, sent: 0 } };

    const accessToken = await googleAccessToken(sa, fetchFn);
    let sent = 0;
    for (const msg of batch) {
      const dead: string[] = [];
      const errors: string[] = [];
      let delivered = 0;
      for (const token of msg.tokens ?? []) {
        const r = await sendOne(fetchFn, sa.project_id, accessToken, token, msg);
        if (r.ok) delivered++;
        else {
          if (r.dead) dead.push(token);
          errors.push(r.error);
        }
      }
      // No device registered, or every device gone: nothing more can be done for this message.
      const finished = delivered > 0 || (msg.tokens ?? []).length === dead.length;
      await rpc(env, fetchFn, "complete_push", {
        p_id: msg.id,
        p_sent: finished,
        p_error: finished ? null : errors.join(" | "),
        p_dead_tokens: dead,
      });
      if (delivered > 0) sent++;
    }
    return { status: 200, body: { claimed: batch.length, sent } };
  } catch (e) {
    console.error("push-dispatch failed", e instanceof Error ? e.message : e);
    return { status: 500, body: { error: "dispatch failed" } };
  }
}

if (import.meta.main) {
  Deno.serve(async () => {
    const result = await dispatch({
      supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
      serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      serviceAccountJson: Deno.env.get("FCM_SERVICE_ACCOUNT"),
    });
    return new Response(JSON.stringify(result.body), {
      status: result.status,
      headers: { "Content-Type": "application/json" },
    });
  });
}
