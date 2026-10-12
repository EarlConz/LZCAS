-- ═══════════════════════════════════════════════════════════════════
-- Audit: referral loops — members who are their own (in)direct referral
--
-- READ-ONLY. Safe on staging and production: every statement is a SELECT.
-- Run each section on its own in the SQL editor and keep the output.
--
-- Why it happens (found 2026-10-03):
--   * The Edit Member form stops a member choosing THEMSELVES as referrer,
--     but not someone below them. If B was referred by A, editing A to be
--     referred by B makes a loop A → B → A. A's direct referrals then
--     include B, and B's direct referrals (A's "indirect") include A.
--   * Nothing in the database refuses a loop or a self-referral.
--   * The member pages also match the old free-text `referrer` field by
--     NAME, so two members with the same name, or a member whose referrer
--     text is their own name, show up in the wrong lists.
--
-- Why it matters: the commission triggers walk referrer_id up the chain,
-- so in a loop a member is paid on their OWN purchase:
--   * Group Sales (Indirect) on their own product purchases (v19), and
--     Group Sales (Direct) when referrer_id is themselves;
--   * Indirect Referral (and, self-referred, Direct Referral / Chairman
--     Bonus / upgrade bonus) on their own package availment (v25–v27).
-- Section 6 shows how much, if any, was paid that way.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Self-referrals: referrer_id is the member themselves ────────
select m.id, m.first_name, m.last_name, m.role, m.referrer_id, m.referrer as referrer_text
  from public.members m
 where m.referrer_id = m.id
 order by m.id;

-- ── 2. Two-way loops: A was referred by B and B by A ───────────────
select a.id  as member_a, a.first_name || ' ' || a.last_name as name_a,
       b.id  as member_b, b.first_name || ' ' || b.last_name as name_b,
       -- The lower id was added first; the loop was most likely made by
       -- a later edit of that member (no edit history is kept).
       least(a.id, b.id) as probably_edited
  from public.members a
  join public.members b on b.id = a.referrer_id
 where b.referrer_id = a.id
   and a.id < b.id
 order by a.id;

-- ── 3. Loops of any length (A → B → C → A …) ───────────────────────
with recursive walk as (
  select m.id as start_id, m.referrer_id as at_id, array[m.id] as path, 1 as depth
    from public.members m
   where m.referrer_id is not null
  union all
  select w.start_id, m.referrer_id, w.path || m.id, w.depth + 1
    from walk w
    join public.members m on m.id = w.at_id
   where m.referrer_id is not null
     and not (m.id = any(w.path))
     and w.depth < 50
)
select start_id, path || at_id as loop_path, depth as loop_length
  from walk
 where at_id = start_id
 order by depth, start_id;

-- ── 4. The old free-text referrer field ────────────────────────────
-- 4a. Referrer text equal to the member's own name.
select m.id, m.first_name, m.last_name, m.referrer as referrer_text, m.referrer_id
  from public.members m
 where lower(trim(coalesce(m.referrer, ''))) = lower(trim(coalesce(m.first_name, '') || ' ' || coalesce(m.last_name, '')))
   and trim(coalesce(m.referrer, '')) <> ''
 order by m.id;

-- 4b. Names shared by more than one member: name matching can't tell them
-- apart, so their referral lists can mix.
select lower(trim(first_name || ' ' || last_name)) as full_name, count(*) as members,
       array_agg(id order by id) as ids
  from public.members
 where is_deleted = false
 group by 1
having count(*) > 1
 order by members desc, full_name;

-- 4c. Text and id disagree: the text names someone other than the id.
select m.id, m.first_name || ' ' || m.last_name as member,
       m.referrer as referrer_text,
       r.id as referrer_id, r.first_name || ' ' || r.last_name as referrer_by_id
  from public.members m
  join public.members r on r.id = m.referrer_id
 where trim(coalesce(m.referrer, '')) <> ''
   and lower(trim(m.referrer)) <> lower(trim(r.first_name || ' ' || r.last_name))
 order by m.id;

-- ── 5. What the member pages show: members in their own indirect list ─
-- Indirect = members whose referrer_id is one of this member's directs.
select m.id, m.first_name || ' ' || m.last_name as member
  from public.members m
 where exists (
   select 1
     from public.members d                    -- m's direct referrals
     join public.members i on i.referrer_id = d.id
    where d.referrer_id = m.id
      and i.id = m.id
 )
 order by m.id;

-- ── 6. Money: commissions paid to a member for their OWN purchase ──
-- 6a. Group Sales credited to the buyer of the very sale.
select t.member_id, mm.first_name || ' ' || mm.last_name as member,
       t.item_name, count(*) as rows, sum(t.price) as total
  from public.member_transactions t
  join public.sales s on s.id = t.sale_id
  join public.members mm on mm.id = t.member_id
 where t.item_name like 'Group Sales%'
   and s.buyer_id = t.member_id
 group by t.member_id, member, t.item_name
 order by total desc;

-- 6b. Package bonuses about themselves (item_id is the referred member).
select t.member_id, mm.first_name || ' ' || mm.last_name as member,
       t.item_name, count(*) as rows, sum(t.price) as total
  from public.member_transactions t
  join public.members mm on mm.id = t.member_id
 where t.item_id = t.member_id
   and (t.item_name ilike 'Direct Referral%'
        or t.item_name ilike 'Indirect Referral%'
        or t.item_name ilike 'Chairman Bonus%')
 group by t.member_id, member, t.item_name
 order by total desc;

-- 6c. The rows behind 6a and 6b, newest first (for a refund decision).
select t.id, t.member_id, t.item_name, t.price, t.timestamp, t.sale_id, t.item_id
  from public.member_transactions t
  left join public.sales s on s.id = t.sale_id
 where (t.item_name like 'Group Sales%' and s.buyer_id = t.member_id)
    or (t.item_id = t.member_id and (t.item_name ilike 'Direct Referral%'
        or t.item_name ilike 'Indirect Referral%' or t.item_name ilike 'Chairman Bonus%'))
 order by t.timestamp desc
 limit 200;
