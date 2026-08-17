# Prod Rollout Checklist

Everything below was built and verified on the **staging** Supabase project
(`sisyujbpcueifeonnzfw`). This is the ordered list of what must be applied to
**prod** (`cyfyydzxdsdzycbpvqox`) once the client signs off.

> **Current prod state (verified 2026-08-15):**
> - Earnings migrations: **v27**, plus **v34 already applied** ✅
> - Still needed: **v28 → v33**, an edge-function redeploy, the app release,
>   and account creation.
> - Last released app build: tag **v1.2** (2026-08-07).

## Golden rule (order matters)

0. **Merge the code** — commit the pending work and merge to `main`.
1. **DB migrations** (invisible/reversible) — safe to run before the app ships.
2. **Edge function redeploy.**
3. **App release** — MUST ship before any `branch_cashier` account exists.
   `UserRole.fromString` throws on an unknown role, so an existing app would
   crash on a `branch_cashier` login.
4. **Create accounts** last.

---

## 0. Code still to commit / merge

As of 2026-08-15 these are **uncommitted** on `branch-cashier-role`:

| Work | Files |
|---|---|
| Buyer's package in POS + receipt | `sellbutton.dart`, `receipt_dialog.dart`, `transactionstable.dart`, `supabase_repository.dart` |
| Itemised earnings sources + Sources/History toggle | `models.dart`, `db.dart`, `supabase_repository.dart`, `member_dashboard.dart` |
| Migration v34 + rollback | `supabase/migrations/`, `supabase/rollbacks/`, `supabase/README.md` |
| Changelogs | `CHANGELOG.md`, `docs/release_notes_technical.md` |

Everything else from this cycle is already merged into `main`.

**Version bump — do not skip.** `pubspec.yaml` is `1.0.0+1` but the last tag is
`v1.2`. The updater compares the release **tag** against the app's **pubspec**
version, so ship with pubspec set above 1.2 (e.g. `1.3.0+3`) and tag `v1.3.0`.
Use plain numeric tags — `_parseVersion` reads only leading digits, so
`1.3.0-rc1` and `1.3.0-rc2` compare equal.

---

## 1. DB migrations — run in this exact order (Supabase SQL editor)

| # | File | What it does |
|---|------|--------------|
| v28 | `migration_v28_branch_cashier_role.sql` | `is_staff()` accepts `branch_cashier` (so branch cashier passes RLS + RPC auth on operational tables). |
| v29 | `migration_v29_branch_cashier_mobile_flag.sql` | Adds `profiles.mobile_enabled` (admin-granted mobile login; desktop-only by default). |
| v30 | `migration_v30_branch_stock.sql` | Branch stock system: `branch_stock` + `stock_transfers` tables, `branch_stock_view`, RPCs `transfer_stock_to_branch` / `return_branch_stock` / `adjust_branch_stock` / `record_branch_sale` / `can_manage_branch_stock`. Two-tier inventory; give-out deducts central. |
| v31 | `migration_v31_branch_transfer_reports.sql` | Give-out/return also write `stock_movements` (`transfer_out` / `transfer_in`) so transfers show in Reports as **Branch Out / Branch In**. (adjust is intentionally not logged — it doesn't change central stock.) |
| v32 | `migration_v32_branch_transfer_note.sql` | Includes the give-stock **note** in the Reports reason (`branch - note`). |
| v33 | `migration_v33_branch_stock_grants.sql` | **RLS + policies** for `branch_stock` / `stock_transfers`: RLS ON, SELECT-only grants, policies (admin/main-cashier see all; a branch cashier sees only their own rows). Writes stay locked to the SECURITY DEFINER RPCs. **This is the read fix — without it the app sees nothing.** |

| v34 | `migration_v34_earnings_sources_rpc.sql` | **ALREADY APPLIED TO PROD ✅** — `get_member_earnings_sources`, the per-credit "where did this come from" list. Must be SECURITY DEFINER: prod RLS limits a member to their own rows in `members`/`sales`, so resolving downline names client-side silently returns nothing. Independent of v28–v33. |

Rollbacks (only if needed): `rollback_is_staff_v27.sql` (reverts v28),
`rollback_mobile_flag_v29.sql`, `rollback_branch_stock_v30.sql`,
`rollback_branch_transfer_reports_v31.sql`, `rollback_branch_transfer_note_v32.sql`,
`rollback_earnings_sources_v34.sql`.

Post-migration sanity (prod): as a logged-in admin the **Branch Stock** tab
loads; giving stock to a branch cashier appears under Allocations, Transfers,
and Reports (Branch Out).

## 2. Edge functions — redeploy to prod

- **`update-user`** — MODIFIED: now persists `mobile_enabled`. Redeploy so the
  admin "Allow mobile login" toggle actually saves.
  ```
  supabase functions deploy update-user   # against the PROD project ref
  ```
- `create-user` was **not** changed (it already forwards whatever role the app
  sends; the role-string fix was app-side). No redeploy needed unless prod is
  behind for other reasons.

## 3. App release

Ship the `branch-cashier-role` build (after merge to `main`). It contains:

- **Role plumbing:** `UserRole.branchCashier` (persists as `branch_cashier`);
  fixed `role.dbValue` serialization (was `role.name`, which broke the new
  snake_case role); route guard + role visibility + app router entries.
- **Branch Cashier dashboard** (`lib/pages/branch/branch_cashier_dashboard.dart`):
  POS Terminal (branch-aware) + Stocks-on-Hand (redesigned, reads their
  allocation).
- **Branch-aware POS** (`sellbutton.dart`, `transactionstable.dart`): sells from
  branch stock via `record_branch_sale`; branch cashier's sales list scoped to
  them (`fetchSalesPaginated(userId:)`).
- **Admin Branch Stock tab** (`lib/pages/admin/branch_stock_page.dart`): give /
  return / adjust, all-branches overview, transfers (paginated + filtered).
- **Mobile flag:** desktop-only gate for branch cashier unless admin enables it
  (`auth_state.dart`, `route_guard.dart`, `UserProfile.mobileEnabled`, edit-user
  dialog toggle).
- **Reports:** Branch Out / Branch In totals, labels, colors, filters
  (`inventory_reports_view.dart`).

Also in this release (built after the checklist was first written):

- **Auto-updater + forced updates** — GitHub Releases check, download, install.
  A `min-supported-version: X.Y.Z` line in the release notes makes an update
  mandatory. Fixed a crash when dismissing the update dialog.
- **Pagination fix** — Members / POS Transactions / Stocks were stuck on
  "Loading…" past the first page (`onPageChanged` gives a row index, not a page
  number). Plus next-page prefetch and shimmer skeleton rows.
- **Itemised earnings sources** — "Where your earnings came from" on the member
  dashboard, behind a Sources ⇄ History toggle. Needs **v34** (already on prod).
- **Buyer's package in POS + receipt** — needs the `members_package_id_fkey`
  foreign key, verified present on prod.
- **Chairman's Bonus wording** — now describes the per-direct-referral model
  (v24) instead of the removed weekly-Friday one. Display only; no amounts change.
- **Request history status counts** — now include withdrawals.
- **Staging build flavor** — `--dart-define=APP_FLAVOR=staging`. Production
  builds are unaffected, **but** Android now requires `--flavor prod`
  (`flutter build apk --release --flavor prod`). See `docs/staging_builds.md`.
  Production builds must pass the prod `--dart-define`s: the bundled
  `assets/supabase_config.json` fallback points at prod, and the startup guard
  refuses to launch on a flavor/project mismatch.

## 4. Create branch-cashier accounts (last)

Admin → Users → Create User → Role **Branch Cashier**. (Needs `update-user` and
the migrations already applied.) Then, per account, optionally toggle **Allow
mobile login** in Edit User if they need phone/tablet access.

## 5. Verify branch-cashier reads on prod

Confirm the branch POS can read `members` (buyer picker) and `sales` (history).
These rely on `is_staff()` including `branch_cashier` (v28). If either comes up
empty/errors, widen the RLS policy on that table to include staff.

---

## NOT for prod (staging-only)

- **`get_member_earnings` RPC** — this is already **live on prod (v24)**. It was
  only missing on *staging* and was added there so the reseller dashboard works.
  Do **not** treat it as a prod change.
- **Migration v34** — already applied to prod and verified. Do not re-run as
  part of this rollout (harmless if you do — it's `create or replace`).
- **Dummy reseller `reseller1`** and its ledger — staging test data only.
- **Real categories/packages/items import** into staging — that was to make
  staging mirror prod; prod already has them.
- **`schema/schema.sql` edits** — for fresh-DB reproducibility only. Prod is not
  rebuilt from `schema.sql`; prod gets the numbered migrations above.
