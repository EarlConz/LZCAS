// Supabase Edge Function: order-push
//
// Sends a push notification (Firebase Cloud Messaging) about one delivery
// order to the people who need to hear about it, so the alert reaches a
// phone whose app is closed. The in-app alerts
// (lib/services/delivery_notification_service.dart) cover an open app; the
// rules for who hears what are the same in both places, so keep them in
// step.
//
// Called by: the database only. Migration v58 puts a trigger on `orders`
// that queues a call here (pg_net) when an order's status or rider
// changes. Deployed with --no-verify-jwt, because the caller is the
// database, not a signed-in user; it proves itself with the shared secret
// instead.
//
// Secrets:
//   PUSH_WEBHOOK_SECRET       the same value as the Vault secret
//                             'order_push_secret'
//   FIREBASE_SERVICE_ACCOUNT  the Firebase service-account JSON, whole
//   SERVICE_ROLE_KEY          reads orders, profiles and push_tokens
//
// Body (from the trigger):
//   { order_id, type: 'insert'|'update', old_status, old_delivery_id, actor }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// The statuses, as the database spells them.
const S = {
  placed: "Order Placed",
  pricing: "Cashier Pricing & Negotiating",
  countered: "Member Negotiating",
  agreed: "Agreed",
  assigned: "Assigned",
  pickedUp: "Picked Up",
  delivered: "Delivered",
  completed: "Completed",
  cancelled: "Cancelled",
} as const;

const ON_THE_ROAD = new Set<string>([S.assigned, S.pickedUp, S.delivered]);

type OrderRow = {
  id: string;
  status: string;
  member_id: number | null;
  cashier_id: string | null;
  delivery_id: string | null;
  cancel_reason: string | null;
  payment_status: string | null;
};

type Push = { to: string[]; title: string; body: string };

// Compared in constant time: a plain === leaks, through timing, how much
// of a guessed secret was right.
const sameSecret = (a: string, b: string) => {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
};

// ── Firebase access token ──────────────────────────────────────────
// FCM's HTTP v1 API takes an OAuth token minted from the service account:
// sign a JWT with its private key, trade it at Google's token endpoint.
// Kept for the life of this function instance (tokens last an hour).

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

let cachedToken: { value: string; expires: number } | null = null;

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

const b64urlText = (text: string) => b64url(new TextEncoder().encode(text));

async function firebaseToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expires - 60 > now) return cachedToken.value;

  const pem = sa.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const unsigned =
    b64urlText(JSON.stringify({ alg: "RS256", typ: "JWT" })) +
    "." +
    b64urlText(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(unsigned),
    ),
  );

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${b64url(signature)}`,
    }),
  });
  if (!res.ok) {
    throw new Error(`Google token exchange failed: ${res.status} ${await res.text()}`);
  }
  const body = await res.json();
  cachedToken = { value: body.access_token, expires: now + (body.expires_in ?? 3600) };
  return cachedToken.value;
}

// ── Who hears what ─────────────────────────────────────────────────
// Mirrors delivery_notification_service.dart. Each entry is one message to
// a set of accounts; resolving accounts to phones happens afterwards.

async function decide(
  service: ReturnType<typeof createClient>,
  order: OrderRow,
  type: string,
  before: string | null,
  oldRider: string | null,
): Promise<Push[]> {
  const ref = `Order ${order.id.split("-")[0].toUpperCase()}`;
  const status = order.status;
  const pushes: Push[] = [];

  const idsWhere = async (column: string, value: unknown) => {
    const { data } = await service.from("profiles").select("id").eq(column, value);
    return (data ?? []).map((r: { id: string }) => r.id);
  };
  const admins = () => idsWhere("role", "admin");

  // ── Cashiers and admins ──
  // The cashier holding the order, or every cashier while nobody does.
  const staff = async () => [
    ...(order.cashier_id ? [order.cashier_id] : await idsWhere("role", "cashier")),
    ...(await admins()),
  ];
  if (type === "insert" && status === S.placed) {
    pushes.push({ to: await staff(), title: "New delivery order", body: "A member just placed an order." });
  } else if (status === S.countered && before !== S.countered) {
    pushes.push({ to: await staff(), title: "Delivery counter-offer", body: `${ref}: the member countered the fee.` });
  } else if (status === S.agreed && before === S.pricing) {
    pushes.push({ to: await staff(), title: "Ready to dispatch", body: `${ref}: the member agreed to the price.` });
  } else if (status === S.cancelled && before !== null && ON_THE_ROAD.has(before)) {
    const why = (order.cancel_reason ?? "").trim();
    pushes.push({
      to: await staff(),
      title: "Delivery cancelled",
      body: `${ref} was cancelled while with the rider${why ? ` (${why})` : ""}. The goods come back to the store.`,
    });
  }

  // ── The member ──
  if (order.member_id != null && status !== before) {
    const member = await idsWhere("member_id", order.member_id);
    let rider = "A rider";
    if (status === S.assigned && order.delivery_id) {
      const { data } = await service
        .from("profiles").select("username").eq("id", order.delivery_id).maybeSingle();
      if (data?.username) rider = data.username;
    }
    const say = (title: string, body: string) => pushes.push({ to: member, title, body });
    if (status === S.pricing) {
      say("Order priced", "The cashier sent your item prices and delivery quote.");
    } else if (status === S.agreed && before === S.countered) {
      say("Delivery fee accepted", "The cashier accepted your offer. Open the app to choose how to pay.");
    } else if (status === S.assigned) {
      say("Rider assigned", `${rider} will bring your order.`);
    } else if (status === S.pickedUp) {
      say("On the way", "Your order has left the store.");
    } else if (status === S.delivered) {
      say("Delivered", 'Your order was handed over. Open the app and tap "Yes, I received it".');
    } else if (status === S.cancelled) {
      const why = (order.cancel_reason ?? "").trim();
      say(
        "Order cancelled",
        (why ? `Your order was cancelled: ${why}.` : "Your order was cancelled.") +
          (order.payment_status === "refunded" ? " Your payment was returned to your funds." : ""),
      );
    }
  }

  // ── Riders ──
  const riderChanged = type === "update" && oldRider !== order.delivery_id;
  if (order.delivery_id) {
    const to = [order.delivery_id];
    if (status === S.assigned && (before !== S.assigned || riderChanged)) {
      pushes.push({ to, title: "New delivery", body: `${ref} was assigned to you.` });
    } else if (status === S.cancelled && before !== S.cancelled) {
      pushes.push({ to, title: "Delivery cancelled", body: `${ref} was cancelled.` });
    } else if (status === S.completed && before !== S.completed) {
      pushes.push({ to, title: "Delivery complete", body: `${ref} is done.` });
    }
  }
  if (riderChanged && oldRider) {
    pushes.push({ to: [oldRider], title: "Delivery reassigned", body: `${ref} was given to another rider.` });
  }

  return pushes;
}

// ── Entry point ────────────────────────────────────────────────────

serve(async (req: Request) => {
  const expected = Deno.env.get("PUSH_WEBHOOK_SECRET");
  const given = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!expected || !sameSecret(given, expected)) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: {
    order_id?: string;
    type?: string;
    old_status?: string | null;
    old_delivery_id?: string | null;
    actor?: string | null;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (!body.order_id) return json({ error: "order_id is required" }, 400);

  const rawAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!rawAccount) {
    console.error("order-push: FIREBASE_SERVICE_ACCOUNT is not set");
    return json({ error: "Push is not configured" }, 503);
  }
  let account: ServiceAccount;
  try {
    account = JSON.parse(rawAccount);
  } catch {
    console.error("order-push: FIREBASE_SERVICE_ACCOUNT is not valid JSON");
    return json({ error: "Push is not configured" }, 503);
  }

  const service = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SERVICE_ROLE_KEY")!,
  );

  const { data: order } = await service
    .from("orders")
    .select("id, status, member_id, cashier_id, delivery_id, cancel_reason, payment_status")
    .eq("id", body.order_id)
    .single<OrderRow>();
  if (!order) return json({ error: "Order not found" }, 404);

  const pushes = await decide(
    service,
    order,
    body.type ?? "update",
    body.old_status ?? null,
    body.old_delivery_id ?? null,
  );

  // Whoever made the change already knows. Everyone else, once per push.
  const users = new Set<string>();
  for (const p of pushes) {
    p.to = [...new Set(p.to)].filter((id) => id !== body.actor);
    p.to.forEach((id) => users.add(id));
  }
  if (users.size === 0) return json({ sent: 0 });

  const { data: tokens } = await service
    .from("push_tokens")
    .select("token, user_id")
    .in("user_id", [...users]);
  if (!tokens || tokens.length === 0) return json({ sent: 0 });

  let accessToken: string;
  try {
    accessToken = await firebaseToken(account);
  } catch (e) {
    console.error("order-push:", (e as Error).message);
    return json({ error: "Could not reach Firebase" }, 502);
  }

  let sent = 0;
  const dead: string[] = [];
  for (const p of pushes) {
    for (const t of tokens.filter((t: { user_id: string }) => p.to.includes(t.user_id))) {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: t.token,
              notification: { title: p.title, body: p.body },
              data: { order_id: order.id },
              android: {
                priority: "HIGH",
                notification: {
                  // Created by the app with high importance: sound and a
                  // heads-up banner. Must match push_service.dart.
                  channel_id: "deliveries",
                  sound: "default",
                  // A newer alert about the same order replaces the older.
                  tag: `order_${order.id}`,
                },
              },
            },
          }),
        },
      );
      if (res.ok) {
        sent++;
        continue;
      }
      const text = await res.text();
      // The app was uninstalled or its data cleared: the token is gone
      // for good, so stop sending to it.
      if (res.status === 404 || text.includes("UNREGISTERED")) {
        dead.push(t.token);
      } else {
        console.error(`order-push: FCM ${res.status}: ${text}`);
      }
    }
  }

  if (dead.length > 0) {
    await service.from("push_tokens").delete().in("token", dead);
  }
  return json({ sent, removed: dead.length });
});
