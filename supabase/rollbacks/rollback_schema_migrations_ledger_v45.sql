-- ═══════════════════════════════════════════════════════════════════
-- Rollback for migration_v45_schema_migrations_ledger.sql
--
-- Drops the ledger. Nothing else depends on it — no app code reads
-- schema_migrations, and no other migration references it — so this is
-- one of the few genuinely clean rollbacks here.
--
-- What you lose is the record itself: which migrations were applied, when,
-- and by whom. Re-running v45 rebuilds most of it by detection, but the
-- applied_at timestamps become the moment you re-ran it rather than the
-- moment each migration was actually applied.
--
-- If the goal is just to correct a wrong row, do that instead:
--   delete from public.schema_migrations where version = 46;
-- ═══════════════════════════════════════════════════════════════════

drop policy if exists "schema_migrations_select" on public.schema_migrations;
drop table if exists public.schema_migrations;
