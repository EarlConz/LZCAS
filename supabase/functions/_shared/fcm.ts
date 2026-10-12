// Shared by the push functions: checking the database's shared secret,
// and sending through Firebase Cloud Messaging (HTTP v1).
//
// announcement-push uses this. order-push still carries its own copy of
// the same code (written first); move it here the next time it changes.

// Compared in constant time: a plain === leaks, through timing, how much
// of a guessed secret was right.
export const sameSecret = (a: string, b: string) => {
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

export type ServiceAccount = { project_id: string; client_email: string; private_key: string };

let cachedToken: { value: string; expires: number } | null = null;

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

const b64urlText = (text: string) => b64url(new TextEncoder().encode(text));

export async function firebaseToken(sa: ServiceAccount): Promise<string> {
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

/** The service account from FIREBASE_SERVICE_ACCOUNT, or null if unset or not JSON. */
export function serviceAccount(fn: string): ServiceAccount | null {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) {
    console.error(`${fn}: FIREBASE_SERVICE_ACCOUNT is not set`);
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch {
    console.error(`${fn}: FIREBASE_SERVICE_ACCOUNT is not valid JSON`);
    return null;
  }
}

/**
 * Sends one message to each token. Returns how many went out, and the
 * tokens Firebase says are gone for good (the app was uninstalled or its
 * data cleared), for the caller to delete.
 */
export async function sendEach(
  fn: string,
  account: ServiceAccount,
  accessToken: string,
  tokens: string[],
  message: Record<string, unknown>,
): Promise<{ sent: number; dead: string[] }> {
  let sent = 0;
  const dead: string[] = [];
  for (const token of tokens) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ message: { ...message, token } }),
      },
    );
    if (res.ok) {
      sent++;
      continue;
    }
    const text = await res.text();
    if (res.status === 404 || text.includes("UNREGISTERED")) {
      dead.push(token);
    } else {
      console.error(`${fn}: FCM ${res.status}: ${text}`);
    }
  }
  return { sent, dead };
}
