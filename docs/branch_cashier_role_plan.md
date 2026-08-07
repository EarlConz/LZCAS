# Branch Cashier role — implementation plan

Status: **DRAFT for team review** · Branch: `branch-cashier-role`

## Goal
Add a new **staff** login role that can use **only** the POS Terminal and view
**Stocks on Hand** — nothing else (no member/user/product management, no
reports, no MLM). Working name: **Branch Cashier** (`branch_cashier`).

> ⚠️ **Do NOT name it `reseller`.** `profiles.role = 'reseller'` is already the
> MLM package-holder login role (`UserRole.reseller`). The new role is
> unrelated to Verified Reseller / members.

## Principle: everything is additive
No existing role's behavior, routing, or data access changes. Existing users are
unaffected whether or not they update the app. See "Rollout" below.

---

## Changes by layer

### 1. Database — RLS (the security boundary)
**Decision: treat branch cashier as STAFF at the DB level** (the POS-only limit
is enforced in the app UI, not RLS). This is the simple path.
- Single change: add `'branch_cashier'` to `is_staff()` →
  `migration_v28_branch_cashier_role.sql`. This grants full staff DB write
  access (enough for POS + stock reads).
- **Accepted tradeoff:** because `is_staff()` also gates `members` writes and
  the RPC auth (`get_member_earnings`, `process_package_upgrade`), a branch
  cashier *could* do more than POS via direct API calls. The app never exposes
  it. Acceptable "for now."
- `profiles` stays RLS-off (login reads it pre-auth — unchanged).
- Additive & safe: existing roles behave identically; no effect until an admin
  creates a `branch_cashier` account. Can ship to prod ahead of the app.
- Rollback: `rollbacks/rollback_is_staff_v27.sql` (drops branch_cashier from
  is_staff).
- **Future tightening (not now):** revert `is_staff()` to the three back-office
  roles and add a separate `is_pos_operator()` applied only to the POS tables'
  write policies (sales/stock_movements/member_transactions INSERT + items
  UPDATE). App code wouldn't change.

### 2. Edge functions
- `create-user` / `update-user` (Deno) validate role against an allowlist — add
  `branch_cashier` so admins can create/assign it.

### 3. App — Dart (this forces an APK/EXE release)
- `lib/auth/auth_state.dart` — add `UserRole.branchCashier('Branch Cashier')`
  and a `fromString` case. ⚠️ `fromString` **throws** on unknown roles (see
  rollout caveat).
- `lib/router/route_guard.dart` — new prefix (e.g. `/branch`), add to
  `_rolePrefixes`, `defaultForRole`, and the mobile gate.
- `lib/auth/role_visibility.dart` — include `branchCashier` in `canProcessSales`;
  add a stock-view getter. Do **not** grant it member/user/inventory management.
- **New restricted shell** with exactly two tabs — reuse existing widgets:
  - **POS Terminal** — the cashier POS flow (`lib/buttons/sellbutton.dart`,
    `lib/dialogs/sale_cart_editor.dart`, cashier dashboard POS section).
  - **Stocks on Hand** — the inventory stock table (`lib/widgets/inventorytable.dart`),
    **read-only** (no add/edit/delete controls).
- Admin "create user" UI — add the role to the dropdown.

### 4. Decisions still open (team, please weigh in)
- **Mobile gate:** cashier/inventory are desktop-only today. Is a branch cashier
  a desktop POS station (→ desktop-only, mirror cashier) or a tablet (→ allow
  mobile)? Default assumption: **desktop-only**.
- **Route prefix name:** `/branch` vs `/pos` vs `/branch-cashier`.
- **Stocks on Hand scope:** just current quantities, or also low-stock flags?
  (Read-only either way.)

---

## Rollout (protect the live system)
Everything is additive; sequence so existing users are never affected.

1. **Phase 0 — isolate:** feature branch (done) + a **second free Supabase
   project as staging** (schema + data copy). All RLS/role testing happens on
   staging via a debug build pointed at it. Never experiment on prod.
2. **Phase 1 — DB to prod (invisible, reversible):** apply the migration +
   edge-function allowlist. `is_pos_operator()` is a superset, so existing roles
   behave identically and no account uses the new path yet.
3. **Phase 2 — app release (additive):** build + ship the new APK/EXE. Existing
   roles route exactly as before; old builds keep working. Get the new build
   onto the branch station(s).
4. **Phase 3 — create accounts LAST:** only after the new build is on the
   station, create the `branch_cashier` login(s).

**Backward-compat caveat:** because `UserRole.fromString` throws on unknown
roles, a `branch_cashier` account opening an **old** build fails to log in. So
Phase 3 must come after Phase 2 on that device.

## Test checklist (on staging, before promoting)
- [ ] All existing roles (admin, cashier, inventory, member, reseller) land on
      the right dashboard and perform their normal actions — **unchanged**.
- [ ] `branch_cashier` can process a sale (stock decrements) and view stock.
- [ ] `branch_cashier` **cannot** write members, users, products (INSERT/DELETE
      items), or pending_requests — verified via direct API call, not just UI.
- [ ] `branch_cashier` **cannot** read others' earnings or run upgrades.
- [ ] Login + session-restore flow for existing roles is identical.

## Not in scope
- Any change to MLM roles (member/reseller), bonuses, or existing dashboards.
- Renaming existing roles or route prefixes.
