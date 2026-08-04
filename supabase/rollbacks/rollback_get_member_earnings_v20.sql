-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK for migration_v21_chairman_immediate_availment.sql
--
-- This is the get_member_earnings function EXACTLY as it ran in production
-- before v21 (weekly Chairman's Bonus, no immediate availment payment).
-- If v21 needs to be undone, run this file — it restores the prior behavior.
-- Nothing else is affected.
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
  if not (
    public.is_staff()
    or exists (
      select 1 from public.profiles pr
      where pr.id = auth.uid() and pr.member_id = p_member_id
    )
  ) then
    raise exception 'Not authorized to view these earnings';
  end if;

  select coalesce(sum(price), 0) into v_balance
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Direct Referral%';

  select coalesce(sum(price), 0) into v_indirect
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Indirect Referral%';

  select coalesce(sum(price), 0) into v_passive
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Group Sales%';

  select coalesce(sum(price), 0) into v_upgrade
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Upgrade Bonus%';

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

  v_total := v_indirect + v_passive + v_chairman + v_upgrade;

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
