-- ═══════════════════════════════════════════════════════════════════
-- Rollback for migration_v42_server_now.sql
--
-- Drops server_now(). The app falls back to the device clock on its
-- own — AppClock keeps a zero offset when the call fails — so this is
-- safe to run against a client that still expects the function. It
-- simply reintroduces the bug v42 exists to fix.
-- ═══════════════════════════════════════════════════════════════════

drop function if exists public.server_now();
