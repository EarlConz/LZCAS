import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}

Future<bool> initSupabase() async {
  if (!SupabaseConfig.isConfigured) {
    // Supabase is optional for now so the app can still run fully offline.
    return false;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  return true;
}

SupabaseClient get supabaseClient => Supabase.instance.client;
