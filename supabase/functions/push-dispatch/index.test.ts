// Tests for the push dispatcher (SA-NOT-001). Run: deno test supabase/functions/push-dispatch/
// No network: fetch is replaced by a fake Supabase / Google / FCM. The RSA key is generated per
// run, so no credential is stored in the repository.
import { dispatch } from "./index.ts";

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

async function throwawayServiceAccount(): Promise<string> {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let bin = "";
  for (const b of der) bin += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin)}\n-----END PRIVATE KEY-----\n`;
  return JSON.stringify({ project_id: "livedrop-test", client_email: "dispatcher@livedrop-test.iam.gserviceaccount.com", private_key: pem });
}

interface Call {
  url: string;
  body: unknown;
}

function fakeFetch(batch: unknown[], fcm: (token: string) => Response) {
  const calls: Call[] = [];
  const fn = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const raw = init?.body;
    const body = typeof raw === "string" ? (raw.startsWith("{") || raw.startsWith("[") ? JSON.parse(raw) : raw) : raw;
    calls.push({ url, body });
    if (url.endsWith("/rpc/claim_push_batch")) return new Response(JSON.stringify(batch), { status: 200 });
    if (url.endsWith("/rpc/complete_push")) return new Response(null, { status: 204 });
    if (url === "https://oauth2.googleapis.com/token") return new Response(JSON.stringify({ access_token: "ya29.test" }), { status: 200 });
    if (url.includes("fcm.googleapis.com")) {
      const token = (body as { message: { token: string } }).message.token;
      return fcm(token);
    }
    return new Response("unexpected", { status: 500 });
  }) as typeof fetch;
  return { fn, calls };
}

const env = (sa: string | undefined) => ({ supabaseUrl: "https://x.supabase.co", serviceRoleKey: "service-role-test", serviceAccountJson: sa });

Deno.test("without the FCM secret it answers 503 and claims nothing", async () => {
  const { fn, calls } = fakeFetch([], () => new Response("{}"));
  const r = await dispatch(env(undefined), fn);
  assert(r.status === 503, `status ${r.status}`);
  assert(calls.length === 0, "no call expected");
});

Deno.test("sends each claimed message to every device, completes it, and drops unregistered tokens", async () => {
  const sa = await throwawayServiceAccount();
  const batch = [
    { id: 1, kind: "payment_claim", title: "Payment to check for #LD-1", body: "₹1580 claimed.", data: { order_id: "o1", late: false }, tokens: ["good-token", "dead-token"] },
    { id: 2, kind: "new_order", title: "New order #LD-2", body: "₹500 reserved.", data: { order_id: "o2" }, tokens: [] },
  ];
  const { fn, calls } = fakeFetch(batch, (token) =>
    token === "dead-token"
      ? new Response(JSON.stringify({ error: { status: "NOT_FOUND", details: [{ errorCode: "UNREGISTERED" }] } }), { status: 404 })
      : new Response(JSON.stringify({ name: "projects/livedrop-test/messages/1" }), { status: 200 })
  );
  const r = await dispatch(env(sa), fn);
  assert(r.status === 200, `status ${r.status}`);
  assert(r.body.claimed === 2 && r.body.sent === 1, JSON.stringify(r.body));

  const fcmCalls = calls.filter((c) => c.url.includes("fcm.googleapis.com"));
  assert(fcmCalls.length === 2, `fcm calls ${fcmCalls.length}`);
  assert(fcmCalls[0].url === "https://fcm.googleapis.com/v1/projects/livedrop-test/messages:send", fcmCalls[0].url);
  const msg = (fcmCalls[0].body as { message: Record<string, any> }).message;
  assert(msg.notification.title === "Payment to check for #LD-1", "title");
  assert(msg.data.order_id === "o1" && msg.data.late === "false" && msg.data.kind === "payment_claim", JSON.stringify(msg.data));
  assert(msg.android.notification.channel_id === "livedrop_seller_alerts", "channel");

  const completes = calls.filter((c) => c.url.endsWith("/rpc/complete_push")).map((c) => c.body as Record<string, unknown>);
  assert(completes.length === 2, `completes ${completes.length}`);
  assert(completes[0].p_id === 1 && completes[0].p_sent === true, JSON.stringify(completes[0]));
  assert(JSON.stringify(completes[0].p_dead_tokens) === JSON.stringify(["dead-token"]), "dead token reported");
  assert(completes[1].p_id === 2 && completes[1].p_sent === true, "a message with no device is finished");

  const tokenCall = calls.find((c) => c.url === "https://oauth2.googleapis.com/token");
  assert(tokenCall && String(tokenCall.body).includes("jwt-bearer"), "Google token requested with a signed JWT");
});

Deno.test("a temporary FCM failure leaves the message for a retry", async () => {
  const sa = await throwawayServiceAccount();
  const batch = [{ id: 7, kind: "new_order", title: "t", body: "b", data: {}, tokens: ["tok"] }];
  const { fn, calls } = fakeFetch(batch, () => new Response("unavailable", { status: 503 }));
  const r = await dispatch(env(sa), fn);
  assert(r.status === 200, `status ${r.status}`);
  const complete = calls.find((c) => c.url.endsWith("/rpc/complete_push"))!.body as Record<string, unknown>;
  assert(complete.p_sent === false && String(complete.p_error).startsWith("503"), JSON.stringify(complete));
});
