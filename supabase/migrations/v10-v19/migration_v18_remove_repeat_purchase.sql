-- ═══════════════════════════════════════════════════════════════════
-- Migration v18 — Remove the Repeat Purchase bonus
--
-- Repeat Purchase (cash-back on a reseller's own product purchases, priced
-- from the product's category commission_rate) is no longer part of the
-- compensation plan. This redefines get_member_earnings WITHOUT it:
--   • the component is dropped from the earnings total, and
--   • repeatPurchase is reported as 0 for backward compatibility.
--
-- This redefines the whole function, so it also INCLUDES the weekly
-- Chairman's Bonus (v15) and package-based Group Sales (v16). Running v18
-- alone is sufficient — it supersedes v6, v15 and v16.
--
-- The earnings_history.repeat_purchase column and packages.repeat_purchase_json
-- column are left in place (inert, default 0/'{}') to avoid churn across the
-- other snapshot-writing functions; they simply stop being populated.
--
-- Run AFTER migration_v6_earnings_rpc.sql. Safe to re-run.
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.get_member_earnings(p_member_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_has_pkg        boolean := false;
  v_pkg_direct     integer := 0;
  v_pkg_indirect   integer := 0;
  v_pkg_chairman   integer := 0;
  v_pkg_gs_direct  integer := 0;
  v_pkg_gs_indirect integer := 0;
  v_direct_count   integer := 0;
  v_indirect_count integer := 0;
  v_balance        integer := 0;
  v_indirect       integer := 0;
  v_passive        integer := 0;
  v_chairman       integer := 0;
  v_fridays        integer := 0;
  v_avail_ts       timestamptz;
  v_upgrade        integer := 0;
  v_total          integer := 0;
  v_earn_deduct    integer := 0;
  v_bal_deduct     integer := 0;
  v_now_manila     timestamp := (now() at time zone 'Asia/Manila');
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

  -- ── This member's package bonuses (if any) ──────────────────────
  select p.direct_referral_bonus, p.indirect_referral_bonus,
         p.chairmans_bonus, p.group_sales_direct, p.group_sales_indirect, true
    into v_pkg_direct, v_pkg_indirect, v_pkg_chairman,
         v_pkg_gs_direct, v_pkg_gs_indirect, v_has_pkg
    from public.members m
    join public.packages p on p.id = m.package_id
    where m.id = p_member_id;
  if not found then
    v_has_pkg := false;
    v_pkg_direct := 0; v_pkg_indirect := 0; v_pkg_chairman := 0;
    v_pkg_gs_direct := 0; v_pkg_gs_indirect := 0;
  end if;

  -- ── Direct + indirect referral counts ───────────────────────────
  select count(*) into v_direct_count
    from public.members where referrer_id = p_member_id;

  select count(*) into v_indirect_count
    from public.members
    where referrer_id in (
      select id from public.members where referrer_id = p_member_id
    );

  if v_has_pkg then
    v_balance  := v_direct_count * v_pkg_direct;      -- balance pool
    v_indirect := v_indirect_count * v_pkg_indirect;  -- indirect bonus
  end if;

  -- ── Group Sales (passive income): downline product purchases ────
  -- Rate comes from THIS member's package: group_sales_direct for a
  -- direct (level-1) downline, group_sales_indirect for indirect
  -- (level-2). Package availments excluded. No package → 0.
  if v_has_pkg then
    with downline as (
      select id, 1 as lvl from public.members where referrer_id = p_member_id
      union
      select id, 2 as lvl from public.members
        where referrer_id in (
          select id from public.members where referrer_id = p_member_id
        )
    )
    select coalesce(sum(
             (case when d.lvl = 1 then v_pkg_gs_direct else v_pkg_gs_indirect end)
             * s.quantity), 0)
      into v_passive
      from public.sales s
      join downline d on d.id = s.buyer_id
      where s.package_id is null and s.quantity > 0;
  end if;

  -- ── Chairman's Bonus: WEEKLY (every Friday) ─────────────────────
  -- The reseller earns their OWN package's chairman's bonus once per
  -- Friday, accruing from the date they availed their package.
  if v_has_pkg and v_pkg_chairman > 0 then
    select min(s."timestamp") into v_avail_ts
      from public.sales s
      where s.buyer_id = p_member_id
        and s.package_id is not null
        and coalesce(s.item_name, '') not like 'Package Upgrade%';
    if v_avail_ts is null then
      select min(s."timestamp") into v_avail_ts
        from public.sales s where s.buyer_id = p_member_id;
    end if;

    if v_avail_ts is not null then
      v_fridays :=
          ((v_now_manila::date - date '2000-01-07') / 7)
        - (((v_avail_ts at time zone 'Asia/Manila')::date - date '2000-01-07') / 7);
      if v_fridays < 0 then v_fridays := 0; end if;
      v_chairman := v_fridays * v_pkg_chairman;
    end if;
  end if;

  -- ── Upgrade referral bonus: recorded by the upgrade RPC ─────────
  select coalesce(sum(price), 0)
    into v_upgrade
    from public.member_transactions
    where member_id = p_member_id
      and item_name ilike 'Upgrade Bonus%';

  -- Repeat Purchase has been removed from the compensation plan.
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
$$;
