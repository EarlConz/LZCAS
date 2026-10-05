-- ═══════════════════════════════════════════════════════════════════
-- Which functions and triggers from our migrations are MISSING here?
--
-- READ-ONLY. Generated 2026-10-05 from supabase/migrations (every
-- "create or replace function public.X" and "create trigger"), after
-- staging turned out to lack the commission triggers that v45 had marked
-- as applied by assumption. Run on staging (and production) and send the
-- rows: each is something a migration created that this database lacks.
-- A function some later migration deliberately dropped may show up here;
-- check before acting on one.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Functions ───────────────────────────────────────────────────
select f.name as missing_function, f.created_in as from_migration
  from (values
  ('process_package_upgrade',71),
  ('get_member_earnings',56),
  ('get_current_member_id',9),
  ('set_member_account_role',12),
  ('sync_group_sales_for_sale',71),
  ('remove_group_sales_for_sale',71),
  ('record_referral_bonus_on_member',24),
  ('first_availed_package',71),
  ('referral_bonus_min_tier',71),
  ('first_availment_ts',71),
  ('package_held_at',71),
  ('crystallize_referral_on_availment',71),
  ('is_staff',28),
  ('can_manage_branch_stock',30),
  ('transfer_stock_to_branch',32),
  ('return_branch_stock',32),
  ('adjust_branch_stock',30),
  ('record_branch_sale',30),
  ('get_member_earnings_sources',35),
  ('admin_adjust_member_funds',35),
  ('member_branch_stock',38),
  ('server_now',42),
  ('touch_orders_updated_at',48),
  ('create_delivery_order',57),
  ('cashier_send_quote',61),
  ('member_respond_delivery_order',49),
  ('cashier_resolve_delivery_order',55),
  ('complete_delivery_order',61),
  ('cancel_delivery_order',61),
  ('is_delivery',49),
  ('my_member_id',49),
  ('order_rider_is_me',50),
  ('cashier_assign_rider',61),
  ('_assert_my_delivery',50),
  ('delivery_pickup',50),
  ('delivery_update_eta',50),
  ('delivery_mark_delivered',54),
  ('delivery_update_position',50),
  ('member_confirm_received',61),
  ('can_post_announcements',51),
  ('owns_announcement_media',51),
  ('order_record_sales',61),
  ('pay_order_with_funds',56),
  ('member_order_cod_code',62),
  ('confirm_cod_delivery',62),
  ('cashier_remit_cod',55),
  ('record_fee_offer',54),
  ('can_handle_orders',55),
  ('_lock_member_funds',56),
  ('_member_bucket_earned',56),
  ('guard_withdrawal_request',56),
  ('register_push_token',58),
  ('unregister_push_token',58),
  ('queue_order_push',61),
  ('reduce_item_stock',60),
  ('_order_take_stock',61),
  ('_order_return_stock',61),
  ('_order_refund_funds',61),
  ('cashier_cancel_shipped_order',61),
  ('_assert_outside_payment_order',61),
  ('member_choose_outside_payment',61),
  ('cashier_send_payment_details',61),
  ('member_mark_payment_sent',61),
  ('cashier_confirm_outside_payment',61),
  ('cashier_reject_outside_payment',61),
  ('cashier_mark_shipped',61),
  ('delivery_busy_rider_ids',62),
  ('_item_status',66),
  ('pos_record_sale',64),
  ('admin_edit_sale_group',64),
  ('guard_member_referrer',67),
  ('_tracking_key',69),
  ('guard_order_tracking_number',69)
  ) as f(name, created_in)
 where not exists (select 1 from pg_proc p
                    where p.pronamespace = 'public'::regnamespace and p.proname = f.name)
 order by f.created_in, f.name;

-- ── 2. Triggers ────────────────────────────────────────────────────
select t.name as missing_trigger, t.on_table, t.created_in as from_migration
  from (values
  ('trg_sync_group_sales_ins','sales',71),
  ('trg_sync_group_sales_upd','sales',71),
  ('trg_remove_group_sales_del','sales',71),
  ('trg_crystallize_referral_on_availment','sales',71),
  ('orders_touch_updated_at','orders',48),
  ('orders_record_fee_offer','orders',54),
  ('withdrawal_requests_guard','withdrawal_requests',56),
  ('orders_push_insert','orders',58),
  ('orders_push_update','orders',61),
  ('members_guard_referrer','members',67),
  ('orders_guard_tracking_number','orders',69)
  ) as t(name, on_table, created_in)
 where not exists (select 1 from pg_trigger g
                    where g.tgname = t.name and not g.tgisinternal)
 order by t.created_in, t.name;
