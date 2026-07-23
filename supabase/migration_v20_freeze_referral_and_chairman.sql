-- ═══════════════════════════════════════════════════════════════════
-- Migration v20 — Freeze Direct/Indirect Referral bonuses, and price the
--                 Chairman's Bonus per package-period (no upgrade re-pricing)
--
-- Completes the "lock the rate at the time it was earned" model:
--
--   • DIRECT / INDIRECT REFERRAL — recorded as a member_transactions ledger
--     row the moment a referral registers, using the referrer's package rate
--     AT THAT TIME. Earnings just sum the ledger, so a referrer upgrading no
--     longer re-prices people they referred earlier.
--
--   • CHAIRMAN'S BONUS — instead of (Fridays × current rate), each week is
--     priced at the rate of the package the reseller held THAT week, derived
--     from their availment/upgrade timeline. Weeks on Starter pay Starter's
--     rate; weeks on Ambassador pay Ambassador's. Fridays still accrue weekly.
--
-- Requires migration_v19 (Group Sales triggers). Supersedes the earnings
-- function from v19. Safe to re-run.
--
-- NOTE: applies to referrals registered AFTER this migration. A referrer must
-- already hold a package when a downline registers to earn the referral bonus
-- for them (rate is captured at that moment). Intended on a fresh reset DB.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Freeze referral bonuses when a member registers ───────────────
create or replace function public.record_referral_bonus_on_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_l2   bigint;
  v_rate integer;
begin
  if NEW.referrer_id is null then
    return NEW;
  end if;

  -- Level 1 — the direct referrer earns their direct_referral_bonus, frozen
  -- at their current package rate.
  select coalesce(p.direct_referral_bonus, 0) into v_rate
    from public.members m
    left join public.packages p on p.id = m.package_id
    where m.id = NEW.referrer_id;

  if coalesce(v_rate, 0) > 0 then
    insert into public.member_transactions
      (user_id, member_id, item_id, item_name, quantity, price, timestamp)
    values
      (NEW.user_id, NEW.referrer_id, NEW.id, 'Direct Referral', 1, v_rate, now());
  end if;

  -- Level 2 — the direct referrer's referrer earns indirect_referral_bonus.
  select referrer_id into v_l2 from public.members where id = NEW.referrer_id;
  if v_l2 is not null then
    select coalesce(p.indirect_referral_bonus, 0) into v_rate
      from public.members m
      left join public.packages p on p.id = m.package_id
      where m.id = v_l2;

    if coalesce(v_rate, 0) > 0 then
      insert into public.member_transactions
        (user_id, member_id, item_id, item_name, quantity, price, timestamp)
      values
        (NEW.user_id, v_l2, NEW.id, 'Indirect Referral', 1, v_rate, now());
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_record_referral_bonus on public.members;
create trigger trg_record_referral_bonus
  after insert on public.members
  for each row execute function public.record_referral_bonus_on_member();

-- ── 2. Earnings: all frozen ledgers + per-period Chairman's Bonus ─────
create or replace function public.get_member_earnings(p_member_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
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

  -- ── Chairman's Bonus: weekly, each week priced by the package the
  --    member actually held that week (Asia/Manila). Built from the
  --    availment/upgrade timeline so an upgrade never re-prices old weeks.
  --    2000-01-07 is a Friday; both operands are positive so integer
  --    division floors, counting Fridays in (period_start, period_end].
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
  select coalesce(sum(rate * fridays), 0), coalesce(sum(fridays), 0)
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
$$;
