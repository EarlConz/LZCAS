-- ═══════════════════════════════════════════════════════════════════
-- Rollback for migration_v34_earnings_sources_rpc.sql
--
-- Drops the itemised earnings-sources function. Safe: the function is
-- read-only and nothing else depends on it. After running this, an app
-- build that expects the RPC will fail to load the "Where your earnings
-- came from" card (it degrades to an empty card, not a crash), so ship
-- the matching app build alongside.
-- ═══════════════════════════════════════════════════════════════════

drop function if exists public.get_member_earnings_sources(bigint);
