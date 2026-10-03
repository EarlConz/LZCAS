-- ═══════════════════════════════════════════════════════════════════
-- Diagnose: did a delivery order pay Group Sales to the buyer's upline?
--
-- READ-ONLY. Safe on staging and production: every statement is a SELECT.
--
-- Written for test G2 (2026-10-03, "referrer got nothing"). The commission
-- path is: the member confirms receipt → order_record_sales (v61) writes
-- one sales row per item → the v19 trigger on sales writes
-- 'Group Sales (Direct)' for the buyer's referrer and 'Group Sales
-- (Indirect)' for theirs, each at THEIR package's rate. Nothing is paid
-- when the referrer has no package, or a package whose rate is 0.
--
-- Run section 1, pick the order, put its id in sections 2–4.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. The latest finished delivery orders ─────────────────────────
select o.id, o.status, o.payment_method, o.sales_recorded_at,
       o.member_id, m.first_name || ' ' || m.last_name as buyer,
       o.updated_at
  from public.orders o
  join public.members m on m.id = o.member_id
 where o.status = 'Completed'
 order by o.updated_at desc
 limit 10;

-- ── 2. The buyer's upline and the rates they are paid at ───────────
-- Expect: referrer_id filled in, and direct_rate above 0. A null
-- referrer_id with referrer_text filled in means the name was typed but
-- never picked from the list, so no one is linked.
select 'buyer' as who, b.id, b.first_name || ' ' || b.last_name as name,
       b.referrer_id, b.referrer as referrer_text, null::text as package,
       null::int as direct_rate, null::int as indirect_rate
  from public.orders o join public.members b on b.id = o.member_id
 where o.id = '<order id>'
union all
select 'referrer', r.id, r.first_name || ' ' || r.last_name,
       r.referrer_id, r.referrer, p.name,
       p.group_sales_direct, p.group_sales_indirect
  from public.orders o
  join public.members b on b.id = o.member_id
  join public.members r on r.id = b.referrer_id
  left join public.packages p on p.id = r.package_id
 where o.id = '<order id>'
union all
select 'referrer''s referrer', rr.id, rr.first_name || ' ' || rr.last_name,
       rr.referrer_id, rr.referrer, p.name,
       p.group_sales_direct, p.group_sales_indirect
  from public.orders o
  join public.members b  on b.id = o.member_id
  join public.members r  on r.id = b.referrer_id
  join public.members rr on rr.id = r.referrer_id
  left join public.packages p on p.id = rr.package_id
 where o.id = '<order id>';

-- ── 3. The sales rows the order wrote ──────────────────────────────
-- Expect one row per item, buyer_id = the buyer, at the time it finished.
select s.id, s.item_name, s.quantity, s.price, s.buyer_id, s.payment_method, s."timestamp"
  from public.sales s
  join public.orders o on o.member_id = s.buyer_id
 where o.id = '<order id>'
   and s.payment_method is not null
   and s."timestamp" between o.sales_recorded_at - interval '5 seconds'
                         and o.sales_recorded_at + interval '5 seconds'
 order by s.id;

-- ── 4. The Group Sales those rows paid ─────────────────────────────
-- Rows here mean the commission WAS paid; if the referrer's screen showed
-- nothing, it had not refreshed (no live update reaches it).
select t.member_id, m.first_name || ' ' || m.last_name as paid_to,
       t.item_name, t.quantity, t.price, t."timestamp"
  from public.member_transactions t
  join public.members m on m.id = t.member_id
 where t.item_name like 'Group Sales%'
   and t.sale_id in (
     select s.id
       from public.sales s
       join public.orders o on o.member_id = s.buyer_id
      where o.id = '<order id>'
        and s.payment_method is not null
        and s."timestamp" between o.sales_recorded_at - interval '5 seconds'
                              and o.sales_recorded_at + interval '5 seconds')
 order by t.id;
