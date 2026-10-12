-- ═══════════════════════════════════════════════════════════════════
-- Migration v3 — Bug-fix batch (safe to re-run on the live database)
--
--  A. Guarantee every earnings_history component column exists
--     (fixes: upgrade bonus paid but missing from Earnings History —
--      the client's snapshot insert references upgrade_bonus and fails
--      silently when the column is absent).
--  B. members.is_deleted for soft deletion
--     (fixes: deleting a referral erased the referrer's historical
--      earnings — members are now flagged, never removed, so the
--      referral tree and all past bonuses stay intact).
--  C. process_package_upgrade v2 — same strict scope as before
--     (change package_id + pay the upgrade referral bonus, NOTHING
--      else; it contains no Chairman's Bonus logic) and now ALSO
--      writes the referrer's Earnings History entry at upgrade time.
--  D. member-ids storage bucket + policies so admin ID-photo uploads
--     cannot fail silently (fixes: photo upload not verifying member).
-- ═══════════════════════════════════════════════════════════════════

-- ── A. earnings_history component columns (idempotent) ─────────────
alter table public.earnings_history add column if not exists indirect_bonus  integer not null default 0;
alter table public.earnings_history add column if not exists group_sales     integer not null default 0;
alter table public.earnings_history add column if not exists passive_income  integer not null default 0;
alter table public.earnings_history add column if not exists repeat_purchase integer not null default 0;
alter table public.earnings_history add column if not exists chairman_bonus  integer not null default 0;
alter table public.earnings_history add column if not exists upgrade_bonus   integer not null default 0;

-- ── B. Soft-delete flag on members (idempotent) ────────────────────
alter table public.members add column if not exists is_deleted boolean not null default false;

-- ── C. Upgrade RPC v2 ──────────────────────────────────────────────
-- Scope is strictly: validate tier, set package_id, pay the upgrade
-- referral bonus (member_transactions + earnings_history). The
-- Chairman's Bonus is never touched here — it is derived from
-- registration-time sale snapshots and only matures on Fridays.
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
  v_last              record;
begin
  -- 1. Current package rank (0 if no package)
  select coalesce(pkgs.hierarchy_rank, 0)
    into v_current_rank
    from public.members m
    left join public.packages pkgs on pkgs.id = m.package_id
    where m.id = p_member_id;

  if not found then
    raise exception 'Member not found (id=%)', p_member_id;
  end if;

  -- 2. Target package: rank, name, price, and the upgrade bonus
  select pkgs.hierarchy_rank, pkgs.name, pkgs.price, pkgs.upgrade_referral_bonus
    into v_target_rank, v_target_name, v_target_price, v_upgrade_bonus
    from public.packages pkgs
    where pkgs.id = p_target_package_id;

  if not found then
    raise exception 'Target package not found (id=%)', p_target_package_id;
  end if;

  -- 3. Upgrade-only: target must be a strictly higher tier
  if v_target_rank <= v_current_rank then
    raise exception 'Invalid upgrade: target rank (%) must be greater than current rank (%)',
      v_target_rank, v_current_rank;
  end if;

  -- 4. Change the member's package — the only member mutation here
  update public.members
    set package_id = p_target_package_id
    where id = p_member_id;

  -- 5. Direct referrer
  select m.referrer_id
    into v_referrer_id
    from public.members m
    where m.id = p_member_id;

  -- 6. Pay the upgrade referral bonus (and nothing else)
  if v_referrer_id is not null and v_upgrade_bonus > 0 then
    -- 6a. Wallet ledger entry (drives the live earnings computation)
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

    -- 6b. Earnings History entry, written at upgrade time so the
    --     referrer sees the transaction without having to open the
    --     earnings tab first. Totals carry forward from the latest
    --     snapshot; only the upgrade component and total move.
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
      v_upgrade_bonus,   -- the exact bonus amount as the delta
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

-- ── D. member-ids storage bucket + open policies (idempotent) ──────
-- The app uploads admin-captured ID photos with the anon key; a
-- missing bucket or missing policy made uploads fail silently, which
-- in turn blocked the Verified Reseller promotion.
insert into storage.buckets (id, name, public)
values ('member-ids', 'member-ids', true)
on conflict (id) do nothing;

drop policy if exists "member-ids read"   on storage.objects;
drop policy if exists "member-ids write"  on storage.objects;
drop policy if exists "member-ids update" on storage.objects;
create policy "member-ids read"   on storage.objects for select using (bucket_id = 'member-ids');
create policy "member-ids write"  on storage.objects for insert with check (bucket_id = 'member-ids');
create policy "member-ids update" on storage.objects for update using (bucket_id = 'member-ids') with check (bucket_id = 'member-ids');
