-- ═══════════════════════════════════════════════════════════════════
-- Migration v72 — Orders keep their "last changed" time again
--
-- Requires v48 (public.orders). Safe to re-run; changes nothing where the
-- trigger is already in place.
--
-- Found 2026-10-05 by diagnostics/find_missing_objects.sql: staging has
-- no orders_touch_updated_at trigger, so orders.updated_at stays at the
-- moment the order was placed. Delivery Orders reads it for how long an
-- order has waited in its current step, for sorting, and (since 2026-10-04)
-- to decide which finished orders fall in the last 30 days of History.
-- Most likely staging's orders table came from an early v48 without the
-- trigger. Re-running v48 is NOT the fix: it would put back v48's old
-- versions of order functions that v49–v61 replaced.
--
-- This is v48's function and trigger, unchanged.
--
-- Rollback: supabase/rollbacks/rollback_orders_touch_updated_at_v72.sql
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.touch_orders_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists orders_touch_updated_at on public.orders;
create trigger orders_touch_updated_at
  before update on public.orders
  for each row execute function public.touch_orders_updated_at();

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (72, 'orders_touch_updated_at')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- select tgname from pg_trigger where tgname = 'orders_touch_updated_at';
-- Expect 1 row. Then any change to an order moves its updated_at.
