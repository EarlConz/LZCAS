-- ═══════════════════════════════════════════════════════════════════
-- Migration v17 — Upgrade Referral Bonus: referrer's own package + real
--                 upgrades only
--
-- Two corrections to how the upgrade referral bonus is paid:
--
--   1. AMOUNT comes from the REFERRER'S OWN package `upgrade_referral_bonus`
--      (consistent with every other bonus), NOT from the target package the
--      downline upgraded to.
--
--   2. Only a GENUINE upgrade pays the bonus — the member must already hold a
--      package (current rank > 0). A first availment (no package → a package)
--      is a Member → Verified Reseller promotion, not an upgrade, so it pays
--      no upgrade bonus. A later step (Package 1 → Package 2) does pay.
--
-- The promotion itself (set package, role → Verified Reseller, sync login
-- role) still happens for the no-package → package case; only the bonus is
-- skipped there.
--
-- Supersedes the bonus logic in migration_v14. Safe to re-run. Requires
-- is_staff().
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.process_package_upgrade(
  p_member_id bigint,
  p_target_package_id bigint
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current_rank     integer;
  v_target_rank      integer;
  v_target_name      text;
  v_target_price     integer;
  v_upgrade_bonus    integer := 0;
  v_referrer_id      bigint;
  v_last             record;
begin
  -- 0. Authorization: only back-office staff may run an upgrade.
  if not public.is_staff() then
    raise exception 'Not authorized: staff role required to process an upgrade';
  end if;

  -- 1. Lock the member row so a concurrent upgrade / retry serializes
  --    behind us instead of re-reading the old rank.
  perform 1 from public.members where id = p_member_id for update;
  if not found then
    raise exception 'Member not found (id=%)', p_member_id;
  end if;

  -- 1b. A package is tied to a login account. Reject the upgrade if the
  --     member has no profiles (login) row — an account must be created
  --     from their details first.
  if not exists (
    select 1 from public.profiles where member_id = p_member_id
  ) then
    raise exception
      'Member % has no login account; create one before availing a package',
      p_member_id;
  end if;

  -- 2. Current package rank (0 if no package). Drives BOTH the upgrade
  --    validation and the "is this a real upgrade?" bonus gate below.
  select coalesce(pkgs.hierarchy_rank, 0)
    into v_current_rank
    from public.members m
    left join public.packages pkgs on pkgs.id = m.package_id
    where m.id = p_member_id;

  -- 3. Target package: rank, name, price (for validation + the ledger label).
  select pkgs.hierarchy_rank, pkgs.name, pkgs.price
    into v_target_rank, v_target_name, v_target_price
    from public.packages pkgs
    where pkgs.id = p_target_package_id;

  if not found then
    raise exception 'Target package not found (id=%)', p_target_package_id;
  end if;

  -- 4. Upgrade-only: target must be a strictly higher tier. Going from
  --    no package (rank 0) to any package is a valid move — this is the
  --    Member → Verified Reseller transition (still allowed, just unpaid).
  if v_target_rank <= v_current_rank then
    raise exception 'Invalid upgrade: target rank (%) must be greater than current rank (%)',
      v_target_rank, v_current_rank;
  end if;

  -- 5. Change the member's package
  update public.members
    set package_id = p_target_package_id
    where id = p_member_id;

  -- 5b. Role follows the package: anyone holding a package is a Verified
  --     Reseller. Promote the member and sync their login account so an
  --     upgrade from no package grants reseller access immediately.
  --     Scoped to the member/reseller domain so staff roles are preserved.
  update public.members
    set role = 'Verified Reseller'
    where id = p_member_id
      and (role in ('Member', 'Verified Reseller') or role is null);

  update public.profiles p
    set role = 'reseller'
    where p.member_id = p_member_id
      and p.role in ('member', 'reseller');

  -- 6. Direct referrer
  select m.referrer_id
    into v_referrer_id
    from public.members m
    where m.id = p_member_id;

  -- 6b. The upgrade referral bonus is drawn from the REFERRER'S OWN package
  --     (consistent with every other bonus), not the target package.
  if v_referrer_id is not null then
    select coalesce(rp.upgrade_referral_bonus, 0)
      into v_upgrade_bonus
      from public.members rm
      left join public.packages rp on rp.id = rm.package_id
      where rm.id = v_referrer_id;
  end if;

  -- 7. Pay the upgrade referral bonus — ONLY for a genuine upgrade, i.e. the
  --    member already held a package (v_current_rank > 0). A first availment
  --    (no package → a package) is a promotion, not an upgrade, so it pays
  --    nothing. The Chairman's Bonus is never touched by upgrades.
  if v_referrer_id is not null
     and v_current_rank > 0
     and coalesce(v_upgrade_bonus, 0) > 0 then
    -- 7a. Wallet ledger entry (drives the live earnings computation)
    insert into public.member_transactions (
      user_id, member_id, item_name, quantity, price, timestamp
    ) values (
      auth.uid(),
      v_referrer_id,
      'Upgrade Bonus — ' || v_target_name,
      1,
      v_upgrade_bonus,
      now()
    );

    -- 7b. Earnings History entry written at upgrade time so the referrer
    --     sees the transaction immediately. Totals carry forward from the
    --     latest snapshot; only the upgrade component and the total move.
    select total_earnings, balance,
           indirect_bonus, group_sales, passive_income,
           repeat_purchase, chairman_bonus, upgrade_bonus
      into v_last
      from public.earnings_history
      where member_id = v_referrer_id
      order by recorded_at desc
      limit 1;

    insert into public.earnings_history (
      member_id, total_earnings, balance,
      earnings_delta, balance_delta,
      indirect_bonus, group_sales, passive_income,
      repeat_purchase, chairman_bonus, upgrade_bonus
    ) values (
      v_referrer_id,
      coalesce(v_last.total_earnings, 0) + v_upgrade_bonus,
      coalesce(v_last.balance, 0),
      v_upgrade_bonus,
      0,
      coalesce(v_last.indirect_bonus, 0),
      coalesce(v_last.group_sales, 0),
      coalesce(v_last.passive_income, 0),
      coalesce(v_last.repeat_purchase, 0),
      coalesce(v_last.chairman_bonus, 0),
      coalesce(v_last.upgrade_bonus, 0) + v_upgrade_bonus
    );
  end if;
end;
$$;
