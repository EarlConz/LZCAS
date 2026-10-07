-- ═══════════════════════════════════════════════════════════════════
-- Migration v64 — POS sales that cannot oversell, and Edit Sale for admins
--
-- ── 1. pos_record_sale ─────────────────────────────────────────────
-- The central POS (main cashier, admin) checked stock in the app, then
-- wrote "stock was 5, sold 2, so 3". Two sales of the same product at the
-- same moment, or a sale while a delivery order completes, could each
-- write their own number: one sale vanished from stock, or the item sold
-- twice. Now the database takes the whole cart in one transaction: it
-- locks each product, refuses if any line wants more than is left, and
-- subtracts. All lines are recorded or none.
-- Branch cashiers keep record_branch_sale (v30), which already works so.
--
-- ── 2. admin_edit_sale_group ───────────────────────────────────────
-- Edit Sale (client decision 2026-10-03: admins only). One POS sale is
-- the rows one cashier recorded at one moment (same user_id, same
-- timestamp). Editing replaces those rows with the new lines and moves
-- stock by the difference, under the same locks. Deleting and inserting
-- sales fires the group-sales triggers (v19), so commissions follow.
-- Refused for sales that are not plain central POS sales: delivery
-- orders (payment_method set), package availments (package_id set) and
-- branch sales (their stock is the branch's, not central).
--
-- Requires: is_admin(), the categories table (v10). Safe to re-run.
-- Rollback: supabase/rollbacks/rollback_pos_sale_guard_v64.sql
-- ═══════════════════════════════════════════════════════════════════

-- Status as items_with_status computes it, for the items.status column the
-- app still writes after a stock change.
create or replace function public._item_status(p_stock integer, p_category text)
returns text
language sql
stable
set search_path = public
as $$
  select case
    when p_stock <= 0 then 'Out of Stock'
    when p_stock < coalesce(
      (select low_stock_threshold from public.categories where name = p_category), 50)
      then 'Low Stock'
    else 'Good'
  end;
$$;

-- ── 1. A POS sale ──────────────────────────────────────────────────
-- p_lines: [{"item_id": 1, "quantity": 2, "price": 450}, …]
create or replace function public.pos_record_sale(
  p_lines      jsonb,
  p_buyer_id   bigint      default null,
  p_buyer_name text        default null,
  p_timestamp  timestamptz default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ts    timestamptz := coalesce(p_timestamp, now());
  v_need  record;
  v_item  public.items%rowtype;
  v_line  record;
  v_short text[] := '{}';
  v_count integer := 0;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'cashier')
  ) then
    raise exception 'Only a cashier or an admin can record a POS sale';
  end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'The sale has no items';
  end if;

  -- Lock every product in the cart, in id order (two carts locking the
  -- same products in different orders would otherwise deadlock), and
  -- check each total against what is left.
  for v_need in
    select (l->>'item_id')::bigint as item_id, sum((l->>'quantity')::int) as qty
      from jsonb_array_elements(p_lines) l
     group by 1
     order by 1
  loop
    if v_need.qty is null or v_need.qty <= 0 then
      raise exception 'Quantities must be positive numbers';
    end if;
    select * into v_item from public.items where id = v_need.item_id for update;
    if not found then
      raise exception 'A product in this sale no longer exists';
    end if;
    if v_item.stock < v_need.qty then
      v_short := v_short || format('%s (need %s, have %s)', v_item.name, v_need.qty, v_item.stock);
    end if;
  end loop;

  if array_length(v_short, 1) > 0 then
    raise exception 'Not enough stock for: %', array_to_string(v_short, '; ');
  end if;

  for v_line in
    select (l->>'item_id')::bigint as item_id,
           (l->>'quantity')::int   as qty,
           coalesce((l->>'price')::int, 0) as price
      from jsonb_array_elements(p_lines) l
  loop
    update public.items
       set stock = stock - v_line.qty,
           last_updated = now(),
           status = public._item_status(stock - v_line.qty, category)
     where id = v_line.item_id
     returning * into v_item;

    insert into public.sales
      (user_id, item_id, item_name, quantity, price, buyer_id, buyer_name, timestamp)
    values
      (auth.uid(), v_line.item_id, v_item.name, v_line.qty, v_line.price,
       p_buyer_id, p_buyer_name, v_ts);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.pos_record_sale(jsonb, bigint, text, timestamptz) from public;
grant execute on function public.pos_record_sale(jsonb, bigint, text, timestamptz) to authenticated;

-- ── 2. Edit a POS sale (admins) ────────────────────────────────────
-- p_user_id + p_timestamp name the sale (the rows of one checkout).
-- p_lines: the sale as it should be, [{"item_id", "quantity", "price"}].
-- An empty list is refused: deleting a sale is its own action.
create or replace function public.admin_edit_sale_group(
  p_user_id   uuid,
  p_timestamp timestamptz,
  p_buyer_id  bigint,
  p_lines     jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orig    record;
  v_item    public.items%rowtype;
  v_line    record;
  v_short   text[] := '{}';
  v_buyer   text;
  v_count   integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can edit a sale';
  end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'A sale needs at least one item. To remove it, delete the sale instead.';
  end if;

  if not exists (
    select 1 from public.sales where user_id = p_user_id and timestamp = p_timestamp
  ) then
    raise exception 'This sale no longer exists. Refresh and try again.';
  end if;
  if exists (
    select 1 from public.sales
     where user_id = p_user_id and timestamp = p_timestamp
       and (payment_method is not null or package_id is not null or item_id <= 0)
  ) then
    raise exception 'Only counter (POS) sales can be edited here. Delivery orders and package availments cannot.';
  end if;
  if exists (
    select 1 from public.profiles where id = p_user_id and role = 'branch_cashier'
  ) then
    raise exception 'Branch sales cannot be edited here: their stock belongs to the branch.';
  end if;

  -- Per product: what the sale had, what it will have. Lock in id order.
  for v_orig in
    with before as (
      select item_id, sum(quantity) as qty
        from public.sales
       where user_id = p_user_id and timestamp = p_timestamp
       group by 1
    ), after as (
      select (l->>'item_id')::bigint as item_id, sum((l->>'quantity')::int) as qty
        from jsonb_array_elements(p_lines) l
       group by 1
    )
    select coalesce(b.item_id, a.item_id) as item_id,
           coalesce(a.qty, 0) - coalesce(b.qty, 0) as delta,
           coalesce(a.qty, 1) as new_qty
      from before b full join after a on a.item_id = b.item_id
     order by 1
  loop
    if v_orig.new_qty <= 0 then
      raise exception 'Quantities must be positive numbers';
    end if;
    select * into v_item from public.items where id = v_orig.item_id for update;
    if not found then
      raise exception 'A product in this sale no longer exists';
    end if;
    if v_orig.delta > 0 and v_item.stock < v_orig.delta then
      v_short := v_short || format('%s (%s more needed, %s left)', v_item.name, v_orig.delta, v_item.stock);
    end if;
  end loop;

  if array_length(v_short, 1) > 0 then
    raise exception 'Not enough stock for: %', array_to_string(v_short, '; ');
  end if;

  -- Stock moves by the difference only.
  update public.items i
     set stock = i.stock - d.delta,
         last_updated = now(),
         status = public._item_status(i.stock - d.delta, i.category)
    from (
      with before as (
        select item_id, sum(quantity) as qty
          from public.sales
         where user_id = p_user_id and timestamp = p_timestamp
         group by 1
      ), after as (
        select (l->>'item_id')::bigint as item_id, sum((l->>'quantity')::int) as qty
          from jsonb_array_elements(p_lines) l
         group by 1
      )
      select coalesce(b.item_id, a.item_id) as item_id,
             coalesce(a.qty, 0) - coalesce(b.qty, 0) as delta
        from before b full join after a on a.item_id = b.item_id
    ) d
   where i.id = d.item_id and d.delta <> 0;

  select nullif(trim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), '')
    into v_buyer
    from public.members where id = p_buyer_id;

  -- Replace the rows: the triggers take the old commissions out and put
  -- the new ones in.
  delete from public.sales where user_id = p_user_id and timestamp = p_timestamp;

  for v_line in
    select (l->>'item_id')::bigint as item_id,
           (l->>'quantity')::int   as qty,
           coalesce((l->>'price')::int, 0) as price
      from jsonb_array_elements(p_lines) l
  loop
    insert into public.sales
      (user_id, item_id, item_name, quantity, price, buyer_id, buyer_name, timestamp)
    select p_user_id, v_line.item_id, i.name, v_line.qty, v_line.price,
           p_buyer_id, v_buyer, p_timestamp
      from public.items i where i.id = v_line.item_id;
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.admin_edit_sale_group(uuid, timestamptz, bigint, jsonb) from public;
grant execute on function public.admin_edit_sale_group(uuid, timestamptz, bigint, jsonb) to authenticated;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (64, 'pos_sale_guard_and_edit_sale')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

notify pgrst, 'reload schema';

-- ── Verify ─────────────────────────────────────────────────────────
-- select proname from pg_proc
--  where proname in ('pos_record_sale', 'admin_edit_sale_group', '_item_status')
--  order by 1;
-- Expect 3 rows.
