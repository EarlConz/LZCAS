-- ═══════════════════════════════════════════════════════════════════
-- Diagnose: were commissions paid for the latest sales?
--
-- READ-ONLY. Run on STAGING, each section on its own, and send the output.
--
-- Written for Part 4 (2026-10-05): G2 and X3 say Group Sales and referral
-- bonuses did not reach the referrer, for counter (POS) and delivery
-- purchases alike. The rules, for reference:
--   • Group Sales (v19): on every product sale with a buyer, the buyer's
--     referrer gets their package's group_sales_direct × quantity, and the
--     referrer's referrer group_sales_indirect × quantity. Nothing when the
--     referrer has no package, or the rate is 0.
--   • Referral bonuses (v25–v27): only on a member's FIRST package
--     availment, to referrers who hold a package, at the LOWER of the two
--     packages' rates (min-tier). Adding a member without a package pays
--     nothing.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. The triggers that pay commissions exist and are enabled ─────
-- Expect 4 rows, tgenabled = 'O' on each:
--   trg_sync_group_sales_ins, trg_sync_group_sales_upd,
--   trg_remove_group_sales_del, trg_crystallize_referral_on_availment
select tgname, tgenabled
  from pg_trigger
 where tgrelid = 'public.sales'::regclass and not tgisinternal
 order by tgname;

-- ── 2. The package rates (0 or null pays nothing) ──────────────────
select id, name, hierarchy_rank,
       group_sales_direct, group_sales_indirect,
       direct_referral_bonus, indirect_referral_bonus
  from public.packages
 order by hierarchy_rank;

-- ── 3. The last 30 sales and what each paid ────────────────────────
-- For each sale: the buyer, their referrer and that referrer's package and
-- direct rate, and the Group Sales rows the sale wrote. A product sale
-- with a buyer, a referrer, a package and a rate above 0, but 0 rows in
-- gs_rows, is the bug.
select s.id as sale_id, s."timestamp", s.item_name, s.quantity,
       s.package_id as availed_pkg, s.payment_method,
       s.buyer_id, b.first_name || ' ' || b.last_name as buyer,
       b.referrer_id, r.first_name || ' ' || r.last_name as referrer,
       rp.name as referrer_pkg, rp.group_sales_direct as referrer_rate,
       (select count(*) from public.member_transactions t
         where t.sale_id = s.id and t.item_name like 'Group Sales%') as gs_rows,
       (select coalesce(sum(t.price), 0) from public.member_transactions t
         where t.sale_id = s.id and t.item_name like 'Group Sales%') as gs_paid
  from public.sales s
  left join public.members b  on b.id = s.buyer_id
  left join public.members r  on r.id = b.referrer_id
  left join public.packages rp on rp.id = r.package_id
 order by s.id desc
 limit 30;

-- ── 4. The ledger rows written in the last 2 days ──────────────────
-- What was actually paid, to whom, for what.
select t.id, t."timestamp", t.member_id,
       m.first_name || ' ' || m.last_name as paid_to,
       t.item_name, t.quantity, t.price, t.sale_id, t.item_id
  from public.member_transactions t
  join public.members m on m.id = t.member_id
 where t."timestamp" > now() - interval '2 days'
 order by t.id desc
 limit 60;
