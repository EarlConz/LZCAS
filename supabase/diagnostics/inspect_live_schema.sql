-- ═══════════════════════════════════════════════════════════════════
-- INSPECT LIVE SCHEMA (read-only) — introspects the actual database
-- catalog so we know exactly what is deployed, independent of repo files.
--
-- Supabase's SQL editor shows only the LAST statement's result, so RUN EACH
-- NUMBERED QUERY SEPARATELY and paste each result back. Writes nothing.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Tables & columns ──────────────────────────────────────────────
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
order by table_name, ordinal_position;

-- ── 2. Functions (name, args, returns, language, security definer) ────
select p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as args,
       pg_get_function_result(p.oid) as returns,
       l.lanname as language,
       p.prosecdef as security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_language l on l.oid = p.prolang
where n.nspname = 'public'
order by p.proname;

-- ── 3. Triggers ──────────────────────────────────────────────────────
select event_object_table as table_name, trigger_name,
       action_timing, event_manipulation
from information_schema.triggers
where trigger_schema = 'public'
order by event_object_table, trigger_name;

-- ── 4. RLS enabled per table ─────────────────────────────────────────
select c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;

-- ── 5. RLS policies (the part that matters for the new role) ─────────
select tablename, policyname, cmd, qual as using_expr, with_check
from pg_policies
where schemaname = 'public'
order by tablename, cmd, policyname;

-- ── 6. Row counts (data footprint) ───────────────────────────────────
select 'members' t, count(*) n from public.members
union all select 'profiles',            count(*) from public.profiles
union all select 'packages',            count(*) from public.packages
union all select 'items',               count(*) from public.items
union all select 'categories',          count(*) from public.categories
union all select 'sales',               count(*) from public.sales
union all select 'member_transactions', count(*) from public.member_transactions
union all select 'stock_movements',     count(*) from public.stock_movements
union all select 'pending_requests',    count(*) from public.pending_requests
union all select 'withdrawal_requests', count(*) from public.withdrawal_requests
union all select 'earnings_history',    count(*) from public.earnings_history
order by t;

-- ── 7. Which login roles actually exist ──────────────────────────────
select role, count(*) from public.profiles group by role order by count(*) desc;

-- ── 8. Exact is_staff() definition (drives the new role's RLS) ───────
select pg_get_functiondef('public.is_staff()'::regprocedure);
