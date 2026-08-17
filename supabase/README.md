# Supabase SQL

All SQL is applied **manually** via the Supabase SQL editor (paste & run) —
nothing here is auto-migrated. Folders group files by purpose.

```
supabase/
├── functions/     Edge Functions (create-user, create-member-user, …)
├── schema/        Baseline objects — run on a fresh project
├── migrations/    Ordered, apply-once changes (v2 … v34)
├── rollbacks/     Undo scripts, paired with a migration
├── diagnostics/   Read-only tools (write nothing)
└── maintenance/   Destructive/reset scripts — use with care
```

## schema/
Run these first on a brand-new project, in this order:
1. `schema.sql` — tables, packages, withdrawal_requests, core objects.
2. `enable_rls_staff.sql` — RLS policies + `is_staff()` helper.
3. `schema_category_delete_guard.sql` — category-delete guard.

(`schema.sql.bak` is an old snapshot, kept for reference only.)

## migrations/
Numbered changes applied over time. Each file's header explains what it does
and whether it supersedes an earlier one. Apply in ascending version order on a
fresh DB; on an existing DB only the ones not yet applied.

**Earnings / compensation history (the `get_member_earnings` RPC + triggers):**
- v6  — earnings RPC introduced
- v19 — Group Sales frozen at purchase time (triggers)
- v20 — Direct/Indirect Referral frozen; Chairman priced per package-period
- v21 — Chairman: immediate on availment + weekly Friday
- v22 — Chairman: per direct referral, paid that week's Friday
- v23 — Chairman: per direct referral, **immediate**, rate frozen at referral time
- v24 — Chairman becomes a **frozen ledger** (trigger + backfill + RPC sums rows)
- v25 — Direct/Indirect/Chairman become **availment-based**: a referral only
  pays when the referred member avails a package; Direct/Indirect are **min-tier
  capped** (lower of earner's vs referral's package, by `hierarchy_rank`);
  Chairman stays the earner's own rate; package-less members get **catch-up**
  when they later avail. Trigger moves from member-registration to first
  package availment. RPC unchanged.
- v26 — Upgrade Referral Bonus becomes **min-tier capped** too (lower of the
  referrer's package vs the package the downline upgraded to). No current-data
  impact with only two tiers; matters once a 3rd+ tier exists. Redefines
  `process_package_upgrade` + extends `referral_bonus_min_tier` with 'upgrade'.
- v27 — Chairman's Bonus becomes **min-tier capped** too (lower of earner's vs
  referral's first-availed package). Extends the helper with 'chairman',
  redefines the availment trigger's chairman inserts, recomputes the Chairman
  ledger. ⚠️ Changes existing earnings (only downward).

> **Live on prod: v27.** All five bonuses (Direct/Indirect Referral, Group
> Sales, Upgrade, Chairman) are stored `member_transactions` rows the RPC sums —
> none recomputed live, so editing package rates never changes history. Direct/
> Indirect are availment-based + min-tier capped; Chairman is availment-gated at
> the earner's own rate. Referral bonuses crystallize at first availment (with
> catch-up), frozen thereafter.

**Branch Cashier role + Branch Stock (v28–v33)** — *staging only; not yet on
prod. Apply in this exact order:*
- v28 — `is_staff()` accepts the new `branch_cashier` role.
- v29 — `profiles.mobile_enabled` flag (admin-granted mobile login for a branch
  cashier; desktop-only by default). Enforced in-app.
- v30 — Branch stock system: `branch_stock` + `stock_transfers` tables,
  `branch_stock_view`, and RPCs `transfer_stock_to_branch`, `return_branch_stock`,
  `adjust_branch_stock`, `record_branch_sale` (two-tier inventory: central
  `items.stock` + per-branch allocation; give-out deducts central).
- v31 — Give-out/return also log `stock_movements` (`transfer_out`/`transfer_in`)
  so branch transfers show up in Reports as **Branch Out / Branch In**. (adjust is
  not logged — it doesn't change central stock.)
- v32 — Include the give-stock **note** in the Reports movement reason
  (`branch - note`).
- v33 — **RLS + policies** for `branch_stock`/`stock_transfers` (the read fix):
  RLS on, SELECT only; admin/main-cashier see all, a branch cashier sees only
  their own rows. All writes stay locked to the SECURITY DEFINER RPCs.

**Itemised earnings sources (v34)** — *needed on BOTH staging and prod.*

- v34 — `get_member_earnings_sources(p_member_id)`: the per-credit list behind
  each earnings bucket ("Chairman's Bonus — from Maria Santos"). Must be a
  SECURITY DEFINER RPC because RLS limits a member to their **own** rows in
  `members`/`sales`, so resolving downline names client-side silently returns
  nothing and every row renders "Source not recorded". Same staff-or-self
  authorization as `get_member_earnings`. Read-only; changes no policies.
  Ship with the app build that adds the breakdown card.

> **Rollout order (all environments):** DB migrations first (invisible/reversible)
> → app release second (`UserRole.fromString` throws on unknown roles, so the new
> build must ship before any `branch_cashier` account exists) → create accounts
> last. Edge Functions `create-user` / `update-user` must be **deployed** to the
> target project (staging currently) for admin user-management + the mobile flag.

## rollbacks/
`rollback_get_member_earnings_vNN.sql` restores the function/behavior as it was
**before** the next migration (e.g. `…_v24.sql` reverts v24 back to v23). Run
one only if you need to undo the corresponding migration.

Branch cashier / branch stock undo scripts:
- `rollback_mobile_flag_v29.sql` — drop `profiles.mobile_enabled`.
- `rollback_branch_stock_v30.sql` — drop the whole branch-stock system.
- `rollback_branch_transfer_reports_v31.sql` — stop logging transfers to Reports.
- `rollback_branch_transfer_note_v32.sql` — drop the note from the Reports reason.
- `rollback_is_staff_v27.sql` — reverts the `is_staff()` change from v28.
- `rollback_earnings_sources_v34.sql` — drop the earnings-sources RPC (v34).

## diagnostics/
Read-only — safe on the live DB, write nothing.
- `diagnose_member_earnings.sql` — itemize one member's earnings (set the id at
  the top). Reconciles every peso to its source.
- `preview_v21…`, `preview_v22…` — impact previews for those specific migrations.

## maintenance/
⚠️ Destructive. `reset_tables.sql` / `deploy_reset.sql` wipe or reset data —
only for a fresh setup or a deliberate reset, never on live data you're keeping.
