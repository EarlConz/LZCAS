# Production rollout: the delivery release

A step-by-step runbook for taking `delivery-account` to production: the
delivery system (Marketplace, Delivery Orders, riders, couriers, pushes) plus
everything built alongside it (product pictures, Edit Sale, the POS stock
guard, members on a phone, referral-loop guard).

Work top to bottom. Tick each box. **Stop at any ⛔ and sort it out before
going on.** Status of each migration and function lives in
[`supabase/DELIVERY_ROLLOUT.md`](../supabase/DELIVERY_ROLLOUT.md); update it as
you go.

| | |
|---|---|
| Production project | `cyfyydzxdsdzycbpvqox` |
| Staging project | `sisyujbpcueifeonnzfw` |
| Production app today | **v1.5.1** (`1.5.1+5`, delivery off) |
| Production database (as far as the notes know) | v46, plus v47 and v51; v48 unknown |
| This release | migrations **v48 → v69**, Edge Functions `order-push` and `order-route`, app **v1.6.0** |

> ⛔ **Never on production:** `supabase/schema/schema.sql` and
> `supabase/maintenance/wipe_delivery_orders_staging.sql`. Production only
> ever gets the numbered migrations.
>
> **Secrets** (the ORS key, the Firebase service account, the push secret, the
> service-role key, the database password) go straight from where they live
> into the Supabase dashboard or CLI. Never into chat, a file in the repo, or
> a commit.

---

## Why this order

1. **Database first, days ahead if you like.** Every migration here is
   invisible to the v1.5.1 app: they add tables, columns, functions,
   triggers and policies; none removes what 1.5.1 uses. (Checked 2026-10-04:
   v60 and v64 add functions but revoke nothing from the tables 1.5.1 writes
   to; v63 rebuilds `items_with_status` with the same columns plus one.)
2. **Edge Functions second.** They only act on delivery orders, which nobody
   can place until the app ships.
3. **App last.** It is the point of no return: once members place real
   orders, rolling the database back loses them.
4. **Rider accounts after the app.** v1.5.1 doesn't know the `delivery` role.

---

## Phase 0 · Before release day

- [ ] **Staging sign-off.** Part 4 of the Delivery Test Plan passed, or every
      failure is fixed and retested. Note the commit that was tested.
- [ ] **Open decisions settled or consciously deferred:** Batch 8 (cashier
      top menu), R6 (Counter purchases filter), rider pay. Anything deferred
      goes in the release notes as "coming later", not half-built.
- [ ] **Rotate the Firebase Android API key.** The current one is in
      `android/app/google-services.json` (project `gutvita-8df41`) and was
      pushed to GitHub (commit `3b3f9b3`).
  1. Google Cloud console → APIs & Services → Credentials: create a new key,
     restricted to Android apps (`com.lzcas.app` and `com.lzcas.app.staging`)
     and to the Firebase Installations and FCM Registration APIs.
  2. Firebase console → Project settings: download the new
     `google-services.json` into `android/app/`.
  3. Keep the **old key** until phase 4 is done: phones on v1.5.1 still use
     it. Delete it in phase 5.
- [ ] **Push and merge.** Push `delivery-account`, open a PR into `main`,
      merge after review. Releases are built from `main`.
- [ ] **Backup.** Confirm production has a recent backup (Dashboard →
      Database → Backups), or take a `pg_dump` yourself. Write down its time.

---

## Phase 1 · Read production (nothing changes yet)

Run each in the production SQL editor and keep the output.

- [ ] **What is applied.** Run all of
      `supabase/diagnostics/check_applied_migrations.sql`. Then the ledger:
  ```sql
  select version, name, applied_at::date, verified
    from public.schema_migrations where version >= 45 order by version;
  ```
  Expect v45, v46, v47, v51 applied; v48 either way; v49–v69 missing.
  ⛔ Anything else applied (a v52 from 2026-09-23, any v49+): stop and
  compare with staging before going on.
- [ ] **Withdrawals (for v56).** Run **section 2** of
      `supabase/diagnostics/audit_withdrawal_overdrafts.sql`.
      ⛔ Any rows: settle those pending withdrawals (approve or reject) first.
- [ ] **Referral loops (for v67).** Run section 5 of
      `supabase/diagnostics/audit_referral_loops.sql`. Expect none (it was
      none on 2026-10-03). Rows here don't block v67, which leaves existing
      loops alone, but fix them in Edit Member after the app ships.
- [ ] **Realtime (for v68).** Note which tables are published now:
  ```sql
  select tablename from pg_publication_tables
   where pubname = 'supabase_realtime' and schemaname = 'public' order by 1;
  ```

---

## Phase 2 · Migrations

Apply each file from `supabase/migrations/` in the SQL editor, **one at a
time, in this order**, from the merged `main`. After each: it finished
without an error, and its row is in `schema_migrations` (v48 writes none).
Each file ends with a `Verify` block; run it where noted.

| ✓ | # | File | Check after |
|---|---|---|---|
| [ ] | v48 | `migration_v48_delivery_orders.sql` | Safe to re-run if already there. `select to_regclass('public.orders');` not null. |
| [ ] | v49 | `migration_v49_orders_authorization.sql` | |
| [ ] | v50 | `migration_v50_delivery_role.sql` | |
| [ ] | v52 | `migration_v52_order_payment_and_sales.sql` | (v51 is already on production.) |
| [ ] | v53 | `migration_v53_order_route.sql` | Deploy `order-route` in phase 3. |
| [ ] | v54 | `migration_v54_delivery_payment_hardening.sql` | |
| [ ] | v55 | `migration_v55_delivery_cashiers_only.sql` | |
| [ ] | v56 | `migration_v56_withdrawal_reservations.sql` | Only after the phase 1 withdrawal audit came back clean. Run its Verify block. |
| [ ] | v57 | `migration_v57_order_refunds_and_receiver.sql` | |
| [ ] | v58 | `migration_v58_push_notifications.sql` | Vault entries in phase 3; until then the trigger quietly does nothing. |
| [ ] | v59 | `migration_v59_dispatch_needs_payment.sql` | |
| [ ] | v60 | `migration_v60_reduce_item_stock.sql` | |
| [ ] | v61 | `migration_v61_courier_delivery.sql` | |
| [ ] | v62 | `migration_v62_short_cod_code_and_busy_riders.sql` | |
| [ ] | v63 | `migration_v63_product_images.sql` | Bucket `product-images` exists (Dashboard → Storage). |
| [ ] | v64 | `migration_v64_pos_sale_guard_and_edit_sale.sql` | |
| [ ] | v65 | `migration_v65_orders_seen_by_all_staff.sql` | |
| [ ] | v66 | `migration_v66_item_status_bigint.sql` | |
| [ ] | v67 | `migration_v67_no_referral_loops.sql` | |
| [ ] | v68 | `migration_v68_realtime_tables.sql` | `select note from schema_migrations where version = 68;` says which tables it added. |
| [ ] | v69 | `migration_v69_unique_tracking_numbers.sql` | |

- [ ] **Check the whole set.** Run `check_applied_migrations.sql` again:
      every row v35–v69 reads **APPLIED**.
- [ ] **v1.5.1 still works.** On a v1.5.1 install against production: log in
      as a cashier, make one POS sale, open Members and Inventory; log in as
      a member and open the earnings screen. Nothing errors.

**If a migration fails:** don't continue. The SQL editor normally runs a
whole file as one transaction, so a failed file usually leaves nothing
behind; confirm with `check_applied_migrations.sql` (its row should read
MISSING). Read the error, fix the cause (or ask), and re-run that file. To undo an applied one, run its file in
`supabase/rollbacks/`, in reverse order from the newest. Before phase 4 this
loses no data: no one can place an order yet.

---

## Phase 3 · Edge Functions, secrets and Vault

Deploy from the merged `main`, the same commit the migrations came from.
The exact commands, the Set-Clipboard trick for the Vault secret, and the
check that the two push secrets match are in `supabase/README.md` (v53 and
v58 sections). Point the CLI at the **production** ref.

- [ ] Secret `ORS_API_KEY` (openrouteservice) set on production.
- [ ] `order-route` deployed.
- [ ] Secrets `FIREBASE_SERVICE_ACCOUNT`, `PUSH_WEBHOOK_SECRET` and
      `SERVICE_ROLE_KEY` set on production.
- [ ] `order-push` deployed **with `--no-verify-jwt`**.
- [ ] Vault `order_push_url` = production's `order-push` URL
      (`https://cyfyydzxdsdzycbpvqox.supabase.co/functions/v1/order-push`).
- [ ] Vault `order_push_secret` = the same value as `PUSH_WEBHOOK_SECRET`.
- [ ] Both checks from the README's v58 section pass (the secrets match; the
      function answers).

`create-user`, `update-user`, `delete-user` and `create-member-user` did
not change in this release: no redeploy.

---

## Phase 4 · The app (point of no return)

### 4.1 Release commit, on `main`

- [ ] **Turn delivery on for production.** In
      `lib/config/feature_flags.dart`, set
      `const bool enableDeliverySystem = true;` and update its comment.
      Only now: production has every migration.
- [ ] **Version.** `pubspec.yaml` `1.5.1+5` → `1.6.0+6`. The updater compares
      the release tag with this number, so it must be higher than `1.5.1`.
      Plain numbers only (no `-rc1`).
- [ ] The new `google-services.json` from phase 0 is in `android/app/`.
- [ ] `CHANGELOG.md` and `docs/release_notes_technical.md` updated.
- [ ] Commit, tag `v1.6.0` on that commit.

### 4.2 Build (PowerShell, one line each; see `docs/staging_builds.md`)

- [ ] Android:
  ```powershell
  flutter build apk --release --flavor prod --dart-define=SUPABASE_URL=https://cyfyydzxdsdzycbpvqox.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PROD_PUBLISHABLE_KEY
  ```
  Rename the APK so the name does **not** contain `staging`.
- [ ] Windows, built **immediately** before packaging (both flavors share
      the output folder):
  ```powershell
  flutter build windows --release --dart-define=SUPABASE_URL=https://cyfyydzxdsdzycbpvqox.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PROD_PUBLISHABLE_KEY
  iscc installer.iss
  ```
- [ ] **Smoke test before publishing.** Install both on a spare device:
      no STAGING ribbon; members have Marketplace and Active Orders;
      cashiers have Delivery Orders; a POS sale works.

### 4.3 Publish

- [ ] GitHub → new release, tag `v1.6.0`, **"Set as a pre-release" unticked**,
      attach the `.exe` and `.apk`.
- [ ] **Force the update?** Recommended: add
      `min-supported-version: 1.6.0` to the release notes. Without it, staff
      on v1.5.1 have no Delivery Orders tab, and their POS skips the oversell
      guard; members on v1.5.1 can't order. Decide before publishing.

---

## Phase 5 · After the app is out

- [ ] **Accounts.** Create the rider accounts (User Management → role
      Delivery). Riders, cashiers and admins: open the new app once, sign
      in, allow notifications. Only phones that have done this get pushes.
- [ ] **One real order of each kind**, with staff watching:
  - rider, paid from funds;
  - rider, cash on delivery (scan the code);
  - LBC or J&T, paid outside the app, marked Shipped with a tracking number.

  For each: pushes arrive; the stock drops once; the sale shows once in the
  POS list; the buyer's upline gets Group Sales.
- [ ] **Pictures.** An admin adds a picture to one product; members see it.
- [ ] **Delete the old Firebase key** in Google Cloud, once phones are on
      v1.6.0.
- [ ] **Update the notes.** Production column in
      `supabase/DELIVERY_ROLLOUT.md`, and a changelog row.

### First week

- [ ] Every day or two: `audit_withdrawal_overdrafts.sql` section 2, and
      sections 5–6 of `audit_referral_loops.sql`. Both should stay empty.
- [ ] Edge Function logs (Dashboard → Edge Functions → `order-push`,
      `order-route`): no repeating errors.
- [ ] Ask cashiers whether alerts and live updates arrive on time.

---

## If something goes wrong after phase 4

- **App bug, data fine:** fix it, then release `v1.6.1`. The updater only
  moves forward, so a fix is always a newer version. To switch delivery off
  meanwhile, release `v1.6.1` with `enableDeliverySystem` back on staging
  only; the database can stay as it is.
- **Database bug:** fix it with a new migration (v70…). Don't run a rollback
  file on production once real orders exist: the delivery rollbacks drop
  order data. Rollbacks are for before phase 4.
- **Pushes not arriving:** the order still works without them. Check the
  Vault entries, the matching secrets and the `order-push` logs (phase 3).
