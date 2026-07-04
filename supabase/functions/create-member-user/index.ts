// Supabase Edge Function: create-member-user
// Called by SupabaseRepository.createMemberAuthAccount() in the Flutter app.
// Only an authenticated admin can invoke this function.
// Creates a Supabase Auth user with role 'member' (or 'reseller') linked to a members table record.

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
    member_id: number;
    member_name?: string;
    role?: string; // "member" (default) or "reseller"
  };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { email, password, member_id, member_name, role } = body;
  if (!email || !password || member_id == null) {
    return new Response(
      JSON.stringify({ error: "email, password, and member_id are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  // ── 3. Create auth user with service_role key ────────────────────
  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SERVICE_ROLE_KEY")!,
  );

  const displayName = member_name || email.split("@")[0];
  const profileRole = role || "member";

  const { data: newUser, error: createError } =
    await serviceClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { username: displayName, member_id: member_id },
    });

  if (createError) {
    return new Response(JSON.stringify({ error: createError.message }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // ── 4. Upsert profile row with member_id link ──────────────────
  const { error: profileError } = await serviceClient
    .from("profiles")
    .upsert({
      id: newUser.user.id,
      username: displayName,
      email: email,
      role: profileRole,
      member_id: member_id,
    });

  if (profileError) {
    console.error("Profile upsert failed:", profileError.message);
  }

  // ── 5. Update the members row with the email ────────────────────
  const { error: memberError } = await serviceClient
    .from("members")
    .update({ email: email })
    .eq("id", member_id);

  if (memberError) {
    console.error("Member email update failed:", memberError.message);
  }

  return new Response(
    JSON.stringify({
      success: true,
      id: newUser.user.id,
      email: email,
      password: password,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
