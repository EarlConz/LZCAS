-- ═══════════════════════════════════════════════════════════════════
-- Rollback v53 — The road route, stored once per order
--
-- Drops the route columns. Nothing else reads them, and every route is
-- re-fetchable, so nothing is lost that cannot be recalculated — at the cost
-- of one routing request per order if v53 is applied again.
--
-- Run with the app build that stops calling the `order-route` function, or
-- undeploy the function first: it writes these columns and fails once they
-- are gone. The app itself falls back to a straight line when a route is
-- missing, so older builds are unaffected either way.
-- ═══════════════════════════════════════════════════════════════════

alter table public.orders drop constraint if exists orders_route_status_check;

alter table public.orders
  drop column if exists route_points,
  drop column if exists route_distance_m,
  drop column if exists route_duration_s,
  drop column if exists route_status,
  drop column if exists route_computed_at,
  drop column if exists route_origin_lat,
  drop column if exists route_origin_lng;

delete from public.schema_migrations where version = 53;
