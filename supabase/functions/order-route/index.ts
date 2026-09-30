// Supabase Edge Function: order-route
//
// Returns the road route from the fulfilling branch to the member for one
// delivery order, fetching it from OpenRouteService ONCE and storing it on
// the order (migration v53). Every later call — any screen, any viewer —
// is answered from the stored copy without touching the routing service.
//
// That "once" is the whole design. The free ORS tier allows about 2,000
// routes a day; a route fetched per screen would be paid for by every
// viewer and every refresh. Failures are stored as well, for the same
// reason: an order pinned somewhere no road reaches would otherwise retry
// on every view and quietly spend the allowance.
//
// Called by: the rider's order detail, and the cashier after assigning a
// rider. Allowed: staff (admin, cashier), the order's own member, and the
// rider it is assigned to.
//
// Secrets: ORS_API_KEY (the routing key — never shipped in the app),
// SERVICE_ROLE_KEY (writes the route columns, as the other functions use).
//
// Body: { "order_id": "<uuid>", "force": false }
// `force` recalculates even a stored route; staff only.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// A transient failure (rate limit, timeout) is retried, but not sooner than
// this — a burst of views must not become a burst of requests.
const RETRY_FAILED_AFTER_MS = 30 * 60 * 1000;

// How far ORS may move each point to reach a road. Its default (350 m) is
// tight for rural pins that sit in a yard or a field behind the road; 2 km
// reaches the road without jumping to the wrong side of a river. The gap it
// leaves is drawn as a dashed last stretch in the app.
const SNAP_RADIUS_M = 2000;

// ORS error codes that mean "these coordinates have no route" rather than
// "try again later": 2009 no route between the points, 2010 no routable
// point within the radius. Stored as 'unroutable' and never retried.
const UNROUTABLE_CODES = new Set([2009, 2010]);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// Five decimals is about a metre: plenty for a line on a map, and it keeps
// the stored array a fraction of the size ORS sends.
const round5 = (n: number) => Math.round(n * 1e5) / 1e5;

// For ranking only — which store is nearest — so a flat approximation is
// enough at the distances between branches, and needs no square root.
const squaredDegrees = (lat1: number, lng1: number, lat2: number, lng2: number) => {
  const dLng = (lng2 - lng1) * Math.cos(((lat1 + lat2) / 2) * (Math.PI / 180));
  const dLat = lat2 - lat1;
  return dLat * dLat + dLng * dLng;
};

type OrderRow = {
  id: string;
  member_id: number | null;
  cashier_id: string | null;
  delivery_id: string | null;
  delivery_latitude: number | null;
  delivery_longitude: number | null;
  route_points: number[][] | null;
  route_distance_m: number | null;
  route_duration_s: number | null;
  route_status: string | null;
  route_computed_at: string | null;
  route_origin_lat: number | null;
  route_origin_lng: number | null;
};

const ROUTE_COLUMNS =
  "id, member_id, cashier_id, delivery_id, delivery_latitude, " +
  "delivery_longitude, route_points, route_distance_m, route_duration_s, " +
  "route_status, route_computed_at, route_origin_lat, route_origin_lng";

// The shape the app reads. Same keys whether the route was just fetched or
// has been stored for a week.
const routeOf = (o: OrderRow) => ({
  status: o.route_status,
  points: o.route_points,
  distance_m: o.route_distance_m,
  duration_s: o.route_duration_s,
  computed_at: o.route_computed_at,
  origin:
    o.route_origin_lat == null || o.route_origin_lng == null
      ? null
      : [o.route_origin_lat, o.route_origin_lng],
});

serve(async (req: Request) => {
  // ── 1. Who is asking ─────────────────────────────────────────────
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

  const anonClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const {
    data: { user: caller },
  } = await anonClient.auth.getUser();
  if (!caller) return json({ error: "Unauthorized" }, 401);

  let body: { order_id?: string; force?: boolean };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const orderId = body.order_id;
  if (!orderId) return json({ error: "order_id is required" }, 400);

  // Reads and the write go through the service role: the caller has been
  // identified above and is authorised below, against the order itself.
  const service = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SERVICE_ROLE_KEY")!,
  );

  const { data: me } = await service
    .from("profiles")
    .select("role, member_id, latitude, longitude")
    .eq("id", caller.id)
    .single();
  if (!me) return json({ error: "Unauthorized" }, 401);

  const { data: order } = await service
    .from("orders")
    .select(ROUTE_COLUMNS)
    .eq("id", orderId)
    .single<OrderRow>();
  if (!order) return json({ error: "Order not found" }, 404);

  // ── 2. May they see this order's route ───────────────────────────
  // Branch cashiers are left out on purpose: delivery orders are a main
  // cashier and admin module (v48), and v49's RLS agrees.
  const isStaff = me.role === "admin" || me.role === "cashier";
  const isOwnMember =
    (me.role === "member" || me.role === "reseller") &&
    me.member_id != null &&
    me.member_id === order.member_id;
  const isAssignedRider =
    me.role === "delivery" && order.delivery_id === caller.id;
  if (!isStaff && !isOwnMember && !isAssignedRider) {
    return json({ error: "Forbidden: not a party to this order" }, 403);
  }

  const force = body.force === true && isStaff;

  // ── 3. Answer from the stored copy whenever it is still good ─────
  if (!force) {
    if (order.route_status === "ok" || order.route_status === "unroutable") {
      return json(routeOf(order));
    }
    if (order.route_status === "failed" && order.route_computed_at) {
      const age = Date.now() - Date.parse(order.route_computed_at);
      if (age < RETRY_FAILED_AFTER_MS) return json(routeOf(order));
    }
  }

  // ── 4. Where it goes, and where it starts ────────────────────────
  if (order.delivery_latitude == null || order.delivery_longitude == null) {
    // Nothing is stored: an address added later should still get a route.
    return json({ status: "no_destination" });
  }

  // The fulfilling branch is the order's cashier. Before anyone has taken
  // the order, a staff caller's own branch stands in — they are the one
  // about to handle it.
  let originLat: number | null = null;
  let originLng: number | null = null;
  if (order.cashier_id) {
    const { data: branch } = await service
      .from("profiles")
      .select("latitude, longitude")
      .eq("id", order.cashier_id)
      .single();
    originLat = branch?.latitude ?? null;
    originLng = branch?.longitude ?? null;
  }
  if ((originLat == null || originLng == null) && isStaff) {
    originLat = me.latitude ?? null;
    originLng = me.longitude ?? null;
  }
  if (originLat == null || originLng == null) {
    // Admins price and dispatch too, and have no store of their own: the
    // goods then leave from the main cashier's store nearest the member.
    // The app makes the same choice (delivery_order_pane.dart, _origin).
    const { data: stores } = await service
      .from("profiles")
      .select("latitude, longitude")
      .eq("role", "cashier")
      .not("latitude", "is", null)
      .not("longitude", "is", null);
    let best = Infinity;
    for (const s of stores ?? []) {
      const d = squaredDegrees(
        s.latitude,
        s.longitude,
        order.delivery_latitude,
        order.delivery_longitude,
      );
      if (d < best) {
        best = d;
        originLat = s.latitude;
        originLng = s.longitude;
      }
    }
  }
  if (originLat == null || originLng == null) {
    // Not stored either: the cashier setting their location should unblock
    // it without anyone clearing a failure first.
    return json({ status: "no_origin" });
  }

  // ── 5. Ask the routing service ───────────────────────────────────
  const key = Deno.env.get("ORS_API_KEY");
  if (!key) {
    // A deployment problem, not the order's: stored nowhere, so the first
    // call after the secret is set just works.
    console.error("order-route: ORS_API_KEY is not set");
    return json({ error: "Routing is not configured" }, 503);
  }

  const now = new Date().toISOString();
  const store = async (fields: Partial<OrderRow>) => {
    const { error } = await service
      .from("orders")
      .update({
        ...fields,
        route_computed_at: now,
        route_origin_lat: originLat,
        route_origin_lng: originLng,
      })
      .eq("id", orderId);
    if (error) console.error("order-route: store failed:", error.message);
  };

  let res: Response;
  try {
    // driving-car: ORS has no motorcycle profile, and motorbikes use the
    // roads cars do. A rider who cuts through a footpath is ahead of the
    // estimate, never behind it.
    res = await fetch(
      "https://api.openrouteservice.org/v2/directions/driving-car/geojson",
      {
        method: "POST",
        headers: {
          Authorization: key,
          "Content-Type": "application/json",
          Accept: "application/geo+json",
        },
        body: JSON.stringify({
          // GeoJSON order: longitude first.
          coordinates: [
            [originLng, originLat],
            [order.delivery_longitude, order.delivery_latitude],
          ],
          radiuses: [SNAP_RADIUS_M, SNAP_RADIUS_M],
        }),
        signal: AbortSignal.timeout(10_000),
      },
    );
  } catch (e) {
    console.error("order-route: request failed:", String(e));
    await store({
      route_status: "failed",
      route_points: null,
      route_distance_m: null,
      route_duration_s: null,
    });
    return json({ status: "failed" });
  }

  if (!res.ok) {
    let code: number | undefined;
    try {
      const err = await res.json();
      code = err?.error?.code;
    } catch { /* body was not JSON; treat as transient */ }
    const status = code != null && UNROUTABLE_CODES.has(code)
      ? "unroutable"
      : "failed";
    console.error(`order-route: ORS ${res.status} (code ${code}) → ${status}`);
    await store({
      route_status: status,
      route_points: null,
      route_distance_m: null,
      route_duration_s: null,
    });
    return json({ status });
  }

  const geo = await res.json();
  const feature = geo?.features?.[0];
  const coords: number[][] | undefined = feature?.geometry?.coordinates;
  if (!coords || coords.length < 2) {
    await store({
      route_status: "unroutable",
      route_points: null,
      route_distance_m: null,
      route_duration_s: null,
    });
    return json({ status: "unroutable" });
  }

  // ORS omits the summary fields when they are zero (same point twice).
  const summary = feature?.properties?.summary ?? {};
  const points = coords.map(([lng, lat]) => [round5(lat), round5(lng)]);
  const route = {
    route_status: "ok",
    route_points: points,
    route_distance_m: Math.round(summary.distance ?? 0),
    route_duration_s: Math.round(summary.duration ?? 0),
  };
  await store(route);

  return json({
    status: "ok",
    points,
    distance_m: route.route_distance_m,
    duration_s: route.route_duration_s,
    computed_at: now,
    origin: [originLat, originLng],
  });
});
