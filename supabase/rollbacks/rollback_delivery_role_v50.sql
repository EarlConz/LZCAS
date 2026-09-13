-- ═══════════════════════════════════════════════════════════════════
-- Rollback for migration_v50_delivery_role.sql
--
-- ⚠️ Lossy. Dropping the columns discards every rider assignment, ETA,
-- pickup and delivery timestamp, receiver name, and cancel reason on
-- every order that has them. The rows themselves survive; what is lost
-- is the record of who delivered what, when.
--
-- It also REFUSES to run while any order sits in a rider state
-- (Assigned / Picked Up / Delivered): narrowing the status CHECK would
-- fail on those rows, and silently rewriting them to Agreed would
-- claim goods are at the counter when they are on a motorbike. Resolve
-- those orders first — complete or cancel them in the app.
--
-- Delivery accounts are NOT deleted. profiles.role = 'delivery' stays;
-- those users just cannot reach anything, because the app has no
-- dashboard for a role its build knows and the DB has no RPC for.
-- Delete them from Admin → Users if you want them gone.
-- ═══════════════════════════════════════════════════════════════════

do $$
declare
  n integer;
begin
  select count(*) into n from public.orders
   where status in ('Assigned', 'Picked Up', 'Delivered');
  if n > 0 then
    raise exception
      'v50 rollback aborted: % order(s) are Assigned, Picked Up or Delivered. Complete or cancel them first.', n;
  end if;
end $$;

drop function if exists public.cashier_assign_rider(uuid, uuid);
drop function if exists public.delivery_pickup(uuid, timestamptz);
drop function if exists public.delivery_update_eta(uuid, timestamptz);
drop function if exists public.delivery_mark_delivered(uuid);
drop function if exists public.delivery_update_position(double precision, double precision);
drop function if exists public.member_confirm_received(uuid);
drop function if exists public._assert_my_delivery(uuid);
drop function if exists public.cancel_delivery_order(uuid, text);

-- complete_delivery_order and the 1-arg cancel_delivery_order revert
-- to their v49 bodies by re-running migration_v49_orders_authorization.sql
-- (create-or-replace). order_rider_is_me likewise goes back to `false`.

alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check
  check (status in (
    'Order Placed', 'Cashier Pricing & Negotiating', 'Member Negotiating',
    'Agreed', 'Completed', 'Cancelled'
  ));

drop index if exists public.idx_orders_delivery_id;

alter table public.orders drop constraint if exists orders_confirmation_method_check;
alter table public.orders drop constraint if exists orders_payment_method_check;
alter table public.orders drop constraint if exists orders_payment_status_check;

alter table public.orders
  drop column if exists delivery_id,
  drop column if exists assigned_at,
  drop column if exists picked_up_at,
  drop column if exists eta_at,
  drop column if exists delivered_at,
  drop column if exists receiver_name,
  drop column if exists receiver_contact,
  drop column if exists confirmed_by,
  drop column if exists confirmed_at,
  drop column if exists confirmation_method,
  drop column if exists cancel_reason,
  drop column if exists payment_method,
  drop column if exists payment_status;

delete from public.schema_migrations where version = 50;
