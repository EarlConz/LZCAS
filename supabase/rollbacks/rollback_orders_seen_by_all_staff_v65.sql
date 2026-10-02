-- ═══════════════════════════════════════════════════════════════════
-- Rollback v65 — cashiers see only their own and unclaimed orders again
--
-- Restores orders_select exactly as v55 left it. The app keeps working
-- either way: with this rolled back it simply never receives another
-- cashier's orders, so the read-only "Handled by" view never shows.
-- ═══════════════════════════════════════════════════════════════════

drop policy if exists "orders_select" on public.orders;
create policy "orders_select" on public.orders
  for select to authenticated
  using (
    public.is_admin()
    -- the member who placed it
    or member_id = public.my_member_id()
    -- the cashier working it, plus anything nobody has picked up yet
    or (public.can_handle_orders() and (cashier_id = auth.uid() or cashier_id is null))
    -- the rider carrying it — nothing else, ever
    or (public.is_delivery() and public.order_rider_is_me(id))
  );

delete from public.schema_migrations where version = 65;

notify pgrst, 'reload schema';
