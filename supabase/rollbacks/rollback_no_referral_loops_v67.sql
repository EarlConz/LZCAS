-- ═══════════════════════════════════════════════════════════════════
-- Rollback v67 — removes the referral-loop guard. Members can again be
-- given a referrer from their own downline (the app still hides those).
-- ═══════════════════════════════════════════════════════════════════

drop trigger if exists members_guard_referrer on public.members;
drop function if exists public.guard_member_referrer();

delete from public.schema_migrations where version = 67;

notify pgrst, 'reload schema';
