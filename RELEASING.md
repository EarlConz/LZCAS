# Releasing GUTVita (APK + EXE)

How to rebuild and ship the mobile (Android APK) and desktop (Windows EXE)
apps after making **app-code (Dart) changes**.

> Database-only changes (SQL migrations / RPC functions) do **NOT** need a
> rebuild — the app reads them live. You only rebuild when Dart code changes.

## 0. Before you build

1. **Bump the version** in `pubspec.yaml`:
   ```yaml
   version: 1.0.1+2   # format is  <name>+<buildNumber>
   ```
   Increment the **build number** (`+2`, `+3`, …) every release — Android uses
   it to recognize an update.
2. Sanity check: `flutter analyze` (no new errors) and test the app.
3. If the logo/app-icon changed, re-run: `dart run flutter_launcher_icons`.

## 1. Android APK

```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

- It is signed automatically with the **release keystore** via
  `android/key.properties`.
- Optional smaller builds (per CPU): `flutter build apk --release --split-per-abi`.

### ⚠️ The #1 rule: never lose the keystore
Users update in place **only** if every APK is signed with the **same key**.
- Keep `android/key.properties` and the `.jks`/`.keystore` file it points to
  **safe and backed up** (they are intentionally NOT in git).
- If that key is lost or changed, users must **uninstall the old app first**
  before installing the new one — an in-place update will fail. So guard it.

## 2. Windows EXE

```bash
flutter build windows --release
```
Output folder: `build/windows/x64/runner/Release/`

- Ship the **entire `Release/` folder**, not just `gutvita.exe` — it needs the
  DLLs and the `data/` folder beside it to run.
- Distribute by either:
  - **Zipping** the whole `Release/` folder, or
  - Building an **installer** (e.g. Inno Setup / MSIX) that bundles it.

## 3. Distribute

- **APK:** share the file (direct download link, etc.). Users install/update.
- **EXE:** share the zip/installer. Users replace their copy.
- There is no auto-update — users update manually. Plan accordingly.

## 4. Backward compatibility (important for a live backend)

Because the app and the Supabase database are decoupled and users update at
their own pace, **old app versions keep running against the live DB**. So:

- **Don't break the DB contract that old apps depend on** until everyone has
  updated: keep RPC return keys stable, and keep (don't drop) columns old apps
  still read. (This is why removed columns like `repeat_purchase_json` /
  `commission_rate` were left inert rather than dropped.)
- Deploy DB migrations **before or with** the app release, never an app release
  that assumes a migration you haven't run.

## 5. Quick checklist

- [ ] Bump `version:` in `pubspec.yaml` (build number +1)
- [ ] `flutter analyze` clean
- [ ] `flutter build apk --release`  → test the APK on a device
- [ ] `flutter build windows --release` → test the EXE
- [ ] Keystore + `key.properties` backed up
- [ ] Any required DB migrations already applied to production
- [ ] Distribute APK + zipped `Release/` folder
