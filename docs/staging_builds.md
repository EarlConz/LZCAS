# Staging builds (side-by-side with production)

How to produce a **staging** `.exe` / `.apk` your client can run *alongside*
the production app, pointed at the staging Supabase project, that will never
update itself into production.

---

## The four things that keep the builds apart

| Concern | Production | Staging |
|---|---|---|
| Android app id | `com.lzcas.app` | `com.lzcas.app.staging` |
| Android launcher name | GUTVita | GUTVita Staging |
| Windows installer `AppId` | `{3A9C1E57-…}` | `{B7E4A2C1-…}` (distinct GUID) |
| Windows install dir | `Program Files\LZCAS` | `Program Files\GUTVita Staging` |
| Update channel | GitHub **stable** releases | GitHub **pre-releases** |
| Supabase project | prod URL/key | staging URL/key |
| On-screen marker | none | orange `STAGING` ribbon |

Because the Android **application id** and the Windows **AppId** differ, the OS
treats them as two unrelated apps — installing or uninstalling one never
touches the other.

> **Why `AppId` and not `AppName`?** Inno Setup decides "is this an upgrade?"
> from `AppId`. The old script had none, so it defaulted to the name and a
> staging install would have *overwritten production*. The GUIDs in
> `installer.iss` are what prevent that — **do not change them.**

---

## Build commands

`APP_FLAVOR` is what flips the app's behavior (update channel + badge).
Pass the Supabase credentials with `--dart-define` — the bundled
`assets/supabase_config.json` fallback points at **production**, so a build
that omits them is a production build no matter what it's labelled.
(The startup guard now catches this, but don't rely on it.)

> **Shell note:** these are PowerShell one-liners (this is a Windows repo).
> PowerShell continues lines with a backtick `` ` ``, **not** `\` — a
> bash-style `\` gives "Missing expression after unary operator '--'".
> Keeping each command on one line avoids the issue entirely.

### Project refs

| Flavor | Supabase project |
|---|---|
| production | `cyfyydzxdsdzycbpvqox` |
| staging | `sisyujbpcueifeonnzfw` |

### Android — staging APK

```powershell
flutter build apk --release --flavor staging --dart-define=APP_FLAVOR=staging --dart-define=SUPABASE_URL=https://sisyujbpcueifeonnzfw.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_STAGING_PUBLISHABLE_KEY
```

Output: `build/app/outputs/flutter-apk/app-staging-release.apk`

**Rename before uploading** so the updater's flavor check accepts it — the
filename must contain `staging`:

```powershell
Move-Item build/app/outputs/flutter-apk/app-staging-release.apk build/app/outputs/flutter-apk/gutvita-staging-v1.0.0.apk
```

### Android — production APK

```powershell
flutter build apk --release --flavor prod --dart-define=SUPABASE_URL=https://cyfyydzxdsdzycbpvqox.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PROD_PUBLISHABLE_KEY
```

The production filename must **not** contain `staging`.

> Since flavors were added, `--flavor` is **required** — a plain
> `flutter build apk` / `flutter run` for Android now fails.

### Windows — staging installer

```powershell
flutter build windows --release --dart-define=APP_FLAVOR=staging --dart-define=SUPABASE_URL=https://sisyujbpcueifeonnzfw.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_STAGING_PUBLISHABLE_KEY
iscc /DSTAGING installer.iss
```

Output: `installer_output/GUTVita_Staging_Setup_v1.0.0.exe`

### Windows — production installer

```powershell
flutter build windows --release --dart-define=SUPABASE_URL=https://cyfyydzxdsdzycbpvqox.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PROD_PUBLISHABLE_KEY
iscc installer.iss
```

Output: `installer_output/LZCAS_Setup_v1.0.0.exe`

> ⚠️ The Windows build output folder is the **same path** for both flavors
> (`build/windows/x64/runner/Release`). Always run `flutter build windows`
> for the flavor you're about to package, immediately before `iscc`.
> Building staging then compiling the production installer would ship a
> staging binary as production.

---

## Publishing releases

One GitHub repo, two channels. GitHub's `/releases/latest` endpoint
**excludes pre-releases**, which is what isolates them.

### Staging release (only staging clients see it)

1. Draft a new release, tag e.g. `v1.1.0-staging.1`
2. ✅ **Tick "Set as a pre-release"** ← the critical step
3. Attach `GUTVita_Staging_Setup_*.exe` and `gutvita-staging-*.apk`

### Production release (only production clients see it)

1. Draft a new release, tag e.g. `v1.1.0`
2. ❌ **Leave "Set as a pre-release" unticked**
3. Attach `LZCAS_Setup_*.exe` and the prod `.apk`

### Forcing an update

Add a line to the release notes (works on either channel):

```
min-supported-version: 1.1.0
```

Clients older than that floor get a non-dismissible "Required Update" dialog.
Use it when a release ships DB migrations that break older clients.

---

## Safety nets built in

- **Project pinning (startup guard)** — each flavor may only connect to its
  own Supabase project (`BuildConfig.expectedProjectRef`). The check runs in
  `initSupabase()` *before* `Supabase.initialize()`, so a staging build aimed
  at production refuses to start instead of touching live data. This is the
  net that catches a forgotten `--dart-define`.
- **Flavor-matched assets** — a staging build only accepts a download whose
  filename contains `staging`; production only accepts one that doesn't. If
  the wrong binary is attached to a release, the update fails with "No binary
  found for your platform" instead of silently swapping the client's app.
- **Default is production** — `APP_FLAVOR` defaults to `production`, so a
  plain `flutter build` can never emit a staging binary by accident.
- **Visible ribbon** — staging always shows the orange `STAGING` marker, and
  the window title reads "GUTVita (Staging)".

---

## Verifying it worked

1. Install production, then install staging. Both appear in
   *Add or Remove Programs* / the Android launcher as separate entries.
2. Open staging → orange `STAGING` ribbon top-right; title "GUTVita (Staging)".
3. Log in on staging, then open production → you are **not** logged in there.
   (Sessions are keyed per Supabase project, so they don't share a login.)
4. Publish a stable release → staging does **not** offer it.
   Publish a pre-release → production does **not** offer it.
5. Uninstall staging → production remains installed and working.
