-- rollback_branch_stock_v30.sql
-- Reverts migration_v30_branch_stock.sql. Drops the branch-stock system
-- entirely (tables, view, and RPCs). Branch cashiers fall back to the shared
-- central stock. Run only if you want to remove the feature completely.

drop function if exists public.record_branch_sale(bigint, integer, integer, bigint, text, timestamptz);
drop function if exists public.adjust_branch_stock(bigint, uuid, integer, text);
drop function if exists public.return_branch_stock(bigint, uuid, integer, text);
drop function if exists public.transfer_stock_to_branch(bigint, uuid, integer, text);
drop function if exists public.can_manage_branch_stock();

drop view if exists public.branch_stock_view;

drop table if exists public.stock_transfers;
drop table if exists public.branch_stock;
