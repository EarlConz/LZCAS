-- ═══════════════════════════════════════════════════════════════════
-- Rollback v69 — tracking numbers may repeat across orders again.
-- ═══════════════════════════════════════════════════════════════════

drop trigger if exists orders_guard_tracking_number on public.orders;
drop function if exists public.guard_order_tracking_number();
drop index if exists public.idx_orders_tracking_key;
drop function if exists public._tracking_key(text);

delete from public.schema_migrations where version = 69;

notify pgrst, 'reload schema';
