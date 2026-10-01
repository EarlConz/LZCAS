-- ═══════════════════════════════════════════════════════════════════
-- Rollback v60 — Reducing stock is one step the database checks
--
-- Removes reduce_item_stock.
--
-- Read first:
--   • The app built with v60 reduces stock only through this function.
--     After this rollback, Reduce Stock in Edit Product and approving a
--     reduction request both fail with an error until the app is rolled
--     back too, or v60 is re-applied. Nothing is written when they fail.
--   • Stock and stock_movements written through it stay as they are.
-- ═══════════════════════════════════════════════════════════════════

drop function if exists public.reduce_item_stock(bigint, integer, text, uuid);

delete from public.schema_migrations where version = 60;
