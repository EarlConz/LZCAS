// Supabase Edge Function: delete-user
// Called by AuthState.deleteUser() — only an authenticated admin can invoke.

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

  // ── 2. Parse request ────────────────────────────────────────────
  const { user_id } = await req.json();
  if (!user_id) {
    return new Response(JSON.stringify({ error: "user_id is required" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Prevent self-deletion
  if (user_id === caller.id) {
    return new Response(
      JSON.stringify({ error: "Cannot delete your own account" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  // ── 3. Delete user with service_role key ────────────────────────
  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SERVICE_ROLE_KEY")!,
  );

  const { error: deleteError } =
    await serviceClient.auth.admin.deleteUser(user_id);

  if (deleteError) {
    return new Response(JSON.stringify({ error: deleteError.message }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // ── 4. Clean up profile row ─────────────────────────────────────
  await serviceClient.from("profiles").delete().eq("id", user_id);

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
