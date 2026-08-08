// Supabase Edge Function: update-user
// Called by AuthState.updateUser() — only an authenticated admin can invoke.
// Supports: password reset, role change, username/email update.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req: Request) => {
  // ── 1. Auth check: caller must be a logged-in admin ──────────────
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Missing Authorization header" }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  const anonClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const {
    data: { user: caller },
  } = await anonClient.auth.getUser();
  if (!caller) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data: profile } = await anonClient
    .from("profiles")
    .select("role")
    .eq("id", caller.id)
    .single();

  if (profile?.role !== "admin") {
    return new Response(
      JSON.stringify({ error: "Forbidden: admin role required" }),
      { status: 403, headers: { "Content-Type": "application/json" } },
    );
  }

  // ── 2. Parse request body ────────────────────────────────────────
  let body: {
    user_id: string;
    password?: string;
    role?: string;
    username?: string;
    email?: string;
    mobile_enabled?: boolean;
  };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { user_id, password, role, username, email, mobile_enabled } = body;
  if (!user_id) {
    return new Response(
      JSON.stringify({ error: "user_id is required" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  // ── 3. Admin client with service_role key ────────────────────────
  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SERVICE_ROLE_KEY")!,
  );

  const updates: Record<string, unknown> = {};

  // Password reset (Supabase Admin API)
  if (password && password.length >= 6) {
    updates.password = password;
  }

  // Email change (must be a valid email format)
  if (email && email.includes("@")) {
    updates.email = email;
  }

  // Only call auth.admin.updateUserById if there are auth fields to update
  if (Object.keys(updates).length > 0) {
    const { error: authError } = await serviceClient.auth.admin.updateUserById(
      user_id,
      updates,
    );

    if (authError) {
      return new Response(JSON.stringify({ error: authError.message }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }
  }

  // ── 4. Update profile row (role, username, email, password) ──────
  const profileUpdates: Record<string, unknown> = {};
  if (role) profileUpdates.role = role;
  if (username) profileUpdates.username = username;
  if (email && email.includes("@")) profileUpdates.email = email;
  if (password && password.length >= 6) profileUpdates.password = password;
  // Per-account mobile-login flag (branch cashier). Explicit boolean check so
  // `false` is persisted (not skipped like a missing field).
  if (typeof mobile_enabled === "boolean") {
    profileUpdates.mobile_enabled = mobile_enabled;
  }

  if (Object.keys(profileUpdates).length > 0) {
    const { error: profileError } = await serviceClient
      .from("profiles")
      .update(profileUpdates)
      .eq("id", user_id);

    if (profileError) {
      return new Response(JSON.stringify({ error: profileError.message }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
