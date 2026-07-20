-- ═══════════════════════════════════════════════════════════════════
-- Migration v9 — Fix member identity mapping for withdrawals
--
-- get_current_member_id() resolved auth.uid() against members.user_id,
-- but members.user_id holds the STAFF CREATOR's id, never the member's
-- own auth id. So for a logged-in member the function returned NULL,
-- which made the withdrawal_requests RLS policies (submit + view own)
-- fail — members could not request or see their own withdrawals.
--
-- Fix: map via profiles.member_id, the same auth.uid() -> member link
-- the rest of the app already uses (fetchMemberByAuthUserId, the
-- members/earnings_history self policies, get_member_earnings).
--
-- Only the withdrawal_requests policies call this helper, so redefining
-- it has no other side effects. Safe to re-run.
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.get_current_member_id()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select member_id
  from public.profiles
  where id = auth.uid()
  limit 1;
$$;
