# Technical release notes

Engineering companion to `CHANGELOG.md` (which is written for users and
admins). This file carries the parts a developer needs and a user shouldn't
have to read: commit history, database migrations, rollout order, and the
reasons behind each change.

Baseline: last released build is tag **v1.3.0** (2026-08-20).

---

## Unreleased — next production release

**Status:** in development.

### Added
- **Admin fund adjustments** (migration v35) — `admin_adjust_member_funds`,
  an admin-only SECURITY DEFINER RPC, plus an Adjust Funds dialog on the
  admin member-detail modal.

  The ledger is append-only, so an adjustment is a **new signed row**, never
  an `UPDATE`/`DELETE` of an existing credit. Its `item_name` keeps the
  bucket's prefix — `'Chairman Bonus Adjustment — <reason>'` still matches
  `ilike 'Chairman Bonus%'` — so `get_member_earnings` picks it up with **no
  change to the earnings RPC**. That prefix match is the whole mechanism.

  Design points worth keeping:
  - `is_admin()`, not `is_staff()`. Stricter than every other earnings RPC on
    purpose.
  - **Reason is mandatory** and lives in `item_name`, because that is the
    string the member's Sources card renders. Whitespace-collapsed and capped
    at 120 chars server-side so one long paste can't wreck the row; the full
    text is kept in `fund_adjustments.reason`.
  - **Bucket cannot go negative.** `get_member_earnings` clamps totals at 0,
    so a negative bucket would silently swallow later legitimate earnings
    instead of showing them. The RPC refuses rather than create that trap.
  - `fund_adjustments` is the audit trail (who/when/why/before/after),
    deliberately separate from `member_transactions` — that table is the
    money, this one is the paperwork. SELECT is admin-only; there is **no**
    INSERT policy, so the RPC is the only way in.
  - The RPC writes its own `earnings_history` snapshot with the new
    `note` column, rather than waiting for the member's dashboard to record
    one. Otherwise the entry would surface later with no cause attached.
- **`earnings_history.note`** — snapshots previously stored deltas with no
  cause, which is why the member's History guessed "Withdrawal" for any
  decrease.
- **`get_member_earnings_sources.is_adjustment`** — v34's RPC plus one
  boolean, joined from `fund_adjustments.transaction_id` rather than sniffed
  from the label. Needed because `'Upgrade Bonus — Ambassador'` encodes the
  target tier after the dash and the client parses it into "Upgraded to
  Ambassador"; an `'Upgrade Bonus Adjustment — <reason>'` row has the same
  shape and would otherwise read "Upgraded to \<reason\>".

  The return type changed, so v35 **drops and recreates** the function —
  `CREATE OR REPLACE` cannot alter OUT columns. Adding a column is
  backward-compatible: older clients read by key and ignore it.

### Fixed
- **Corrections labelled "Withdrawal"** — `_historyRow` assumed any negative
  delta was money paid out. It now prefers the snapshot's `note` when one
  exists and falls back to the neutral "Deduction".
- **Negative amounts rendered `₱-300`** in the Sources list — the sign now
  sits outside the currency symbol and the row is coloured `danger`.

### Known gap
- `member_transactions` has **no realtime subscription**, so a member already
  sitting on the Earnings tab sees an adjustment on their next visit rather
  than instantly. Subscribing would stream every sale and referral row to
  every device for a rare manual action; not worth the WAL load.

---

## v1.3.0 — 2026-08-20

### Added
- **Branch Cashier role + Branch Stock** (`9d87cda`) — two-tier inventory.
  `branch_stock` is keyed per branch-cashier account; a give-out deducts
  central `items.stock` and credits the branch, so total quantity is
  conserved. All writes go through SECURITY DEFINER RPCs
  (`transfer_stock_to_branch`, `return_branch_stock`, `adjust_branch_stock`,
  `record_branch_sale`), so RLS only needs SELECT policies. Adds
  `profiles.mobile_enabled` to gate mobile sign-in per branch-cashier
  account.
- **Auto-updater** (`318e5c6`) — polls GitHub Releases, downloads the
  platform asset via dio with progress, launches the installer.
- **Forced updates** (`6d19dff`) — `min-supported-version: X.Y.Z` parsed from
  the release body. When the running version is below the floor,
  `UpdateInfo.mandatory` is set and the dialog becomes non-dismissible
  (`PopScope(canPop: false)`, no "Later").
- **Lifetime Earning** (`72c8a4a`) — gross sum of all `member_transactions`,
  shown alongside the net figure from `get_member_earnings`.
- **Staging build flavor** (`ab87977`) — see `docs/staging_builds.md`.
  Android product flavors (`applicationIdSuffix = .staging`), Inno Setup
  `AppId` per flavor, GitHub pre-release update channel, flavor-matched
  release assets, and a startup guard pinning each flavor to one Supabase
  project ref.
- **Buyer's package in POS + receipt** — `fetchMembers()` now selects
  `*, packages(name)` so `Member.packageName` is populated (it was always
  empty; the query never joined). Requires the
  `members_package_id_fkey` FK, verified present on staging and prod.
- **Itemised earnings sources** — "Where your earnings came from" card,
  backed by the v34 RPC. Reads `member_transactions` (the frozen ledger
  `get_member_earnings` sums), NOT `earnings_history` snapshots, so the
  itemised list always reconciles to the displayed totals.

### Improved
- **Table paging** (`1f621ab`) — background prefetch of the next page, a
  coalescing loader keyed on a `_pendingNeeded` high-water mark so fast
  multi-page jumps can't drop a request, and shimmer skeleton rows via a
  shared `skeletonCell()` helper. Members / POS transactions / inventory.
- **Branch transfers in Reports** (v31, v32) — give-outs and returns also
  insert `stock_movements` rows (`transfer_out` / `transfer_in`) with the
  branch username and the give-stock note as the reason.

### Fixed
- **Paginated tables stuck past row 25** (`1f621ab`) —
  `PaginatedDataTable.onPageChanged` passes the **first row index**, not a
  page number; all three tables called `_fetchServerPage(pageIndex + 1)`,
  requesting a nonexistent far-off page. Replaced with
  `_ensureLoadedThrough(rowCount)`. Also: the POS table's `rowCount` used the
  raw sale count while rows are *grouped* (a multi-item checkout renders as
  one row), leaving permanent phantom rows; it now collapses to the exact
  group count once fully loaded.
- **Request history status counts** (`c48eddf`) — the Status chips counted
  only `pending_requests` and ignored `withdrawal_requests`, despite
  withdrawals rendering in the same list and having their own Action chip.
- **Chairman's Bonus wording** (`af7cdba`, `c48eddf`) — v24 made the bonus
  per-direct-referral and set `chairmanFridays = 0` unconditionally; the UI
  still advertised "₱X / Friday". Removed the dead `_chairmanFridays` field
  and its "(N Fridays)" label suffixes. The Friday-gated *withdrawal* rule is
  unrelated and untouched.
- **UpdateDialog crash on dispose** (`6d19dff`) —
  `context.read<UpdaterService>()` in `dispose()` throws once the widget is
  deactivated. Service reference is now captured in `initState`.

---

## Database migrations

| Migration | Purpose | Staging | Prod |
|---|---|---|---|
| v28 | `is_staff()` includes `branch_cashier` | ✅ | ✅ |
| v29 | `profiles.mobile_enabled` | ✅ | ✅ |
| v30 | `branch_stock`, `stock_transfers`, RPCs | ✅ | ✅ |
| v31 | Branch transfers → `stock_movements` | ✅ | ✅ |
| v32 | Give-stock note in the Reports reason | ✅ | ✅ |
| v33 | RLS + SELECT policies for branch stock | ✅ | ✅ |
| v34 | `get_member_earnings_sources` RPC | ✅ | ✅ |
| v35 | Admin fund adjustments + `is_adjustment` | ❌ | ❌ |

Each has a matching script in `supabase/rollbacks/`.

### v35 must ship before the build that uses it

v35 is additive and safe to apply on its own — a v1.3.0 client keeps working
against it, because the extra `is_adjustment` column is simply ignored. The
reverse is not true: a build with the Adjust Funds dialog against a v34
database fails at the RPC call. **Apply v35 to prod before releasing the
next binary.**

The `note` column and the `fund_adjustments` table are the two things worth
preserving on any rollback — part 3 of the rollback script is destructive and
commented out for that reason.

### Why v34 must be SECURITY DEFINER

Production RLS restricts a member to their **own** rows:

```
members_select : is_staff() OR id = my member_id
sales_select   : is_staff() OR buyer_id = my member_id
```

So resolving a downline's name client-side returns zero rows — silently,
because RLS *filters* rather than errors — and every entry renders "Source
not recorded". v34 resolves the joins server-side under table-owner rights,
with the same staff-or-self authorization as `get_member_earnings`. No policy
is loosened.

> Note: `supabase/schema/enable_rls_staff.sql` in this repo uses
> `using (true)` for these tables. **Production does not match it** and is
> stricter. Don't assume the repo script reflects prod.

### Rollout order

1. **Migrations first** — invisible to older clients, reversible.
2. **Redeploy Edge Functions** `create-user` / `update-user` to prod
   (`update-user` must accept `mobile_enabled`).
3. **Release the app.**
4. **Create `branch_cashier` accounts last** — `UserRole.fromString` throws
   on an unknown role, so the new build must be deployed before the first
   such account exists.

Full sequence: `docs/prod_rollout_checklist.md`.

---

## Known limitations

- **Upgrade Bonus rows carry no member link.** The upgrade RPC inserts
  without `item_id`, so the breakdown falls back to the label. 1 of 66 rows
  on the prod account checked. Fixable going forward with a one-line change
  to the RPC; **not** backfillable — the link was never written.
- **Pre-v20 / hand-imported ledger rows have no `item_id`/`sale_id`.** Prod
  data is fully attributed (118/118 referral rows match a member). The
  staging dummy reseller is not (51/51 unattributed), since it was inserted
  as raw `VALUES` — don't judge the feature by that account.
- **Android builds now require `--flavor`.** `flutter build apk` and
  `flutter run` need `--flavor prod` (or `staging`). Desktop unaffected.

---

## Version numbering — read before releasing

`pubspec.yaml` is `1.0.0+1` but the last tag is `v1.2`. The updater compares
the **release tag** against the **app's pubspec version**, so this mismatch
means clients may not see an update. Before releasing, set pubspec above
`1.2` (e.g. `1.3.0+3`) and tag to match.

Tag with plain numeric versions (`v1.3.0`). `_parseVersion` reads only the
leading digits of each segment, so `1.3.0-rc1` and `1.3.0-rc2` compare
**equal** and the second would never be offered.
