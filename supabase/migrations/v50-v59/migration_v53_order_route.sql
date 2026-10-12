-- ═══════════════════════════════════════════════════════════════════
-- Migration v53 — The road route, stored once per order
--
-- The rider's map has drawn a dashed straight line from their position to
-- the member. v53 stores the ROAD route instead: branch to member, fetched
-- from OpenRouteService by the `order-route` Edge Function and saved on the
-- order, so every screen that shows it reads the same copy.
--
-- ── Why on the order, and why once ─────────────────────────────────
-- The routing service's free tier is about 2,000 routes a day. A route
-- fetched by each screen would be paid for again by every viewer and every
-- refresh — the cashier's page, the member's tracking, the rider's detail —
-- and a busy day would exhaust the allowance before noon. Stored here, one
-- order costs one request however many people look at it.
--
-- This is the FIXED route: calculated once, not re-planned as the rider
-- moves. The rider's live dot is drawn on top of it; how far they have
-- left is measured along it on the phone, which costs nothing.
--
-- ── route_status, and why failures are stored too ──────────────────
--   'ok'          route_points holds the road path.
--   'unroutable'  the service found no road near a point, or no road
--                 between them. Permanent for these coordinates: never
--                 retried automatically, or an order pinned in a field would
--                 ask again on every view and quietly burn the allowance.
--   'failed'      a transient failure (rate limit, timeout, service down).
--                 The function retries it after 30 minutes, not sooner.
--   null          never attempted.
--
-- Only the Edge Function writes these columns, with the service role. The
-- app never does.
--
-- Numbering: the payment hardening mentioned alongside v52 (recording a
-- counter payment, refusing delivery of an unpaid order) moves to v54.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_order_route_v53.sql
-- ═══════════════════════════════════════════════════════════════════

alter table public.orders
  -- [[lat, lng], …] in travel order, branch first. Latitude FIRST — the
  -- opposite of GeoJSON, which the function converts from — because every
  -- consumer (flutter_map's LatLng) reads it that way round.
  add column if not exists route_points      jsonb,
  add column if not exists route_distance_m  integer,
  add column if not exists route_duration_s  integer,
  add column if not exists route_status      text,
  add column if not exists route_computed_at timestamptz,
  -- The branch position the route started from. Kept so a branch that later
  -- moves its saved location can be told apart from one whose route is
  -- still right.
  add column if not exists route_origin_lat  double precision,
  add column if not exists route_origin_lng  double precision;

alter table public.orders drop constraint if exists orders_route_status_check;
alter table public.orders add constraint orders_route_status_check
  check (route_status is null or route_status in ('ok', 'unroutable', 'failed'));

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (53, 'order_route')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
--   select column_name from information_schema.columns
--    where table_schema = 'public' and table_name = 'orders'
--      and column_name like 'route%'
--    order by 1;                                  -- expect 7 rows
--
-- Then, with the Edge Function deployed and ORS_API_KEY set, open a
-- dispatched order as its rider: the map shows a road path, and
--   select route_status, route_distance_m from public.orders where id = '…';
-- reads 'ok' and a distance in metres.
