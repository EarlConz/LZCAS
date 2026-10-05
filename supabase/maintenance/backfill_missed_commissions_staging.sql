-- ═══════════════════════════════════════════════════════════════════
-- STAGING ONLY — pay the commissions staging's sales missed before v71
--
-- ⛔ Never on production. It refuses to run where trigger-written Group
--    Sales rows already exist (production has them), but don't rely on that.
--
-- Run AFTER migration v71. Until v71, staging had no commission triggers
-- (diagnose_recent_commissions.sql, section 1), so no sale ever paid Group
-- Sales and no first package availment paid a referral bonus. This pays
-- them now, the way the triggers would have:
--
--   1. Group Sales: a no-op update of every product sale with a buyer
--      fires v71's update trigger, which writes each sale's Group Sales
--      (Direct and Indirect) at the referrers' CURRENT package rates.
--   2. Referral bonuses: for each member's FIRST package availment, the
--      same Direct Referral, Chairman's Bonus and Indirect Referral rows
--      v27's trigger writes (min-tier amounts), skipping any already paid.
--
-- Uses today's referrer links and packages, not those at the time of each
-- sale: fine for test data. One transaction: all or nothing.
-- Afterwards, run sections 3 and 4 of diagnose_recent_commissions.sql.
-- ═══════════════════════════════════════════════════════════════════

begin;

do $$
begin
  if not exists (select 1 from pg_trigger
                  where tgname = 'trg_sync_group_sales_upd' and not tgisinternal) then
    raise exception 'Apply migration v71 first: the commission triggers are missing.';
  end if;
  if exists (select 1 from public.member_transactions
              where sale_id is not null
                and item_name in ('Group Sales (Direct)', 'Group Sales (Indirect)')) then
    raise exception 'Group Sales rows written by the trigger already exist here. This script is for staging before v71 only.';
  end if;
end $$;

-- ── 1. Group Sales for every product sale with a buyer ─────────────
update public.sales
   set quantity = quantity
 where package_id is null
   and buyer_id is not null
   and coalesce(quantity, 0) > 0;

-- ── 2. Referral bonuses for each first package availment ───────────
do $$
declare
  r record;
begin
  for r in
    select distinct on (s.buyer_id)
           s.buyer_id, s.package_id, s."timestamp" as ts
      from public.sales s
     where s.package_id is not null and s.buyer_id is not null
     order by s.buyer_id, s."timestamp", s.id
  loop
    -- L1 Direct Referral (min-tier)
    insert into public.member_transactions
      (user_id, member_id, item_id, item_name, quantity, price, timestamp)
    select a1.user_id, a1.id, r.buyer_id, 'Direct Referral', 1,
           public.referral_bonus_min_tier(a1.package_id, r.package_id, 'direct'), r.ts
      from public.members m
      join public.members a1 on a1.id = m.referrer_id
     where m.id = r.buyer_id
       and a1.is_deleted = false
       and a1.package_id is not null
       and public.referral_bonus_min_tier(a1.package_id, r.package_id, 'direct') > 0
       and not exists (select 1 from public.member_transactions t
                        where t.member_id = a1.id and t.item_id = r.buyer_id
                          and t.item_name ilike 'Direct Referral%');

    -- L1 Chairman's Bonus (min-tier)
    insert into public.member_transactions
      (user_id, member_id, item_id, item_name, quantity, price, timestamp)
    select a1.user_id, a1.id, r.buyer_id, 'Chairman Bonus', 1,
           public.referral_bonus_min_tier(a1.package_id, r.package_id, 'chairman'), r.ts
      from public.members m
      join public.members a1 on a1.id = m.referrer_id
     where m.id = r.buyer_id
       and a1.is_deleted = false
       and a1.package_id is not null
       and public.referral_bonus_min_tier(a1.package_id, r.package_id, 'chairman') > 0
       and not exists (select 1 from public.member_transactions t
                        where t.member_id = a1.id and t.item_id = r.buyer_id
                          and t.item_name ilike 'Chairman Bonus%');

    -- L2 Indirect Referral (min-tier)
    insert into public.member_transactions
      (user_id, member_id, item_id, item_name, quantity, price, timestamp)
    select a2.user_id, a2.id, r.buyer_id, 'Indirect Referral', 1,
           public.referral_bonus_min_tier(a2.package_id, r.package_id, 'indirect'), r.ts
      from public.members m
      join public.members a1 on a1.id = m.referrer_id
      join public.members a2 on a2.id = a1.referrer_id
     where m.id = r.buyer_id
       and a2.is_deleted = false
       and a2.package_id is not null
       and public.referral_bonus_min_tier(a2.package_id, r.package_id, 'indirect') > 0
       and not exists (select 1 from public.member_transactions t
                        where t.member_id = a2.id and t.item_id = r.buyer_id
                          and t.item_name ilike 'Indirect Referral%');
  end loop;
end $$;

-- What the ledger holds now, by kind (the script's output):
select item_name, count(*) as rows, sum(price) as total
  from public.member_transactions
 where item_name in ('Group Sales (Direct)', 'Group Sales (Indirect)',
                     'Direct Referral', 'Chairman Bonus', 'Indirect Referral')
 group by item_name
 order by item_name;

commit;
