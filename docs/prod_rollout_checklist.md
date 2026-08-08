# Prod Rollout Checklist — Branch Cashier + Branch Stock

Everything below was built and verified on the **staging** Supabase project
(`sisyujbpcueifeonnzfw`) and on the `branch-cashier-role` branch. This is the
ordered list of what must be applied to **prod** later. **Nothing here is on
prod yet.**

> Prod is currently at **earnings migration v27**. This feature set is **v28 →
> v33** plus an edge-function redeploy, the app release, and account creation.

## Golden rule (order matters)

Apply in this order so nothing breaks:

1. **DB migrations** (invisible/reversible) — safe to run before the app ships.
2. **Edge function redeploy.**
3. **App release** — MUST ship before any `branch_cashier` account exists.
   `UserRole.fromString` throws on an unknown role, so an existing app would
   crash on a `branch_cashier` login.
4. **Create accounts** last.

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

Rollbacks (only if needed): `rollback_is_staff_v27.sql` (reverts v28),
`rollback_mobile_flag_v29.sql`, `rollback_branch_stock_v30.sql`,
`rollback_branch_transfer_reports_v31.sql`, `rollback_branch_transfer_note_v32.sql`.

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
- **Dummy reseller `reseller1`** and its ledger — staging test data only.
- **Real categories/packages/items import** into staging — that was to make
  staging mirror prod; prod already has them.
- **`schema/schema.sql` edits** — for fresh-DB reproducibility only. Prod is not
  rebuilt from `schema.sql`; prod gets the numbered migrations above.
