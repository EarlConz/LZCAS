-- ═══════════════════════════════════════════════════════════════════
-- Migration v15 — Chairman's Bonus becomes a WEEKLY (every-Friday) payout
--
-- Redefines the Chairman's Bonus in get_member_earnings:
--   • It is the RESELLER'S OWN package `chairmans_bonus` value
--     (Starter ₱50, Ambassador ₱100), NOT a hardcoded price tier and NOT
--     based on downline registrations.
--   • The reseller earns that amount ONCE EVERY FRIDAY, accruing from the
--     date they availed their package. Total = (# of Fridays since
--     availment) × package chairman's bonus. Calendar = Asia/Manila.
--
-- This supersedes the per-registration one-time Chairman's Bonus from
-- migration_v6. Everything else in get_member_earnings is unchanged.
-- Also revives the `chairmanFridays` count in the returned payload so the
-- member dashboard's "(N Fridays)" label works again.
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
  v_has_pkg      boolean := false;
  v_pkg_direct   integer := 0;
  v_pkg_indirect integer := 0;
  v_pkg_chairman integer := 0;
  v_direct_count integer := 0;
  v_indirect_count integer := 0;
  v_balance      integer := 0;
  v_indirect     integer := 0;
  v_passive      integer := 0;
  v_repeat       integer := 0;
  v_chairman     integer := 0;
  v_fridays      integer := 0;
  v_avail_ts     timestamptz;
  v_upgrade      integer := 0;
  v_total        integer := 0;
  v_earn_deduct  integer := 0;
  v_bal_deduct   integer := 0;
  v_now_manila   timestamp := (now() at time zone 'Asia/Manila');
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
         p.chairmans_bonus, true
    into v_pkg_direct, v_pkg_indirect, v_pkg_chairman, v_has_pkg
    from public.members m
    join public.packages p on p.id = m.package_id
    where m.id = p_member_id;
  if not found then
    v_has_pkg := false;
    v_pkg_direct := 0; v_pkg_indirect := 0; v_pkg_chairman := 0;
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

  -- ── Passive income: downline product purchases ──────────────────
  -- direct referral → 5/item, indirect → 3/item (package sales excluded)
  with downline as (
    select id, 1 as lvl from public.members where referrer_id = p_member_id
    union
    select id, 2 as lvl from public.members
      where referrer_id in (
        select id from public.members where referrer_id = p_member_id
      )
  )
  select coalesce(sum((case when d.lvl = 1 then 5 else 3 end) * s.quantity), 0)
    into v_passive
    from public.sales s
    join downline d on d.id = s.buyer_id
    where s.package_id is null and s.quantity > 0;

  -- ── Repeat purchase: own product purchases by category ──────────
  -- First (lowest-id) category whose name is contained in the item name.
  if v_has_pkg then
    select coalesce(sum(comm.rate * s.quantity), 0)
      into v_repeat
      from public.sales s
      cross join lateral (
        select c.commission_rate as rate
        from public.categories c
        where position(lower(c.name) in lower(coalesce(s.item_name, ''))) > 0
        order by c.id
        limit 1
      ) comm
      where s.buyer_id = p_member_id
        and s.package_id is null
        and s.quantity > 0;
  end if;

  -- ── Chairman's Bonus: WEEKLY (every Friday) ─────────────────────
  -- The reseller earns their OWN package's chairman's bonus once per
  -- Friday, accruing from the date they availed their package.
  --   v_chairman = (# Fridays since availment) × package chairman's bonus
  -- Only package holders qualify; no package → 0.
  if v_has_pkg and v_pkg_chairman > 0 then
    -- When did this member avail their package? Earliest non-upgrade
    -- availment sale; fall back to their earliest sale of any kind
    -- (members has no created_at column).
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
      -- Count Fridays strictly after the availment date, up to today
      -- (Asia/Manila). 2000-01-07 is a Friday; both operands are positive
      -- so integer division floors correctly.
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

  v_total := v_indirect + v_passive + v_repeat + v_chairman + v_upgrade;

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
    'repeatPurchase', v_repeat,
    'chairmanBonus',  v_chairman,
    'upgradeBonus',   v_upgrade,
    'chairmanFridays', v_fridays
  );
end;
$$;
