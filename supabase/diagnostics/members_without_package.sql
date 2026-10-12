-- ═══════════════════════════════════════════════════════════════════
-- Members with no package (read-only; safe on production)
--
-- From 2026-10-06 every member must avail a package (the client: only
-- resellers get accounts). Add member now refuses one without a package.
-- This lists the members who already exist without one, so the client
-- can decide what happens to them.
--
-- Writes nothing. Deleted members are left out.
-- Run each numbered query on its own (the SQL editor shows only the
-- last result).
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Summary ─────────────────────────────────────────────────────
select count(*)                                              as members,
       count(*) filter (where m.package_id is not null)      as with_package,
       count(*) filter (where m.package_id is null)          as without_package,
       count(*) filter (where m.package_id is null
                          and coalesce(trim(m.email), '') <> '') as without_package_but_login,
       count(*) filter (where m.package_id is null
                          and m.role = 'Verified Reseller')  as without_package_but_reseller_role
  from public.members m
 where not m.is_deleted;

-- ── 2. The list ────────────────────────────────────────────────────
-- has_login: the member can sign in (an email on the member, as the app
--            checks it).
-- package_sales: package availments on record for them. Above 0 with no
--            package means the package was taken off later (Edit member's
--            "remove package").
-- product_lines / last_purchase: whether they still buy.
-- direct_referrals: members they referred (they would lose those
--            commissions if removed).
select m.id,
       trim(both ', ' from coalesce(m.last_name, '') || ', ' || coalesce(m.first_name, '')) as name,
       m.contact_no,
       m.role,
       coalesce(trim(m.email), '') <> ''                     as has_login,
       coalesce(nullif(trim(coalesce(r.first_name, '') || ' ' || coalesce(r.last_name, '')), ''),
                m.referrer)                                   as referred_by,
       (select count(*) from public.sales s
         where s.buyer_id = m.id and s.package_id is not null) as package_sales,
       (select count(*) from public.sales s
         where s.buyer_id = m.id and s.package_id is null)     as product_lines,
       (select max(s."timestamp") from public.sales s
         where s.buyer_id = m.id)                              as last_purchase,
       (select count(*) from public.members d
         where d.referrer_id = m.id and not d.is_deleted)      as direct_referrals
  from public.members m
  left join public.members r on r.id = m.referrer_id
 where not m.is_deleted
   and m.package_id is null
 order by m.last_name, m.first_name, m.id;
