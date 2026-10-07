-- ═══════════════════════════════════════════════════════════════════
-- Migration v60 — Reducing stock is one step the database checks
--
-- Independent of the delivery chain: touches only items and
-- stock_movements, which production has.
--
-- ── The gap ────────────────────────────────────────────────────────
-- Edit Product's "Reduce Stock" (and an admin approving an inventory
-- user's reduction request) ran in the app: read the item's stock, check
-- it was enough, then write the new figure and a stock_movements row as
-- separate calls. Two reductions at the same moment could both read the
-- same stock and both write, so one was lost and the stock ended wrong;
-- and nothing in the database stopped a reduction past zero.
--
-- reduce_item_stock does it in one transaction. It locks the item row, so
-- a second reduction waits and then sees the first one's result; refuses
-- when the stock is too low, saying how much there is; writes the new
-- stock and its status (with the same category threshold v52 uses for
-- order sales); and logs the stock_out movement.
--
-- The refusal carries the current stock in the error's `detail` and the
-- tag 'stock_too_low' in its `hint`, so the app can show "Stock is now 20"
-- rather than a bare "failed".
--
-- ── Not covered here, on purpose ───────────────────────────────────
-- POS sales and sale edits also lower stock from the app. A blanket
-- `check (stock >= 0)` would make an oversold till sale fail with a raw
-- database error, which is a change to the till, not to Edit Product.
-- Branch transfers already check inside their own functions (v30–v32),
-- and delivery sales clamp at zero (v52).
--
-- Safe to re-run. Rollback:
--   supabase/rollbacks/rollback_reduce_item_stock_v60.sql
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.reduce_item_stock(
  p_item_id      bigint,
  p_quantity     integer,
  p_reason       text,
  -- An admin approving an inventory user's request credits the movement to
  -- the person who asked for it. Admins only.
  p_on_behalf_of uuid default null
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name   text;
  v_stock  integer;
  v_thresh integer;
begin
  if not public.is_staff() then
    raise exception 'Not authorized: staff role required to change stock';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Enter an amount of 1 or more to reduce';
  end if;
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'A reason is required for stock reduction';
  end if;
  if p_on_behalf_of is not null and not public.is_admin() then
    raise exception 'Not authorized: only an admin records a reduction for someone else';
  end if;

  -- The lock is the point: a second reduction of the same item waits here,
  -- then reads the stock this one leaves.
  select name, stock into v_name, v_stock
    from public.items where id = p_item_id for update;
  if v_name is null then
    raise exception 'Item not found';
  end if;

  if v_stock < p_quantity then
    raise exception using
      message = format('Only %s in stock, so you can reduce by at most %s.', v_stock, v_stock),
      detail  = v_stock::text,
      hint    = 'stock_too_low';
  end if;

  v_stock := v_stock - p_quantity;

  select coalesce(
           c.low_stock_threshold,
           (select value::int from public.app_config where key = 'low_stock_threshold'),
           50)
    into v_thresh
    from public.items i
    left join public.categories c on c.name = i.category
   where i.id = p_item_id;

  update public.items
     set stock        = v_stock,
         status       = case
                          when v_stock <= 0        then 'Out of Stock'
                          when v_stock <  v_thresh then 'Low Stock'
                          else 'Good'
                        end,
         last_updated = now()
   where id = p_item_id;

  insert into public.stock_movements
    (user_id, item_id, item_name, quantity, movement_type, reason, created_at)
  values
    (coalesce(p_on_behalf_of, auth.uid()), p_item_id, v_name, p_quantity,
     'stock_out', btrim(p_reason), now());

  return v_stock;
end;
$$;

revoke all on function public.reduce_item_stock(bigint, integer, text, uuid) from public;
grant execute on function public.reduce_item_stock(bigint, integer, text, uuid) to authenticated;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (60, 'reduce_item_stock')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. The function exists:
--      select pg_get_function_identity_arguments(oid)
--        from pg_proc where proname = 'reduce_item_stock';
-- 2. In the app (Edit Product on an item with stock 30):
--      • type 50 in Amount to reduce: an error under the box, Save off.
--      • reduce 10 with a reason: stock 20, one stock_out movement.
--      • open Edit Product on two screens at 20; reduce 15 on one, then 15
--        on the other: the second is refused with "Stock is now 5".
