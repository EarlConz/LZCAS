-- ═══════════════════════════════════════════════════════════════════
-- Migration v5 — Harden process_package_upgrade
--   • CRITICAL-2: reject non-staff callers (no more free self-upgrades
--     or referrer bonuses printed by hitting the RPC directly).
--   • HIGH-5: lock the member row so two concurrent upgrades (or a
--     client retry) can't both pass validation and double-pay the bonus.
-- Safe to re-run. Requires is_staff() (from enable_rls_staff.sql).
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
  v_upgrade_bonus    integer;
  v_referrer_id      bigint;
  v_last             record;
begin
  -- 0. Authorization: only back-office staff may run an upgrade.
  --    SECURITY DEFINER runs as owner, so the caller MUST be re-checked
  --    here — a reseller calling this RPC directly is rejected.
  if not public.is_staff() then
    raise exception 'Not authorized: staff role required to process an upgrade';
  end if;

  -- 1. Lock the member row for the duration of this transaction so a
  --    concurrent upgrade / retry serializes behind us instead of
  --    re-reading the old rank and paying the bonus twice.
  perform 1 from public.members where id = p_member_id for update;
  if not found then
    raise exception 'Member not found (id=%)', p_member_id;
  end if;

  -- 2. Current package rank (0 if no package)
  select coalesce(pkgs.hierarchy_rank, 0)
    into v_current_rank
    from public.members m
    left join public.packages pkgs on pkgs.id = m.package_id
    where m.id = p_member_id;

  -- 3. Target package: rank, name, price, and the upgrade bonus
  select pkgs.hierarchy_rank, pkgs.name, pkgs.price, pkgs.upgrade_referral_bonus
    into v_target_rank, v_target_name, v_target_price, v_upgrade_bonus
    from public.packages pkgs
    where pkgs.id = p_target_package_id;

  if not found then
    raise exception 'Target package not found (id=%)', p_target_package_id;
  end if;

  -- 4. Upgrade-only: target must be a strictly higher tier. (After the
  --    row lock, a duplicate concurrent call now sees the NEW rank here
  --    and fails this check — the double-pay is closed.)
  if v_target_rank <= v_current_rank then
    raise exception 'Invalid upgrade: target rank (%) must be greater than current rank (%)',
      v_target_rank, v_current_rank;
  end if;

  -- 5. Change the member's package
  update public.members
    set package_id = p_target_package_id
    where id = p_member_id;

  -- 6. Direct referrer
  select m.referrer_id
    into v_referrer_id
    from public.members m
    where m.id = p_member_id;

  -- 7. Pay the upgrade referral bonus (and nothing else — the
  --    Chairman's Bonus is never touched by upgrades)
  if v_referrer_id is not null and v_upgrade_bonus > 0 then
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

    -- 7b. Earnings History entry written at upgrade time so the
    --     referrer sees the transaction immediately. Totals carry
    --     forward from the latest snapshot; only the upgrade
    --     component and the total move.
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
