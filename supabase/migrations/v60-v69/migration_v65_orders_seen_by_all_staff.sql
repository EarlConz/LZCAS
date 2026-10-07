-- ═══════════════════════════════════════════════════════════════════
-- Migration v65 — Every cashier sees every delivery order
--
-- Requires v55 (can_handle_orders and the orders_select it narrowed).
--
-- Until now a cashier saw only the orders they were working plus the
-- ones nobody had picked up yet (v49, narrowed to admins and cashiers in
-- v55). In testing a cashier reported "some orders are not showing": they
-- were orders another cashier had already quoted. Client decision
-- 2026-10-03: make Delivery Orders central, so admins and cashiers all
-- see every order.
--
-- What changes: only who can SEE an order. orders_select lets in anyone
-- who passes can_handle_orders() (admin or cashier). order_items and
-- order_fee_offers follow automatically: their policies ask "can you see
-- the parent order?" under the caller's own rules (v49, v54).
--
-- What does not: who can CHANGE an order. Quoting, dispatching,
-- completing and cancelling still belong to the cashier holding the order,
-- or an admin (the v_owner checks in v55, v57, v59 and v61). The app shows
-- another cashier's order read-only, with "Handled by <name>". Taking cash
-- from a rider (cashier_remit_cod) was already open to any cashier.
--
-- Members still see only their own orders; riders only the ones they carry.
-- Branch cashiers and inventory accounts still see none.
--
-- Realtime: Postgres changes are filtered by this same policy, so cashiers
-- now receive change events for every order. The in-app alerts already
-- skip orders held by someone else (delivery_notification_service), and
-- the order-push Edge Function picks its recipients itself.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_orders_seen_by_all_staff_v65.sql
-- ═══════════════════════════════════════════════════════════════════

drop policy if exists "orders_select" on public.orders;
create policy "orders_select" on public.orders
  for select to authenticated
  using (
    -- admins and main cashiers: every order
    public.is_admin()
    or public.can_handle_orders()
    -- the member who placed it
    or member_id = public.my_member_id()
    -- the rider carrying it — nothing else, ever
    or (public.is_delivery() and public.order_rider_is_me(id))
  );

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (65, 'orders_seen_by_all_staff')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

notify pgrst, 'reload schema';

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. The policy (expect: true, false):
--      select qual like '%can_handle_orders()%' as all_staff,
--             qual like '%auth.uid()%'          as still_narrowed
--        from pg_policies
--       where tablename = 'orders' and policyname = 'orders_select';
-- 2. In the app, signed in as cashier A:
--      • an order cashier B has quoted shows in A's Delivery Orders, with
--        "Handled by B" and no buttons;
--      • A's own and unclaimed orders work exactly as before.
