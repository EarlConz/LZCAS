# GUTVita (LZCAS)

**GUTVita** is a cross-platform inventory management and multi-level marketing (MLM) POS system built with Flutter and Supabase. It supports role-based dashboards for administrators, inventory staff, cashiers, branch cashiers, members, and resellers — all backed by a real-time PostgreSQL database.

---

## Core Features

- **Role-Based Dashboards** — Six user roles (Admin, Inventory, Cashier, Branch Cashier, Member, Reseller) each with tailored views and access controls enforced both at the router and widget level.
- **Inventory Management** — Full CRUD for products with categories, low-stock thresholds, stock movements, and real-time status (Good / Low Stock / Out of Stock).
- **Point-of-Sale (POS) Terminal** — Process sales with barcode/QR scanning, quantity controls, per-item pricing, and receipt generation.
- **Member & MLM System** — Member profiles with package subscriptions, referral trees, hierarchy rankings, and automated commission/payout tracking (`directReferralBonus`, `indirectReferralBonus`, `chairmanBonus`, `groupSalesDirect`, `groupSalesIndirect`, `upgradeReferralBonus`).
- **Package Management** — Configurable membership packages with tiered pricing, hierarchy ranks, and per-package bonus structures.
- **QR Code Generation & Scanning** — Generate QR codes for members and scan product barcodes / member QR codes via `mobile_scanner` and `zxing2`.
- **CSV Import/Export** — Bulk import and export of inventory items and sales records.
- **Pending Requests** — Cashiers and inventory staff can submit deletion and stock-reduction requests for admin approval.
- **In-App Notifications** — Real-time badge counts for pending requests and low-stock alerts (admin dashboard).
- **In-App Auto-Updater** — Checks GitHub Releases for new versions at login (all roles) and offers a one-click download + install flow with progress tracking. Manual trigger available in Admin → Settings.
- **Global Configuration** — Admin-configurable currency symbol, notification toggles, and per-category low-stock thresholds stored in Supabase.
- **Dark Mode Support** — Full light/dark theme with a custom design system (orange primary, royal-blue secondary).

---

## Supported Platforms

| Platform    | Status                                         |
| ----------- | ---------------------------------------------- |
| **Android** | ✅ Release builds (APK signed via keystore)    |
| **Windows** | ✅ Release builds (EXE + Inno Setup installer) |
| **Web**     | ✅ Configured (launcher icon + build target)   |
| **macOS**   | ✅ Project scaffold present                    |
| **Linux**   | ✅ Project scaffold present                    |
| **iOS**     | ✅ Project scaffold present                    |

> **Note:** Cashier, Inventory, and Branch Cashier roles are **desktop-only**. They are force-signed-out on mobile. Admin, Member, and Reseller roles work across all platforms.

---

## Tech Stack

| Layer                   | Technology                                                                                                                                              |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Framework**           | [Flutter](https://flutter.dev/) 3.x (Dart SDK ^3.9.0)                                                                                                   |
| **Backend / DB**        | [Supabase](https://supabase.com/) (PostgreSQL + Auth + Edge Functions)                                                                                  |
| **State Management**    | [Provider](https://pub.dev/packages/provider) (ChangeNotifier-based)                                                                                    |
| **HTTP Client**         | [Dio](https://pub.dev/packages/dio) + [http](https://pub.dev/packages/http)                                                                             |
| **Auth**                | Supabase Auth (email/password) with session persistence                                                                                                 |
| **Charts**              | [fl_chart](https://pub.dev/packages/fl_chart)                                                                                                           |
| **QR / Barcode**        | [mobile_scanner](https://pub.dev/packages/mobile_scanner), [zxing2](https://pub.dev/packages/zxing2), [qr_flutter](https://pub.dev/packages/qr_flutter) |
| **Auto-Updater**        | GitHub REST API + Dio download with native `HttpClient` fallback                                                                                        |
| **File Handling**       | [file_selector](https://pub.dev/packages/file_selector), [csv](https://pub.dev/packages/csv), [open_filex](https://pub.dev/packages/open_filex)         |
| **Secure Storage**      | [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)                                                                               |
| **Fonts**               | [google_fonts](https://pub.dev/packages/google_fonts) (Satoshi)                                                                                         |
| **Installer (Windows)** | [Inno Setup](https://jrsoftware.org/isinfo.php)                                                                                                         |
| **Code Generation**     | [build_runner](https://pub.dev/packages/build_runner)                                                                                                   |
| **Linting**             | [flutter_lints](https://pub.dev/packages/flutter_lints)                                                                                                 |

---

## Prerequisites & Environment Setup

### Required Tools

- **Flutter SDK** 3.x (Dart ^3.9.0) — [Install guide](https://docs.flutter.dev/get-started/install)
- **Android Studio** (for Android builds + emulator)
- **Visual Studio 2022** with "Desktop development with C++" (for Windows builds)
- **Supabase project** — [Create one here](https://supabase.com/dashboard)
- **Inno Setup 6** (optional — for building Windows installer)

### Supabase Setup

1. Create a Supabase project at [supabase.com/dashboard](https://supabase.com/dashboard).
2. In the SQL Editor, run the baseline schema:
   ```
   supabase/schema/schema.sql
   supabase/schema/enable_rls_staff.sql
   supabase/schema/schema_category_delete_guard.sql
   ```
3. Apply migrations in ascending version order from `supabase/migrations/`.
4. Deploy Edge Functions from `supabase/functions/` (`create-user`, `create-member-user`, `delete-user`, `update-user`).
5. Copy your **Project URL** and **anon public key** from Supabase → Settings → API.

### Local Configuration

1. Copy the example config and fill in your Supabase credentials:

   ```powershell
   cp supabase.local.example.json supabase.local.json
   ```

   Edit `supabase.local.json`:

   ```json
   {
     "SUPABASE_URL": "https://your-project.supabase.co",
     "SUPABASE_ANON_KEY": "eyJhbGciOi..."
   }
   ```

   > ⚠️ `supabase.local.json` is git-ignored. Never commit real keys.

2. Install dependencies:
   ```bash
   flutter pub get
   ```

---

## How to Build & Run

### Local Development

```bash
# Windows (desktop)
flutter run -d windows --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<key>

# Android (mobile) — using PowerShell helper
.\tools\run_mobile.ps1

# Or manually:
flutter run -d <device-id> --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<key>
```

The `tools/run_mobile.ps1` script reads credentials from `supabase.local.json` and passes them as `--dart-define` flags. Use `-DeviceId <id>` to target a specific device.

### Release Builds

```bash
# Android APK
flutter build apk --release
# Output: build\app\outputs\flutter-apk\app-release.apk

# Windows EXE
flutter build windows --release
# Output: build\windows\x64\runner\Release\  (ship entire folder)

# Windows Installer (Inno Setup)
# 1. Bump version in installer.iss
# 2. Open installer.iss in Inno Setup Compiler → Build → Compile
# Output: installer_output\LZCAS_Setup_vX.Y.Z.exe
```

### Static Analysis

```bash
flutter analyze
```

### Code Generation (if schema changes)

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

---

## Release & Auto-Updater Workflow

The app includes a built-in auto-updater that queries the [GitHub Releases API](https://api.github.com/repos/EarlConz/LZCAS/releases/latest) after every successful login. Here's the full release workflow:

### 1. Prepare the Release

1. **Bump the version** in `pubspec.yaml`:

   ```yaml
   version: 1.0.1+2 # <name>+<buildNumber>
   ```

   Increment the build number every release — Android uses it to recognize updates, and the updater compares semantic versions.

2. **Run static analysis**: `flutter analyze` — ensure no new errors.

3. **Rebuild launcher icons** (if the logo changed):
   ```bash
   dart run flutter_launcher_icons
   ```

### 2. Build Binaries

```bash
# Android
flutter build apk --release
# → build\app\outputs\flutter-apk\app-release.apk

# Windows (EXE folder)
flutter build windows --release
# → build\windows\x64\runner\Release\

# Windows (Installer via Inno Setup)
# Update installer.iss with the new version, then compile.
# → installer_output\LZCAS_Setup_vX.Y.Z.exe
```

### 3. Create a GitHub Release

1. Go to [GitHub Releases](https://github.com/EarlConz/LZCAS/releases).
2. Click **Draft a new release**.
3. Set the **tag** to match the version (e.g., `v1.0.1` — the auto-updater strips the leading `v`).
4. Write **release notes** in the description — these appear in the in-app update dialog as the changelog.
5. Upload the platform binaries as release assets. **Name them so the auto-updater can match the current OS:**

   | Platform | Recommended Asset Name              |
   | -------- | ----------------------------------- |
   | Android  | `GUTVita-v1.0.1.apk`                |
   | Windows  | `GUTVita-Setup-1.0.1.exe` or `.msi` |
   | macOS    | `GUTVita-1.0.1.dmg` or `.pkg`       |
   | Linux    | `GUTVita-1.0.1.AppImage` or `.deb`  |

   The updater matches assets by file extension: `.apk` (Android), `.exe`/`.msi` (Windows), `.dmg`/`.pkg` (macOS), `.AppImage`/`.deb`/`.tar.gz` (Linux).

6. Publish the release.

### 4. Auto-Update Flow

- On next login, every user's dashboard calls `UpdaterService.checkForUpdate()`.
- If the remote `tag_name` is newer than the local `package_info_plus` version, a themed dialog appears showing the version and release notes.
- Tapping **"Update Now"** downloads the binary to the temp directory with a progress bar.
- On completion, the app opens the installer/APK via `open_filex`.
- A manual **"Check for Updates"** button is also available in Admin → Settings.

---

## Folder Structure

```
LZCAS/
├── lib/                          # Dart source code
│   ├── main.dart                 # App entry point, provider setup, Supabase init
│   ├── theme.dart                # GUTVita design system (colors, typography, shapes)
│   ├── auth/                     # Authentication module
│   │   ├── auth.dart             # Barrel export
│   │   ├── auth_state.dart       # AuthState (ChangeNotifier) — login, logout, session, roles
│   │   ├── role_visibility.dart  # RoleVisibility widget + assertRoleOrThrow
│   │   ├── api_client.dart       # Dio wrapper with CSRF + auth token injection
│   │   └── csrf_interceptor.dart # CSRF token interceptor
│   ├── data/                     # Data layer (Supabase-backed)
│   │   ├── models.dart           # Item, Member, Sale, Package, Category, etc.
│   │   ├── supabase_repository.dart # SupabaseRepository (all DB operations)
│   │   └── supabase_config.dart  # Supabase initialization
│   ├── db/                       # Database barrel + CSV helpers
│   │   ├── db.dart               # Global repository getter
│   │   └── csv_header_utils.dart # CSV column mapping
│   ├── router/                   # Navigation & access control
│   │   ├── app_router.dart       # onGenerateRoute with role-based routing
│   │   └── route_guard.dart      # AppRoutes + RouteGuard (auth + role checks)
│   ├── pages/                    # Screen pages (one file per role dashboard)
│   │   ├── landing_page.dart     # Public brand landing
│   │   ├── login_page.dart       # Email/password login
│   │   ├── admin/                # Admin dashboard (9 tabs)
│   │   ├── cashier/              # Cashier dashboard (POS, members, requests)
│   │   ├── inventory/            # Inventory dashboard (CRUD, reports, requests)
│   │   ├── branch/               # Branch cashier dashboard (POS, stock)
│   │   ├── member/               # Member/reseller dashboard
│   │   ├── homepage.dart         # Legacy shared HomePage
│   │   ├── dashboardpage.dart    # Shared analytics dashboard widget
│   │   └── ...                   # Additional shared pages
│   ├── widgets/                  # Reusable UI components
│   │   ├── stockpile_sidebar.dart / stockpile_topbar.dart
│   │   ├── inventorytable.dart / transactionstable.dart / memberstable.dart
│   │   ├── saleschart.dart / metric_card.dart / donut_chart.dart
│   │   ├── member_sidebar.dart / memberqr.dart / qrgenerator.dart
│   │   └── ...                   # 28 widget files total
│   ├── dialogs/                  # Reusable dialog components
│   │   ├── update_dialog.dart    # Auto-updater dialog (download + install)
│   │   ├── confirmation_dialog.dart / edit_member_dialog.dart
│   │   ├── sale_cart_editor.dart / receipt_dialog.dart
│   │   └── ...                   # 14 dialog files total
│   ├── buttons/                  # Action button components
│   │   ├── sellbutton.dart       # POS sale flow
│   │   ├── qrscanbutton.dart     # QR scan trigger
│   │   └── inventoryfilterbutton.dart
│   ├── services/                 # App-wide services (ChangeNotifiers)
│   │   ├── updater_service.dart  # GitHub auto-updater
│   │   ├── notification_service.dart # In-app notification badge tracking
│   │   └── config_service.dart   # Global config (currency, categories, thresholds)
│   └── utils/                    # Utilities
│       ├── fonts.dart            # Satoshi font loader
│       ├── animations.dart       # Reusable animations
│       ├── action_guard.dart     # Debounced action guard
│       ├── toast_utils.dart      # Toast helpers
│       └── formatters.dart / phone_formatter.dart
├── android/                      # Android platform (Gradle, keystore, manifest)
├── windows/                      # Windows platform (CMake, runner)
├── macos/ / linux/ / ios/ / web/ # Other platform scaffolds
├── assets/
│   ├── images/                   # Logo, landing banners
│   └── supabase_config.json      # Fallback Supabase config
├── supabase/                     # Database schema & migrations
│   ├── schema/                   # Baseline SQL (tables, RLS, functions)
│   ├── migrations/               # Versioned migrations (v2–v28)
│   ├── functions/                # Edge Functions (create-user, etc.)
│   ├── rollbacks/                # Migration undo scripts
│   └── diagnostics/ / maintenance/
├── tools/
│   ├── run_mobile.ps1            # Mobile run helper (loads supabase.local.json)
│   └── stress-test.js            # Stress testing script
├── docs/                         # Planning & debugging docs
├── installer.iss                 # Inno Setup script for Windows installer
├── pubspec.yaml                  # Flutter dependencies & metadata
├── analysis_options.yaml         # Dart linting rules
├── RELEASING.md                  # Detailed release guide
├── GEMINI.md                     # Developer technical overview
├── supabase.local.example.json   # Template for local Supabase credentials
└── README.md                     # You are here
```

---

## Architecture Notes

- **State Management**: The app uses `Provider` with `ChangeNotifier`. Global services (`AuthState`, `ConfigService`, `NotificationService`, `UpdaterService`) are registered in `main.dart` via `MultiProvider` and accessed throughout the widget tree.
- **Data Layer**: All database operations go through `SupabaseRepository` (exposed as the global `repository` getter from `lib/db/db.dart`). UI code never calls Supabase directly. The repository emits change events on a broadcast stream for reactive updates.
- **Auth Flow**: Supabase Auth handles email/password login with automatic session persistence. `AuthState` listens to `onAuthStateChange` and loads the user's role from the `profiles` table. The router enforces role-based access via `RouteGuard`.
- **Design System**: All colors, typography, and shapes are centralized in `lib/theme.dart`. Widgets use `StockpileColors` and `StockpileFonts.satoshi()` — no hardcoded colors or fonts in UI code.
- **Releases**: See `RELEASING.md` for the complete release checklist including keystore management, backward compatibility rules, and distribution steps.

---

## Key Dependencies

| Package                                    | Purpose                                    |
| ------------------------------------------ | ------------------------------------------ |
| `supabase_flutter`                         | Backend-as-a-Service (DB, Auth, real-time) |
| `provider`                                 | State management                           |
| `dio`                                      | HTTP client with interceptors              |
| `fl_chart`                                 | Analytics charts (line, bar, donut)        |
| `mobile_scanner` / `zxing2` / `qr_flutter` | QR/barcode scanning and generation         |
| `package_info_plus`                        | App version detection (for auto-updater)   |
| `open_filex`                               | Launch downloaded installers               |
| `path_provider`                            | Platform temp directories                  |
| `file_selector`                            | File picker for CSV import                 |
| `csv`                                      | CSV parsing/generation                     |
| `flutter_secure_storage`                   | Secure token storage                       |
| `google_fonts`                             | Satoshi font family                        |
| `bot_toast`                                | Toast notifications                        |
| `intl`                                     | Number/date formatting                     |
| `camera` / `camera_windows`                | Camera access for barcode scanning         |

---

## Contributing

1. Follow the existing code patterns — stateless parent pages, stateful dialogs, `ChangeNotifier` services.
2. Use the design system in `lib/theme.dart` — no hardcoded colors or fonts.
3. Route all DB mutations through `SupabaseRepository` (the global `repository`).
4. Add new DB columns via migrations in `supabase/migrations/`.
5. Run `flutter analyze` before committing.
6. Update `RELEASING.md` if the release process changes.
