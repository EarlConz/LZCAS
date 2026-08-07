# Supabase SQL

All SQL is applied **manually** via the Supabase SQL editor (paste & run) —
nothing here is auto-migrated. Folders group files by purpose.

```
supabase/
├── functions/     Edge Functions (create-user, create-member-user, …)
├── schema/        Baseline objects — run on a fresh project
├── migrations/    Ordered, apply-once changes (v2 … v24)
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

> **Currently live: v26.** All five bonuses (Direct/Indirect Referral, Group
> Sales, Upgrade, Chairman) are stored `member_transactions` rows the RPC sums —
> none recomputed live, so editing package rates never changes history. Direct/
> Indirect are availment-based + min-tier capped; Chairman is availment-gated at
> the earner's own rate. Referral bonuses crystallize at first availment (with
> catch-up), frozen thereafter.

## rollbacks/
`rollback_get_member_earnings_vNN.sql` restores the function/behavior as it was
**before** the next migration (e.g. `…_v24.sql` reverts v24 back to v23). Run
one only if you need to undo the corresponding migration.

## diagnostics/
Read-only — safe on the live DB, write nothing.
- `diagnose_member_earnings.sql` — itemize one member's earnings (set the id at
  the top). Reconciles every peso to its source.
- `preview_v21…`, `preview_v22…` — impact previews for those specific migrations.

## maintenance/
⚠️ Destructive. `reset_tables.sql` / `deploy_reset.sql` wipe or reset data —
only for a fresh setup or a deliberate reset, never on live data you're keeping.
