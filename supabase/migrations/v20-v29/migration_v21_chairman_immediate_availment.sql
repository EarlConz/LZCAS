-- ═══════════════════════════════════════════════════════════════════
-- Migration v21 — Chairman's Bonus: immediate payment on availment/upgrade
--
-- Adds ONE immediate Chairman's Bonus payment the moment a reseller avails
-- or upgrades a package, on top of the existing weekly (every-Friday) payout.
--
--   Per package period:  rate × (1 + Fridays elapsed)
--                                 └ the immediate availment/upgrade payment
--
-- This is the ONLY change from the currently-deployed function — Group Sales,
-- Direct/Indirect Referral, Upgrade Bonus, withdrawals and everything else are
-- byte-for-byte identical. Safe to apply on the live database: it only ever
-- INCREASES Chairman's Bonus (no data loss, no zeroing).
--
-- Note: because the amount is derived from existing availment/upgrade sales,
-- current resellers receive the immediate payment retroactively for package
-- events that already happened (a one-time upward adjustment).
--
-- Rollback: re-run this function with `rate * fridays` (no "+ 1") in the final
-- select — that is the pre-v21 behavior.
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
  v_now_manila  timestamp := (now() at time zone 'Asia/Manila');
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

  -- ── Chairman's Bonus: an immediate payment on each availment/upgrade
  --    PLUS the weekly (every-Friday) payout. Each package period is
  --    priced by the package the member held that period (Asia/Manila),
  --    so an upgrade never re-prices old weeks. 2000-01-07 is a Friday;
  --    both operands are positive so integer division floors, counting
  --    Fridays in (period_start, period_end].
  with pkg_periods as (
    select
      ((s."timestamp") at time zone 'Asia/Manila')::date as eff_from,
      ((lead(s."timestamp") over (order by s."timestamp"))
         at time zone 'Asia/Manila')::date as eff_to,
      coalesce(pk.chairmans_bonus, 0) as rate
    from public.sales s
    join public.packages pk on pk.id = s.package_id
    where s.buyer_id = p_member_id and s.package_id is not null
  ),
  periods_fridays as (
    select
      rate,
      greatest(0,
        ((coalesce(eff_to, v_now_manila::date) - date '2000-01-07') / 7)
        - ((eff_from - date '2000-01-07') / 7)
      ) as fridays
    from pkg_periods
  )
  -- rate × (1 + fridays): the "1" is the immediate availment/upgrade
  -- payment; v_fridays keeps counting only the weekly Fridays for display.
  select coalesce(sum(rate * (fridays + 1)), 0), coalesce(sum(fridays), 0)
    into v_chairman, v_fridays
    from periods_fridays;

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
