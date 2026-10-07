// Supabase Edge Function: announcement-push
//
// Sends a push notification (Firebase Cloud Messaging) about one new
// announcement to everyone it is addressed to, so it reaches a phone whose
// app is closed. While the app is open, the count on the Announcements
// tab covers it (lib/services/announcement_alerts.dart), and Android does
// not show a push to an app in front.
//
// Called by: the database only. Migration v74 queues a call here (pg_net)
// once per announcement, when it goes live. Deployed with
// --no-verify-jwt, because the caller is the database, not a signed-in
// user; it proves itself with the shared secret instead.
//
// Secrets (the project's, shared with order-push):
//   PUSH_WEBHOOK_SECRET       the same value as the Vault secret
//                             'order_push_secret'
//   FIREBASE_SERVICE_ACCOUNT  the Firebase service-account JSON, whole
//   SERVICE_ROLE_KEY          reads announcements, profiles and push_tokens
//
// Body (from the database): { announcement_id }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { firebaseToken, sameSecret, sendEach, serviceAccount } from "../_shared/fcm.ts";

const FN = "announcement-push";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// Who may read each audience: the announcements_select policy (v51).
// Admins and cashiers can read every announcement, so they hear of every
// one somebody else posts.
const STAFF = ["admin", "cashier"];
const ROLES: Record<string, string[] | null> = {
  all: null, // everyone
  branches: ["branch_cashier", ...STAFF],
  members: ["member", "reseller", ...STAFF],
};

type AnnouncementRow = {
  id: number;
  title: string | null;
  body: string | null;
  audience: string | null;
  created_by: string | null;
  archived_at: string | null;
  published_at: string | null;
  ends_at: string | null;
};

// The first words of the body, or a nudge for a poster with none.
const preview = (body: string | null) => {
  const text = (body ?? "").replace(/\s+/g, " ").trim();
  if (!text) return "New announcement. Open the app to see it.";
  return text.length > 140 ? `${text.slice(0, 137).trimEnd()}...` : text;
};

serve(async (req: Request) => {
  const expected = Deno.env.get("PUSH_WEBHOOK_SECRET");
  const given = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!expected || !sameSecret(given, expected)) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: { announcement_id?: number };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (body.announcement_id == null) return json({ error: "announcement_id is required" }, 400);

  const account = serviceAccount(FN);
  if (!account) return json({ error: "Push is not configured" }, 503);

  const service = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SERVICE_ROLE_KEY")!,
  );

  const { data: a } = await service
    .from("announcements")
    .select("id, title, body, audience, created_by, archived_at, published_at, ends_at")
    .eq("id", body.announcement_id)
    .maybeSingle<AnnouncementRow>();
  if (!a) return json({ error: "Announcement not found" }, 404);

  // Taken down, or not live, between the queueing and now: say nothing.
  const now = Date.now();
  const live = !a.archived_at &&
    (!a.published_at || Date.parse(a.published_at) <= now) &&
    (!a.ends_at || Date.parse(a.ends_at) > now);
  if (!live) return json({ sent: 0, reason: "not live" });

  // The phones of the accounts it is addressed to, except the poster's.
  const roles = ROLES[a.audience ?? "all"] ?? null;
  let users: string[] | null = null;
  if (roles) {
    const { data } = await service.from("profiles").select("id").in("role", roles);
    users = (data ?? []).map((r: { id: string }) => r.id);
  }
  let query = service.from("push_tokens").select("token, user_id");
  if (users) query = query.in("user_id", users);
  const { data: rows } = await query;
  const tokens = (rows ?? [])
    .filter((t: { user_id: string }) => t.user_id !== a.created_by)
    .map((t: { token: string }) => t.token);
  if (tokens.length === 0) return json({ sent: 0 });

  let accessToken: string;
  try {
    accessToken = await firebaseToken(account);
  } catch (e) {
    console.error(`${FN}:`, (e as Error).message);
    return json({ error: "Could not reach Firebase" }, 502);
  }

  const { sent, dead } = await sendEach(FN, account, accessToken, tokens, {
    notification: { title: (a.title ?? "").trim() || "New announcement", body: preview(a.body) },
    data: { announcement_id: String(a.id) },
    android: {
      priority: "HIGH",
      notification: {
        // Created by the app (MainActivity.kt). An older app without it
        // shows the push on Android's default channel instead.
        channel_id: "announcements",
        sound: "default",
        tag: `announcement_${a.id}`,
      },
    },
  });

  if (dead.length > 0) {
    await service.from("push_tokens").delete().in("token", dead);
  }
  return json({ sent, removed: dead.length });
});
