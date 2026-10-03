-- ═══════════════════════════════════════════════════════════════════
-- Rollback v66 — removes the bigint _item_status. Edit Sale fails again
-- with "_item_status(bigint, text) does not exist"; nothing else changes.
-- ═══════════════════════════════════════════════════════════════════

drop function if exists public._item_status(bigint, text);

delete from public.schema_migrations where version = 66;

notify pgrst, 'reload schema';
