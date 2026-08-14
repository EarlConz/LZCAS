import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/build_flavor.dart';

class SupabaseConfig {
  static const _definedUrl = String.fromEnvironment('SUPABASE_URL');
  static const _definedAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String _assetUrl = '';
  static String _assetAnonKey = '';

  static String get url =>
      _normalizeUrl(_definedUrl.isNotEmpty ? _definedUrl : _assetUrl);
  static String get anonKey =>
      _definedAnonKey.isNotEmpty ? _definedAnonKey : _assetAnonKey;

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static Future<void> loadAssetConfig() async {
    if (_definedUrl.isNotEmpty && _definedAnonKey.isNotEmpty) return;

    try {
      final raw = await rootBundle.loadString('assets/supabase_config.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _assetUrl = (data['url'] ?? '').toString().trim();
      _assetAnonKey = (data['anonKey'] ?? '').toString().trim();
    } catch (_) {
      _assetUrl = '';
      _assetAnonKey = '';
    }
  }

  static String _normalizeUrl(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return trimmed;
    }

    final restIndex = uri.pathSegments.indexOf('rest');
    if (restIndex != -1 &&
        uri.pathSegments.length > restIndex + 1 &&
        uri.pathSegments[restIndex + 1] == 'v1') {
      return uri.replace(path: '', query: '', fragment: '').toString();
    }

    return trimmed;
  }
}

Future<bool> initSupabase() async {
  await SupabaseConfig.loadAssetConfig();

  if (!SupabaseConfig.isConfigured) {
    // Supabase is optional for now so the app can still run fully offline.
    return false;
  }

  // Refuse to connect if this build is aimed at the wrong project — checked
  // BEFORE initialize() so a mis-built binary never touches the database.
  final mismatch = BuildConfig.supabaseMismatch(SupabaseConfig.url);
  if (mismatch != null) {
    throw StateError(mismatch);
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  return true;
}

SupabaseClient get supabaseClient => Supabase.instance.client;
