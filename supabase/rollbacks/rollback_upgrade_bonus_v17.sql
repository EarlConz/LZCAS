-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK for migration_v26_upgrade_bonus_min_tier.sql
--
-- Restores the v17 Upgrade Referral Bonus: the amount is the REFERRER'S OWN
-- package upgrade_referral_bonus (no min-tier cap). Everything else (direct
-- referrer only, genuine-upgrade gate, frozen ledger row) is unchanged.
--
-- The referral_bonus_min_tier helper is left with the 'upgrade' branch in
-- place — it's harmless (this restored function doesn't call it). Existing
-- ledger rows are untouched (v26 changed no historical amounts).
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
  if not public.is_staff() then
    raise exception 'Not authorized: staff role required to process an upgrade';
  end if;

  perform 1 from public.members where id = p_member_id for update;
  if not found then
    raise exception 'Member not found (id=%)', p_member_id;
  end if;

  if not exists (select 1 from public.profiles where member_id = p_member_id) then
    raise exception
      'Member % has no login account; create one before availing a package',
      p_member_id;
  end if;

  select coalesce(pkgs.hierarchy_rank, 0)
    into v_current_rank
    from public.members m
    left join public.packages pkgs on pkgs.id = m.package_id
    where m.id = p_member_id;

  select pkgs.hierarchy_rank, pkgs.name, pkgs.price
    into v_target_rank, v_target_name, v_target_price
    from public.packages pkgs
    where pkgs.id = p_target_package_id;
  if not found then
    raise exception 'Target package not found (id=%)', p_target_package_id;
  end if;

  if v_target_rank <= v_current_rank then
    raise exception 'Invalid upgrade: target rank (%) must be greater than current rank (%)',
      v_target_rank, v_current_rank;
  end if;

  update public.members
    set package_id = p_target_package_id
    where id = p_member_id;

  update public.members
    set role = 'Verified Reseller'
    where id = p_member_id
      and (role in ('Member', 'Verified Reseller') or role is null);

  update public.profiles p
    set role = 'reseller'
    where p.member_id = p_member_id
      and p.role in ('member', 'reseller');

  select m.referrer_id into v_referrer_id
    from public.members m where m.id = p_member_id;

  if v_referrer_id is not null then
    select coalesce(rp.upgrade_referral_bonus, 0)
      into v_upgrade_bonus
      from public.members rm
      left join public.packages rp on rp.id = rm.package_id
      where rm.id = v_referrer_id;
  end if;

  if v_referrer_id is not null
     and v_current_rank > 0
     and coalesce(v_upgrade_bonus, 0) > 0 then

    insert into public.member_transactions (
      user_id, member_id, item_name, quantity, price, timestamp
    ) values (
      auth.uid(), v_referrer_id,
      'Upgrade Bonus — ' || v_target_name, 1, v_upgrade_bonus, now()
    );

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
      v_upgrade_bonus, 0,
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
