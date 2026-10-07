-- ═══════════════════════════════════════════════════════════════════
-- Migration v26 — Upgrade Referral Bonus becomes MIN-TIER capped
--
-- Brings the Upgrade Referral Bonus in line with Direct/Indirect (v25): the
-- amount is the upgrade_referral_bonus of the LOWER-TIER package (by
-- hierarchy_rank) between the REFERRER's own package and the package the
-- downline upgraded TO — instead of always the referrer's own rate.
--
--   e.g. referrer on Elite, downline upgrades Starter → Ambassador:
--        min-tier(Elite, Ambassador) = Ambassador → the referrer earns the
--        Ambassador upgrade rate (600), not the Elite rate (1000).
--
-- Everything else about upgrade bonuses is unchanged:
--   • pays the DIRECT referrer only (no indirect),
--   • only for a GENUINE upgrade (downline already held a package),
--   • frozen as an 'Upgrade Bonus — <target>' ledger row.
--
-- NO CURRENT-DATA IMPACT: with only two tiers (Starter, Ambassador) the target
-- is always Ambassador and the referrer is Starter or Ambassador, so min-tier
-- already equals the old "referrer's own rate" — existing rows are unchanged
-- and no backfill is needed. This only changes behavior once a 3rd+ tier
-- (e.g. Elite) exists and a referrer can outrank the target.
--
-- Two parts: (1) extend the helper to know 'upgrade', (2) redefine
-- process_package_upgrade to use it. DB-only, no app rebuild.
--
-- Rollback: rollbacks/rollback_upgrade_bonus_v17.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Teach referral_bonus_min_tier the 'upgrade' kind ──────────────
create or replace function public.referral_bonus_min_tier(
  p_earner_pkg   bigint,
  p_referral_pkg bigint,
  p_kind         text
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  r_earner   integer;
  r_referral integer;
  chosen_pkg bigint;
  amt        integer;
begin
  if p_earner_pkg is null or p_referral_pkg is null then
    return 0;
  end if;

  select hierarchy_rank into r_earner   from public.packages where id = p_earner_pkg;
  select hierarchy_rank into r_referral from public.packages where id = p_referral_pkg;

  chosen_pkg := case
    when coalesce(r_referral, 0) < coalesce(r_earner, 0) then p_referral_pkg
    else p_earner_pkg
  end;

  select case p_kind
           when 'indirect' then indirect_referral_bonus
           when 'upgrade'  then upgrade_referral_bonus
           else direct_referral_bonus
         end
    into amt
    from public.packages where id = chosen_pkg;

  return coalesce(amt, 0);
end;
$$;

-- ── 2. Upgrade flow uses min-tier for the bonus ──────────────────────
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
  v_referrer_pkg     bigint;
  v_last             record;
begin
  -- 0. Authorization
  if not public.is_staff() then
    raise exception 'Not authorized: staff role required to process an upgrade';
  end if;

  -- 1. Lock the member row
  perform 1 from public.members where id = p_member_id for update;
  if not found then
    raise exception 'Member not found (id=%)', p_member_id;
  end if;

  -- 1b. Must have a login account
  if not exists (select 1 from public.profiles where member_id = p_member_id) then
    raise exception
      'Member % has no login account; create one before availing a package',
      p_member_id;
  end if;

  -- 2. Current rank (0 if no package)
  select coalesce(pkgs.hierarchy_rank, 0)
    into v_current_rank
    from public.members m
    left join public.packages pkgs on pkgs.id = m.package_id
    where m.id = p_member_id;

  -- 3. Target package
  select pkgs.hierarchy_rank, pkgs.name, pkgs.price
    into v_target_rank, v_target_name, v_target_price
    from public.packages pkgs
    where pkgs.id = p_target_package_id;
  if not found then
    raise exception 'Target package not found (id=%)', p_target_package_id;
  end if;

  -- 4. Upgrade-only: target must be a strictly higher tier
  if v_target_rank <= v_current_rank then
    raise exception 'Invalid upgrade: target rank (%) must be greater than current rank (%)',
      v_target_rank, v_current_rank;
  end if;

  -- 5. Change the member's package
  update public.members
    set package_id = p_target_package_id
    where id = p_member_id;

  -- 5b. Role follows the package
  update public.members
    set role = 'Verified Reseller'
    where id = p_member_id
      and (role in ('Member', 'Verified Reseller') or role is null);

  update public.profiles p
    set role = 'reseller'
    where p.member_id = p_member_id
      and p.role in ('member', 'reseller');

  -- 6. Direct referrer + their package
  select m.referrer_id into v_referrer_id
    from public.members m where m.id = p_member_id;

  if v_referrer_id is not null then
    select rm.package_id into v_referrer_pkg
      from public.members rm where rm.id = v_referrer_id;

    -- 6b. MIN-TIER: upgrade bonus = upgrade_referral_bonus of the lower-tier
    --     package between the referrer's own package and the target package
    --     the downline upgraded to. (Consistent with Direct/Indirect v25.)
    v_upgrade_bonus := public.referral_bonus_min_tier(
                         v_referrer_pkg, p_target_package_id, 'upgrade');
  end if;

  -- 7. Pay ONLY for a genuine upgrade (member already held a package)
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
