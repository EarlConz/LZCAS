<!--
Guidance for AI coding agents working on the LZCAS Flutter app.
Keep this short, concrete and focused on discoverable project patterns.
--> 
# Copilot instructions for LZCAS

This file gives concise, actionable signals for AI coding agents editing the LZCAS Flutter app.

Key facts (read before making changes)
- Single-app Flutter project. Entrypoint: `lib/main.dart` which creates and exposes a global `repository` (type `DbRepository`) used throughout UI code.
- Database layer lives under `lib/db/` (main files: `app_db.dart`, `db_repository.dart`, `db.dart`). The app uses Drift for local persistence.
- UI is in `lib/pages/`, `lib/buttons/`, `lib/dialogs/` and `lib/widgets/`. Follow existing widget patterns (stateless parent pages with small stateful dialogs/components).

Architecture and important flows
- Initialization: `main()` calls `initDb()` (see `lib/data/db_init.dart`) and constructs `repository = DbRepository(db)`. Use `repository` for all DB operations — do not instantiate `AppDb` directly in UI code.
- Data flow: UI reads via `repository.fetch*()` methods, writes via `repository.add*/update*/delete*()` helpers. After DB mutations the repository emits simple change events on a broadcast stream (`DbRepository.changes`) — prefer using repository helpers so notifications are emitted.
- Sales flow example: see `lib/buttons/sellbutton.dart` — it fetches items and members via `repository.fetchItems()/fetchMembers()` and calls `repository.addSale()` + `repository.updateItem()` during confirm.

Project conventions
- Single global `repository` exported from `lib/db/db.dart` (re-exported from `lib/main.dart`). Import `package:lzcas/db/db.dart` in UI code to get `repository` and typed models (Item, Member, Sale).
- Drift models: table classes (`Items`, `Members`, `Sales`) are in `lib/db/app_db.dart`. Use companion classes (e.g. `ItemsCompanion.insert(...)`) via repository helpers.
- Seeds & CSV I/O: seed data helpers and CSV import/export live in `lib/db/*.dart` (see `seed_data.dart`, `csv_io.dart`). For bulk import use `DbRepository.import*Csv()`.
- UI pattern: pages are mostly stateless and obtain data by calling repository methods (often in `initState()` of stateful subwidgets). Dialog widgets are self-contained stateful classes (see `lib/dialogs/*`). Keep dialog logic local unless it must change DB state, in which case call repository helpers.

Build / test / dev notes
- Use standard Flutter commands. Typical quick local run:
  - flutter pub get
  - flutter run (select target platform)
- Code generation: Drift uses `drift_dev` + `build_runner`. If you change `app_db.dart` or migrations run:
  - flutter pub run build_runner build --delete-conflicting-outputs
- Tests: there are a small number of unit/widget tests under `test/`. Run them with `flutter test`.

Patterns and gotchas
- Always update item stock via `DbRepository.updateItem(...)` rather than calling DB update directly so the repository can emit change events.
- When reading rows you may see helper converters in `lib/db/seed_data.dart` (e.g. `inventoryItemsFromRows`, `membersFromRows`) — reuse them for consistent mapping.
- UI uses synchronous showDialog builders that call repository methods (e.g. `await repository.fetchItems()`) — be defensive around mounted checks and prefer `if (!mounted) return` after async awaits inside widgets.
- Input validation: some dialogs (e.g. `sellbutton.dart`) enforce numeric-only input using `FilteringTextInputFormatter.digitsOnly` — follow that pattern for price/quantity fields.

Files to inspect for examples
- `lib/main.dart` — app startup and global `repository` export.
- `lib/db/db_repository.dart` — canonical DB helpers and change stream usage.
- `lib/db/app_db.dart` — Drift table definitions and generated models.
- `lib/buttons/sellbutton.dart` — a longer example of UI -> repository interactions, validation, and dialog patterns.
- `lib/pages/*` and `lib/dialogs/*` — small components and their patterns.

What to avoid
- Do not bypass `DbRepository` when mutating DB state (no direct calls to `AppDb.insert*/update*/delete*` from UI files).
- Avoid adding side-effecting global state beyond the existing `repository` pattern.

If uncertain, ask the maintainer for:
- preferred testing workflow for platform-specific features (camera, Windows camera plugin),
- any database migration policy beyond schemaVersion = 1 in `app_db.dart`.

---
If this file needs updates or you want additional examples, leave a short note and I will expand specific areas.
