# Delivery release — staging vs production

The one place that says what the delivery release has put on **staging** and
what **production** still needs. Update the tables below whenever something is
applied to either project.

- Staging: `sisyujbpcueifeonnzfw`
- Production: `cyfyydzxdsdzycbpvqox`

> **Last updated 2026-10-04.** Staging is at **v69**. Production, as far as
> these notes know, is at v46 plus v47 and v51. **Confirm production before
> starting** (query below): this file only knows what someone wrote down.
>
> **Production app:** release **v1.5.1** (tag, 2026-09-23). Delivery is off in
> it (`enableDeliverySystem = false`), and it carries only three of these
> migration files: v47, v48 and v51. So production cannot have v49 or later
> from this release. Whether v48 was ever run there is unknown: the ledger
> query settles it. A v52 called `saved_items_policy_repair` existed for
> twelve minutes on 2026-09-23 and was dropped before the tag; it is the
> label staging still shows for v52.

```sql
-- Run on PRODUCTION first: what its ledger says is applied from v45 on.
select version, name, applied_at, verified
from public.schema_migrations
where version >= 45
order by version;
```

## ⛔ Never on production

- `supabase/maintenance/wipe_delivery_orders_staging.sql`: deletes every order
  and its sales, commissions and payments. (It refuses where v61 is not
  recorded, so production stops it today. It would not after this rollout.)
- `supabase/schema/schema.sql`: destructive. Staging only.

> **Doing the rollout?** Follow the step-by-step runbook,
> [`docs/prod_rollout_delivery.md`](../docs/prod_rollout_delivery.md). This
> file is the status board it ticks off.

## 1. Migrations, in this order

| # | File | Staging | Production | Before applying on production |
|---|------|:-:|:-:|---|
| v47 | `migration_v47_member_location.sql` | ✅ | ✅ | — |
| v48 | `migration_v48_delivery_orders.sql` | ✅ | ❓ | Shipped as a file in v1.5.1; check the ledger. Safe to re-run if present. |
| v49 | `migration_v49_orders_authorization.sql` | ✅ | ❌ | — |
| v50 | `migration_v50_delivery_role.sql` | ✅ | ❌ | — |
| v51 | `migration_v51_cashier_announcements.sql` | ✅ | ✅ | — |
| v52 | `migration_v52_order_payment_and_sales.sql` | ✅ ¹ | ❌ | — |
| v53 | `migration_v53_order_route.sql` | ✅ | ❌ | Deploy `order-route` (section 2) in the same sitting. |
| v54 | `migration_v54_delivery_payment_hardening.sql` | ✅ | ❌ | — |
| v55 | `migration_v55_delivery_cashiers_only.sql` | ✅ | ❌ | — |
| v56 | `migration_v56_withdrawal_reservations.sql` | ✅ | ❌ | **Run section 2 of `supabase/diagnostics/audit_withdrawal_overdrafts.sql` on production right before**: any stacked pending withdrawals must be settled first. |
| v57 | `migration_v57_order_refunds_and_receiver.sql` | ✅ | ❌ | — |
| v58 | `migration_v58_push_notifications.sql` | ✅ | ❌ | Vault secrets and `order-push` (section 2). Without the Vault entries the trigger does nothing; it never fails an order. |
| v59 | `migration_v59_dispatch_needs_payment.sql` | ✅ | ❌ | — |
| v60 | `migration_v60_reduce_item_stock.sql` | ✅ | ❌ | Independent of delivery, but the app's Edit Product calls it: apply before the new app ships. |
| v61 | `migration_v61_courier_delivery.sql` | ✅ 2026-10-02 | ❌ | — |
| v62 | `migration_v62_short_cod_code_and_busy_riders.sql` | ✅ 2026-10-02 | ❌ | — |
| v63 | `migration_v63_product_images.sql` | ✅ 2026-10-03 | ❌ | Product pictures; independent of delivery. Creates the public `product-images` bucket. Apply before an app build with picture upload reaches admins (older builds ignore it). |
| v64 | `migration_v64_pos_sale_guard_and_edit_sale.sql` | ✅ 2026-10-03 | ❌ | POS checkout and Edit Sale call its functions: apply before the app build that has them, or checkout fails. Independent of delivery. |
| v65 | `migration_v65_orders_seen_by_all_staff.sql` | ✅ 2026-10-03 | ❌ | Every cashier sees every delivery order (client decision 2026-10-03); only its cashier or an admin can change it. Apply with or before the app build that shows "Handled by"; older builds just show more orders, with buttons the database refuses. |
| v66 | `migration_v66_item_status_bigint.sql` | ✅ 2026-10-04 | ❌ | Fixes Edit Sale ("_item_status(bigint, text) does not exist", tests X1–X3). Needs v64. No app change. |
| v67 | `migration_v67_no_referral_loops.sql` | ✅ 2026-10-04 | ❌ | Refuses a referrer from the member's own downline (referral loops, X6). Existing loops untouched; the app also hides those choices. |
| v68 | `migration_v68_realtime_tables.sql` | ✅ 2026-10-04 | ❌ | Puts items, members, sales, the request queues and orders in the realtime publication, so changes reach other devices (Part 3 live-update failures). Adds only what is missing. |
| v69 | `migration_v69_unique_tracking_numbers.sql` | ✅ 2026-10-04 | ❌ | Refuses a tracking number already on another order (ignores case, spaces, dashes). Needs v61. The app's Generate button relies on it to avoid repeats. |

¹ Staging's ledger names v52 `saved_items_policy_repair`; its changes are in
place. On production it will record itself correctly.

Every migration has a rollback in `supabase/rollbacks/`, named after it.

## 2. Edge Functions, secrets and Vault

| What | Staging | Production |
|---|:-:|:-:|
| `order-route` deployed | ✅ | ❌ |
| secret `ORS_API_KEY` (openrouteservice) | ✅ | ❌ |
| `order-push` deployed **with `--no-verify-jwt`** | ⚠️ v61 version; **redeploy** for the 2026-10-03 admin rules | ❌ |
| secrets `PUSH_WEBHOOK_SECRET`, `FIREBASE_SERVICE_ACCOUNT`, `SERVICE_ROLE_KEY` | ✅ | ❌ |
| Vault `order_push_url` = the production `order-push` URL | ✅ | ❌ |
| Vault `order_push_secret` = the same value as `PUSH_WEBHOOK_SECRET` | ✅ | ❌ |

Set secrets from a variable, never by typing them into chat or a file in the
repo. The README's v58 section has the commands, the Set-Clipboard trick for
the Vault entry, and the check that the two secret values match.

Deploy functions from the same commit as the last migration: `order-push`
must know v59's payment events and v61's `event` field.

## 3. App release

1. **Rotate the Firebase key first.** The current one was pushed to GitHub.
   Create a new key, download a new `android/app/google-services.json`,
   build with it, then delete the old key in Google Cloud.
2. **Turn delivery on for production builds.** `enableDeliverySystem` in
   `lib/config/feature_flags.dart` is on for staging builds only. Set it to
   `true` (or include production in the condition) in the release commit,
   and not before production has every migration above.
3. Bump the version above the last tag (see `docs/prod_rollout_checklist.md`
   on how the updater compares versions), merge to `main`, tag, release.
4. **Ship the app before creating any rider account.** An older app does not
   know the `delivery` role.

## 4. After the app is out

1. Create rider accounts (User Management → role Delivery).
2. Every rider, cashier and admin phone: open the new app once, sign in, allow
   notifications. Only phones that have done this receive pushes.
3. Smoke test with one real order of each kind: rider + funds, rider + cash
   on delivery, LBC/J&T + outside payment.

## Changelog of this file

| Date | Change |
|---|---|
| 2026-10-02 | Created. Staging at v62; production at v46 + v47 + v51 (unconfirmed). |
| 2026-10-02 | Production app is v1.5.1: delivery off; v48 status unknown. |
| 2026-10-02 | Added v63 (product pictures), written but not applied anywhere yet. |
| 2026-10-03 | Added v64 (POS sale guard, admin Edit Sale), not applied anywhere yet. |
| 2026-10-03 | order-push changed (admins: new + completed orders, the rest only when no cashier holds it); staging needs a redeploy. |
| 2026-10-03 | Added v65 (every cashier sees every order), not applied anywhere yet. |
| 2026-10-03 | v65 applied on staging; ledger confirms v45–v65. |
| 2026-10-03 | Added v66 (Edit Sale fix), not applied anywhere yet. |
| 2026-10-03 | Added v67 (no referral loops), not applied anywhere yet. |
| 2026-10-04 | Added v68 (realtime tables), not applied anywhere yet. |
| 2026-10-04 | Added v69 (unique tracking numbers), not applied anywhere yet. |
| 2026-10-04 | v66–v69 applied on staging. |
| 2026-10-04 | Production runbook written: `docs/prod_rollout_delivery.md`. |
