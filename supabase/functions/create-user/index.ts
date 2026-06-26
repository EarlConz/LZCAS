// Supabase Edge Function: create-user
// Called by AuthState.createUser() in the Flutter app.
// Only an authenticated admin can invoke this function.

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
    email: string;
    password: string;
    role: string;
    username?: string;
  };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { email, password, role, username } = body;
  if (!email || !password) {
    return new Response(
      JSON.stringify({ error: "email and password are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  // ── 3. Create auth user with service_role key ────────────────────
  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SERVICE_ROLE_KEY")!,
  );

  const { data: newUser, error: createError } =
    await serviceClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { username: username || email },
    });

  if (createError) {
    return new Response(JSON.stringify({ error: createError.message }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // ── 4. Upsert profile row with role ──────────────────────────────
  const { error: profileError } = await serviceClient
    .from("profiles")
    .upsert({
      id: newUser.user.id,
      username: username || email,
      email: email,
      role: role || "cashier",
    });

  if (profileError) {
    // Auth user was created but profile insert failed.
    // The DB trigger (handle_new_user) provides a fallback.
    console.error("Profile upsert failed:", profileError.message);
  }

  return new Response(
    JSON.stringify({ success: true, id: newUser.user.id }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
