-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK for migration_v28_branch_cashier_role.sql
--
-- Restores is_staff() to the three back-office roles (admin, cashier,
-- inventory), removing branch_cashier's staff-level DB access. Safe to run;
-- any existing branch_cashier accounts simply lose write access (and the app
-- would 403 them). Nothing else is affected.
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('admin', 'cashier', 'inventory')
  );
$$;
