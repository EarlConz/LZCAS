-- ═══════════════════════════════════════════════════════════════════
-- Rollback for migration_v46_app_config_rls.sql
--
-- Drops the policies and turns RLS back off, returning app_config to what
-- schema.sql describes: an unprotected table.
--
-- ⚠️ Understand what that means before running it. With RLS off, ANY
-- signed-in account can rewrite app settings through the API — a member
-- could change the currency symbol or the birthday greeting's wording.
-- That was the state the app shipped in; it was never deliberate.
--
-- The far more likely thing you want, if v46 broke something, is to keep
-- RLS and widen the write policy rather than remove it. For example, to
-- let all staff write:
--
--   drop policy if exists "app_config_update" on public.app_config;
--   create policy "app_config_update" on public.app_config
--     for update to authenticated
--     using (public.is_staff()) with check (public.is_staff());
--
-- Only run what follows if you specifically need the old unprotected
-- behaviour back.
-- ═══════════════════════════════════════════════════════════════════

drop policy if exists "app_config_select" on public.app_config;
drop policy if exists "app_config_insert" on public.app_config;
drop policy if exists "app_config_update" on public.app_config;

alter table public.app_config disable row level security;

-- The keys inserted by v46 are left in place: they are the defaults every
-- migration since v36 has expected, and removing them would send the app
-- back to hardcoded fallbacks.

delete from public.schema_migrations where version = 46;
