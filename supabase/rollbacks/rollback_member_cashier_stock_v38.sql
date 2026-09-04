-- Rollback for migration v38 — member-facing cashier stock discovery.
--
-- Drops the SECURITY DEFINER function that let members read branch
-- cashiers' on-hand stock. Applying this hides every branch from the
-- member "Nearest Cashiers" screen again (branches would all appear
-- out of stock).

drop function if exists public.member_branch_stock();
