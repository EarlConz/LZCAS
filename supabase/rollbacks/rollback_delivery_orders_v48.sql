-- Rollback for migration v48 — Member Ordering & Delivery Negotiation.

drop function if exists public.cancel_delivery_order(uuid);
drop function if exists public.complete_delivery_order(uuid);
drop function if exists public.cashier_resolve_delivery_order(uuid, text, numeric);
drop function if exists public.member_respond_delivery_order(uuid, text, numeric);
drop function if exists public.cashier_send_quote(uuid, uuid, numeric, numeric, jsonb);
drop function if exists public.create_delivery_order(bigint, text, double precision, double precision, jsonb);

drop trigger if exists orders_touch_updated_at on public.orders;
drop function if exists public.touch_orders_updated_at();

drop table if exists public.order_items;
drop table if exists public.orders;
