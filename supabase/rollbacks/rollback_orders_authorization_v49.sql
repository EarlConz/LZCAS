-- ═══════════════════════════════════════════════════════════════════
-- Rollback for migration_v49_orders_authorization.sql
--
-- ⚠️ Read before running. This returns `orders` and `order_items` to
-- v48's state: RLS OFF, and RPCs that check NOTHING about the caller.
-- Concretely, after this runs:
--
--   • every signed-in member can read every other member's home
--     address and GPS coordinates;
--   • any caller can cancel or complete any order by id.
--
-- Those are the defects v49 exists to close. There is no partial form
-- of this rollback that keeps the protection — if v49 broke a specific
-- flow, fix that RPC's check rather than removing all of them.
--
-- v50 depends on v49 (is_delivery, my_member_id, order_rider_is_me).
-- Roll back v50 first, or this will leave v50's RPCs calling functions
-- that no longer exist.
-- ═══════════════════════════════════════════════════════════════════

do $$
begin
  if exists (select 1 from public.schema_migrations where version = 50) then
    raise exception 'v50 is applied. Roll back v50 before v49.';
  end if;
end $$;

drop policy if exists "orders_select"      on public.orders;
drop policy if exists "order_items_select" on public.order_items;
alter table public.orders      disable row level security;
alter table public.order_items disable row level security;

-- Restore v48's unchecked RPC bodies by re-running v48's function
-- definitions. Re-applying migration_v48_delivery_orders.sql is the
-- supported way to do that; its create-or-replace statements overwrite
-- these. Nothing here reproduces them, deliberately — one copy of each
-- function definition, in the migration that owns it.

drop function if exists public.order_rider_is_me(uuid);
drop function if exists public.my_member_id();
drop function if exists public.is_delivery();

delete from public.schema_migrations where version = 49;
-- The v47 / v48 rows v49 recorded are left in place: they are true.
