-- ═══════════════════════════════════════════════════════════════════
-- Migration v23 — Chairman's Bonus: immediate, one payment per direct
--                 referral, frozen at the rate held when it happened
--
-- NEW RULE (replaces the v22 "paid on that week's Friday" model):
--   The moment a reseller gets a direct referral, they immediately earn one
--   Chairman's Bonus — no waiting for Friday. Total is simply:
--
--        (number of direct referrals) × chairman rate at each referral
--
--   • TIMING — immediate. A referral registered today shows up in Chairman's
--     Bonus today. There is no weekly/Friday gate anymore.
--
--   • RATE (frozen at referral time) — each referral is priced at the
--     chairmans_bonus of the package the reseller HELD the moment that
--     referral registered, taken from their availment/upgrade timeline. A
--     later upgrade never re-prices earlier referrals; only new referrals earn
--     the new rate. This matches every other bonus (Direct/Indirect Referral,
--     Group Sales, Upgrade) which are all frozen at event time.
--
--   Direct referrals are the individual member_transactions rows written by
--   trg_record_referral_bonus (item_name 'Direct Referral'), so the count is
--   just how many of those rows the reseller has.
--
-- This is the ONLY change from the deployed v22 function — Direct/Indirect
-- Referral, Group Sales, Upgrade Bonus, withdrawals and everything else are
-- byte-for-byte identical. DB-only: no app rebuild needed.
--
-- Return keys are unchanged. 'chairmanFridays' is now always 0 (there is no
-- Friday concept), which makes the installed app hide its "(N Fridays)" suffix
-- and simply show the Chairman's Bonus amount.
--
-- Rollback: supabase/rollback_get_member_earnings_v22.sql (restores v22).
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.get_member_earnings(p_member_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_balance     integer := 0;
  v_indirect    integer := 0;
  v_passive     integer := 0;
  v_chairman    integer := 0;
  v_fridays     integer := 0;
  v_upgrade     integer := 0;
  v_total       integer := 0;
  v_earn_deduct integer := 0;
  v_bal_deduct  integer := 0;
begin
  -- ── Authorization: staff, or the member themselves ──────────────
  if not (
    public.is_staff()
    or exists (
      select 1 from public.profiles pr
      where pr.id = auth.uid() and pr.member_id = p_member_id
    )
  ) then
    raise exception 'Not authorized to view these earnings';
  end if;

  -- ── Direct Referral Bonus (Balance wallet) — frozen at registration
  select coalesce(sum(price), 0) into v_balance
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Direct Referral%';

  -- ── Indirect Referral Bonus — frozen at registration ────────────
  select coalesce(sum(price), 0) into v_indirect
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Indirect Referral%';

  -- ── Group Sales (passive income) — frozen at purchase time (v19) ─
  select coalesce(sum(price), 0) into v_passive
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Group Sales%';

  -- ── Upgrade Referral Bonus — frozen at upgrade time ─────────────
  select coalesce(sum(price), 0) into v_upgrade
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Upgrade Bonus%';

  -- ── Chairman's Bonus: one chairman rate per direct referral, credited
  --    immediately and priced at the package the reseller held the moment
  --    that referral registered (from their availment/upgrade timeline), so
  --    a later upgrade never re-prices earlier referrals.
  with pkg_periods as (
    select
      s."timestamp" as eff_from_ts,
      lead(s."timestamp") over (order by s."timestamp") as eff_to_ts,
      coalesce(pk.chairmans_bonus, 0) as rate
    from public.sales s
    join public.packages pk on pk.id = s.package_id
    where s.buyer_id = p_member_id and s.package_id is not null
  ),
  referrals as (
    select mt."timestamp" as ts
    from public.member_transactions mt
    where mt.member_id = p_member_id
      and mt.item_name ilike 'Direct Referral%'
  ),
  priced as (
    select coalesce((
      select pp.rate
      from pkg_periods pp
      where r.ts >= pp.eff_from_ts
        and (pp.eff_to_ts is null or r.ts < pp.eff_to_ts)
      order by pp.eff_from_ts desc
      limit 1
    ), 0) as rate
    from referrals r
  )
  select coalesce(sum(rate), 0)
    into v_chairman
    from priced;

  -- No Friday concept anymore — keep the key for old clients, always 0.
  v_fridays := 0;

  -- Repeat Purchase was removed from the compensation plan (v18).
  v_total := v_indirect + v_passive + v_chairman + v_upgrade;

  -- ── Subtract approved withdrawals per bucket ────────────────────
  select
    coalesce(sum(case when source_bucket = 'total_earnings' then requested_amount else 0 end), 0),
    coalesce(sum(case when source_bucket = 'balance'        then requested_amount else 0 end), 0)
    into v_earn_deduct, v_bal_deduct
    from public.withdrawal_requests
    where member_id = p_member_id and status = 'approved';

  return jsonb_build_object(
    'totalEarnings',  greatest(0, v_total   - v_earn_deduct),
    'balance',        greatest(0, v_balance - v_bal_deduct),
    'indirectBonus',  v_indirect,
    'passiveIncome',  v_passive,
    'repeatPurchase', 0,
    'chairmanBonus',  v_chairman,
    'upgradeBonus',   v_upgrade,
    'chairmanFridays', v_fridays
  );
end;
$function$;
