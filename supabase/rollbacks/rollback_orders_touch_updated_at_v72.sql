-- ═══════════════════════════════════════════════════════════════════
-- Rollback v72 — STAGING ONLY. Removes the trigger again; orders'
-- updated_at then stops moving. The function stays (v48 owns it).
-- ⛔ Never on production, where v48 put this trigger in place.
-- ═══════════════════════════════════════════════════════════════════

drop trigger if exists orders_touch_updated_at on public.orders;

delete from public.schema_migrations where version = 72;
