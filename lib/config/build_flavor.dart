import 'package:flutter/material.dart';

/// Which build of the app this binary is.
///
/// Selected at COMPILE time via `--dart-define=APP_FLAVOR=staging`; anything
/// else (including omitting it) yields [AppFlavor.production], so a normal
/// `flutter build` can never accidentally produce a staging binary.
enum AppFlavor {
  production,
  staging;

  static const _defined = String.fromEnvironment(
    'APP_FLAVOR',
    defaultValue: 'production',
  );

  /// The flavor this binary was compiled as.
  static final AppFlavor current = _defined.trim().toLowerCase() == 'staging'
      ? AppFlavor.staging
      : AppFlavor.production;

  bool get isStaging => this == AppFlavor.staging;
  bool get isProduction => this == AppFlavor.production;
}

/// Flavor-derived identity used across the app (updater channel, storage
/// namespace, on-screen badge). Keep every flavor difference here so there is
/// one place to audit when adding a new environment.
class BuildConfig {
  const BuildConfig._();

  static AppFlavor get flavor => AppFlavor.current;
  static bool get isStaging => flavor.isStaging;

  /// Human-readable suffix for window titles / about screens.
  /// Empty on production so nothing changes for real users.
  static String get titleSuffix => isStaging ? ' (Staging)' : '';

  /// Short label for the on-screen badge. Null on production (no badge).
  static String? get badgeLabel => isStaging ? 'STAGING' : null;

  /// Badge colour — deliberately loud so a staging build is never mistaken
  /// for production during a client demo.
  static const Color badgeColor = Color(0xFFC2410C); // burnt orange

  // ── Supabase project pinning ─────────────────────────────────────
  // Each flavor may only talk to ONE Supabase project. The bundled
  // assets/supabase_config.json is a FALLBACK that points at production, so
  // forgetting --dart-define=SUPABASE_URL on a staging build would silently
  // connect a "STAGING"-labelled app to live data. Pinning the project ref
  // per flavor turns that silent mistake into a startup failure.
  //
  // If you ever migrate a project, update the ref here in the same commit.
  static const String _productionRef = 'cyfyydzxdsdzycbpvqox';
  static const String _stagingRef = 'sisyujbpcueifeonnzfw';

  /// The only Supabase project ref this binary is allowed to reach.
  static String get expectedProjectRef =>
      isStaging ? _stagingRef : _productionRef;

  /// Validate that [url] targets this flavor's project.
  ///
  /// Returns `null` when the pairing is correct, otherwise a human-readable
  /// error. Returns `null` for an empty/unparseable URL so the existing
  /// "Supabase is not configured" path keeps reporting that instead.
  static String? supabaseMismatch(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return null;
    final ref = host.split('.').first;
    if (ref == expectedProjectRef) return null;

    final flavorName = isStaging ? 'STAGING' : 'PRODUCTION';
    final expectedName = isStaging ? 'staging' : 'production';
    return 'Build/database mismatch: this is a $flavorName build but it is '
        'pointed at Supabase project "$ref". It may only connect to the '
        '$expectedName project "$expectedProjectRef".\n\n'
        'Pass the correct credentials at build time, e.g.\n'
        '  --dart-define=SUPABASE_URL=https://$expectedProjectRef.supabase.co\n'
        '  --dart-define=SUPABASE_ANON_KEY=<$expectedName publishable key>\n'
        'See docs/staging_builds.md.';
  }

  // ── A note on local storage ──────────────────────────────────────
  // On Windows both flavors install to different folders but share the
  // same %APPDATA% dir (CompanyName/ProductName are compiled into
  // windows/runner/Runner.rc). Logins still do NOT bleed across builds:
  // supabase_flutter stores its session under
  //     sb-<project-ref>-auth-token
  // and the two flavors point at different Supabase projects, so the keys
  // are already distinct. No extra namespacing is needed — but if a future
  // flavor ever shares a Supabase project with another, revisit this.
}
