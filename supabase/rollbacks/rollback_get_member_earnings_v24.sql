-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK for migration_v24_chairman_frozen_ledger.sql
--
-- Undoes the frozen-ledger conversion and returns to v23 behavior
-- (Chairman's Bonus computed LIVE per direct referral, priced at the package
-- held when the referral registered). Three parts, mirroring the migration:
--   1. Restore the trigger to NOT write Chairman Bonus rows.
--   2. Delete the Chairman Bonus ledger rows the migration created.
--   3. Restore the v23 RPC (live recompute).
--
-- After this, Chairman is once again recomputed live, so values are identical
-- to before v24 — but editing a package's chairman rate will again move
-- history (that's the v23 behavior you're reverting to).
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Trigger without Chairman Bonus (v20/v23 version) ──────────────
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

-- ── 2. Remove the frozen Chairman Bonus ledger rows ──────────────────
delete from public.member_transactions where item_name ilike 'Chairman Bonus%';

-- ── 3. Restore the v23 RPC (Chairman computed live per referral) ─────
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

  v_fridays := 0;

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
