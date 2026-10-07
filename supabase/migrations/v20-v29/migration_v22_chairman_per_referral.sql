-- ═══════════════════════════════════════════════════════════════════
-- Migration v22 — Chairman's Bonus: earned per DIRECT REFERRAL, paid on
--                 that week's Friday (no more automatic weekly accrual)
--
-- NEW RULE (replaces the v21 "every Friday + immediate on availment" model):
--   A reseller earns Chairman's Bonus only for weeks in which they recruited
--   direct referrals. On a given week's Friday they earn:
--
--        (number of direct referrals gathered that week) × chairman rate
--
--   A week with no direct referrals pays no Chairman's Bonus. So the total is
--   driven by recruitment, not by how long ago the package was availed.
--
--   • RATE — each Friday's payout is priced at the chairmans_bonus of the
--     package the reseller HOLDS ON THAT FRIDAY (when the bonus rolls out).
--     So if they upgrade before a Friday, that whole week's referrals pay at
--     the new rate. The rate is fixed to what they held that Friday, so a
--     LATER upgrade never re-prices an already-passed Friday.
--
--   • TIMING — a referral gathered this week only counts once that week's
--     Friday has passed (Asia/Manila). A referral made on Friday counts that
--     same Friday. 2000-01-07 is a known Friday; the payout Friday is the next
--     Friday on-or-after the referral's date.
--
--   Direct referrals are the individual member_transactions rows written by
--   trg_record_referral_bonus (item_name 'Direct Referral'), each with the
--   timestamp of when that downline registered — so "how many this week" is a
--   simple count of those rows per Friday-week.
--
-- This is the ONLY change from the deployed v21 function — Direct/Indirect
-- Referral, Group Sales, Upgrade Bonus, withdrawals and everything else are
-- byte-for-byte identical. DB-only: no app rebuild needed.
--
-- Return keys are unchanged. 'chairmanFridays' now means "number of Fridays
-- the reseller actually got paid on" (distinct weeks that had ≥1 credited
-- referral), so the installed app's "(N Fridays)" label stays truthful.
--
-- Rollback: supabase/rollback_get_member_earnings_v21.sql (restores v21).
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

  -- ── Chairman's Bonus: for each payout Friday, count the direct referrals
  --    gathered that week and multiply by the chairman rate of the package
  --    the reseller HOLDS ON THAT FRIDAY. Only Fridays that have already
  --    passed (Asia/Manila) are paid. The rate is taken from the package
  --    effective on the Friday date, so a later upgrade never re-prices an
  --    already-passed Friday.
  with pkg_periods as (
    -- the reseller's own availment/upgrade timeline (Manila dates)
    select
      ((s."timestamp") at time zone 'Asia/Manila')::date as eff_from,
      ((lead(s."timestamp") over (order by s."timestamp"))
         at time zone 'Asia/Manila')::date as eff_to,
      coalesce(pk.chairmans_bonus, 0) as rate
    from public.sales s
    join public.packages pk on pk.id = s.package_id
    where s.buyer_id = p_member_id and s.package_id is not null
  ),
  referrals as (
    -- each direct referral mapped to its payout Friday (next Friday on-or-
    -- after the registration date, 2000-01-07 is a Friday)
    select
      (date '2000-01-07'
        + (ceil((((mt."timestamp") at time zone 'Asia/Manila')::date
                 - date '2000-01-07')::numeric / 7)::int) * 7) as payout_friday
    from public.member_transactions mt
    where mt.member_id = p_member_id
      and mt.item_name ilike 'Direct Referral%'
  ),
  weekly as (
    -- referrals per already-passed Friday
    select payout_friday, count(*) as referral_count
    from referrals
    where payout_friday <= v_now_manila::date
    group by payout_friday
  ),
  priced as (
    select
      w.referral_count,
      -- chairman rate of the package held ON that Friday (0 if none)
      coalesce((
        select pp.rate
        from pkg_periods pp
        where w.payout_friday >= pp.eff_from
          and (pp.eff_to is null or w.payout_friday < pp.eff_to)
        order by pp.eff_from desc
        limit 1
      ), 0) as rate
    from weekly w
  )
  select
    coalesce(sum(referral_count * rate), 0),
    count(*)
    into v_chairman, v_fridays
    from priced;

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
