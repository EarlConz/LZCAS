-- ═══════════════════════════════════════════════════════════════════
-- Migration v6 — Server-side earnings computation (CRITICAL-3)
--
-- Moves the reseller earnings calculation OUT of the Flutter client
-- (which had to read the entire members + sales tree, exposing every
-- reseller's financial data to every logged-in user) and INTO a
-- SECURITY DEFINER RPC that reads the tree internally and returns ONLY
-- the caller's own totals.
--
-- Ownership: only the member themselves (via profiles.member_id) or
-- staff may fetch a given member's earnings.
--
-- The logic is a faithful port of SupabaseRepository
-- .fetchMemberEarningsBreakdown, with one deliberate improvement: the
-- Chairman's Bonus Friday gate is computed in Asia/Manila instead of
-- device-local time (fixes the timezone blindspot). PH devices already
-- run in UTC+8, so results are unchanged in production.
--
-- Run AFTER enable_rls_staff.sql. Safe to re-run.
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
  v_direct_count integer := 0;
  v_indirect_count integer := 0;
  v_balance      integer := 0;
  v_indirect     integer := 0;
  v_passive      integer := 0;
  v_repeat       integer := 0;
  v_chairman     integer := 0;
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
  select p.direct_referral_bonus, p.indirect_referral_bonus, true
    into v_pkg_direct, v_pkg_indirect, v_has_pkg
    from public.members m
    join public.packages p on p.id = m.package_id
    where m.id = p_member_id;
  if not found then
    v_has_pkg := false; v_pkg_direct := 0; v_pkg_indirect := 0;
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

  -- ── Chairman's bonus: per downline registration ─────────────────
  -- Priced from the earliest NON-upgrade availment sale (never the
  -- member's current package). Matures on the first Friday on/after the
  -- registration date (Asia/Manila). Legacy members with no availment
  -- sale fall back to their current package price, ungated.
  with downline as (
    select id, package_id from public.members where referrer_id = p_member_id
    union
    select id, package_id from public.members
      where referrer_id in (
        select id from public.members where referrer_id = p_member_id
      )
  ),
  reg as (
    select distinct on (s.buyer_id)
           s.buyer_id, s.price as reg_price, s."timestamp" as reg_ts
      from public.sales s
      join downline d on d.id = s.buyer_id
      where s.package_id is not null
        and coalesce(s.item_name, '') not like 'Package Upgrade%'
      order by s.buyer_id, s."timestamp" asc
  ),
  priced as (
    select
      case
        when r.buyer_id is not null then
          case
            when v_now_manila <
                 date_trunc('day', (r.reg_ts at time zone 'Asia/Manila'))
                 + ((( 5 - extract(isodow from (r.reg_ts at time zone 'Asia/Manila'))::int) + 7) % 7)
                   * interval '1 day'
            then null                       -- not yet matured this Friday
            else r.reg_price
          end
        when d.package_id is not null then
          (select pp.price from public.packages pp where pp.id = d.package_id)
        else null
      end as price
    from downline d
    left join reg r on r.buyer_id = d.id
  )
  select coalesce(sum(
           case when price >= 3000 then 100
                when price >= 1500 then 50
                else 0 end), 0)
    into v_chairman
    from priced;

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
    'chairmanFridays', 0
  );
end;
$$;
